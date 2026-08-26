// SPDX-License-Identifier: MIT

// Campaign 3 feasibility spike: Vulkan external memory -> HIP import on Windows (gfx1100).
// Proves: OPAQUE_WIN32 handle export/import, device UUID match, zero-copy kernel write
// visible to a Vulkan host map, and HIP kernel launch+sync latency on the shared buffer.
#define NOMINMAX
#include <windows.h>
#define VK_USE_PLATFORM_WIN32_KHR
#include <vulkan/vulkan.h>
#include <hip/hip_runtime.h>
#include <cstdio>
#include <cstring>
#include <chrono>
#include <vector>

#define VK_CHECK(x) do { VkResult r_ = (x); if (r_ != VK_SUCCESS) { printf("VK fail %d at %s:%d\n", (int) r_, __FILE__, __LINE__); return 1; } } while (0)
#define HIP_CHECK(x) do { hipError_t e_ = (x); if (e_ != hipSuccess) { printf("HIP fail %s at %s:%d\n", hipGetErrorString(e_), __FILE__, __LINE__); return 1; } } while (0)

__global__ void write_pattern(uint32_t * p, uint32_t n, uint32_t salt) {
    uint32_t i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i < n) p[i] = i * 3u + 7u + salt;
}

int main() {
    const VkDeviceSize BUF_SIZE = 64 * 1024;

    // ---- Vulkan instance + physical device
    VkApplicationInfo app = { VK_STRUCTURE_TYPE_APPLICATION_INFO };
    app.pApplicationName = "hip-interop-spike";
    app.apiVersion = VK_API_VERSION_1_1;
    VkInstanceCreateInfo ici = { VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO };
    ici.pApplicationInfo = &app;
    VkInstance inst;
    VK_CHECK(vkCreateInstance(&ici, nullptr, &inst));

    uint32_t n_pd = 0;
    vkEnumeratePhysicalDevices(inst, &n_pd, nullptr);
    std::vector<VkPhysicalDevice> pds(n_pd);
    vkEnumeratePhysicalDevices(inst, &n_pd, pds.data());

    // HIP device UUID
    hipUUID hip_uuid = {};
    HIP_CHECK(hipDeviceGetUuid(&hip_uuid, 0));

    VkPhysicalDevice pd = VK_NULL_HANDLE;
    for (auto cand : pds) {
        VkPhysicalDeviceIDProperties idp = { VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_ID_PROPERTIES };
        VkPhysicalDeviceProperties2 p2 = { VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PROPERTIES_2 };
        p2.pNext = &idp;
        vkGetPhysicalDeviceProperties2(cand, &p2);
        printf("vk device: %s uuid[0..3]=%02x%02x%02x%02x\n", p2.properties.deviceName,
               idp.deviceUUID[0], idp.deviceUUID[1], idp.deviceUUID[2], idp.deviceUUID[3]);
        if (memcmp(idp.deviceUUID, hip_uuid.bytes, 16) == 0) {
            pd = cand;
            printf("UUID MATCH: %s == hip device 0\n", p2.properties.deviceName);
        }
    }
    if (pd == VK_NULL_HANDLE) {
        // fall back to first discrete AMD device; UUID mismatch is reported, not fatal for the probe
        printf("WARNING: no VK<->HIP UUID match; using device 0 (verify manually)\n");
        pd = pds[0];
    }

    // ---- external-memory capability query for OPAQUE_WIN32 buffers
    VkPhysicalDeviceExternalBufferInfo ebi = { VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_EXTERNAL_BUFFER_INFO };
    ebi.usage = VK_BUFFER_USAGE_STORAGE_BUFFER_BIT | VK_BUFFER_USAGE_TRANSFER_SRC_BIT | VK_BUFFER_USAGE_TRANSFER_DST_BIT;
    ebi.handleType = VK_EXTERNAL_MEMORY_HANDLE_TYPE_OPAQUE_WIN32_BIT;
    VkExternalBufferProperties ebp = { VK_STRUCTURE_TYPE_EXTERNAL_BUFFER_PROPERTIES };
    vkGetPhysicalDeviceExternalBufferProperties(pd, &ebi, &ebp);
    const auto feat = ebp.externalMemoryProperties.externalMemoryFeatures;
    printf("OPAQUE_WIN32 buffer: exportable=%d importable=%d\n",
           !!(feat & VK_EXTERNAL_MEMORY_FEATURE_EXPORTABLE_BIT),
           !!(feat & VK_EXTERNAL_MEMORY_FEATURE_IMPORTABLE_BIT));
    if (!(feat & VK_EXTERNAL_MEMORY_FEATURE_EXPORTABLE_BIT)) {
        printf("RESULT: NOT FEASIBLE (no export support)\n");
        return 2;
    }

    // ---- logical device with the win32 external-memory extensions
    float prio = 1.0f;
    uint32_t qfam = 0; // any queue family works; we never submit
    VkDeviceQueueCreateInfo qci = { VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO };
    qci.queueFamilyIndex = qfam;
    qci.queueCount = 1;
    qci.pQueuePriorities = &prio;
    const char * dev_exts[] = {
        VK_KHR_EXTERNAL_MEMORY_EXTENSION_NAME,
        VK_KHR_EXTERNAL_MEMORY_WIN32_EXTENSION_NAME,
        VK_KHR_DEDICATED_ALLOCATION_EXTENSION_NAME,
        VK_KHR_GET_MEMORY_REQUIREMENTS_2_EXTENSION_NAME,
    };
    VkDeviceCreateInfo dci = { VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO };
    dci.queueCreateInfoCount = 1;
    dci.pQueueCreateInfos = &qci;
    dci.enabledExtensionCount = 4;
    dci.ppEnabledExtensionNames = dev_exts;
    VkDevice dev;
    VK_CHECK(vkCreateDevice(pd, &dci, nullptr, &dev));

    // ---- exportable buffer + dedicated allocation
    VkExternalMemoryBufferCreateInfo embci = { VK_STRUCTURE_TYPE_EXTERNAL_MEMORY_BUFFER_CREATE_INFO };
    embci.handleTypes = VK_EXTERNAL_MEMORY_HANDLE_TYPE_OPAQUE_WIN32_BIT;
    VkBufferCreateInfo bci = { VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO };
    bci.pNext = &embci;
    bci.size = BUF_SIZE;
    bci.usage = ebi.usage;
    bci.sharingMode = VK_SHARING_MODE_EXCLUSIVE;
    VkBuffer buf;
    VK_CHECK(vkCreateBuffer(dev, &bci, nullptr, &buf));

    VkMemoryRequirements mreq;
    vkGetBufferMemoryRequirements(dev, buf, &mreq);

    VkPhysicalDeviceMemoryProperties mprops;
    vkGetPhysicalDeviceMemoryProperties(pd, &mprops);
    // prefer DEVICE_LOCAL | HOST_VISIBLE (ReBAR) so the CPU can verify without a copy
    uint32_t mem_type = UINT32_MAX;
    const VkMemoryPropertyFlags want = VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT | VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT;
    for (uint32_t i = 0; i < mprops.memoryTypeCount; ++i) {
        if ((mreq.memoryTypeBits & (1u << i)) && (mprops.memoryTypes[i].propertyFlags & want) == want) { mem_type = i; break; }
    }
    bool host_visible = mem_type != UINT32_MAX;
    if (!host_visible) {
        for (uint32_t i = 0; i < mprops.memoryTypeCount; ++i) {
            if ((mreq.memoryTypeBits & (1u << i)) && (mprops.memoryTypes[i].propertyFlags & VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT)) { mem_type = i; break; }
        }
        printf("note: no ReBAR host-visible+device-local type for this buffer; CPU verify skipped\n");
    }

    VkMemoryDedicatedAllocateInfo dedic = { VK_STRUCTURE_TYPE_MEMORY_DEDICATED_ALLOCATE_INFO };
    dedic.buffer = buf;
    VkExportMemoryAllocateInfo expi = { VK_STRUCTURE_TYPE_EXPORT_MEMORY_ALLOCATE_INFO };
    expi.pNext = &dedic;
    expi.handleTypes = VK_EXTERNAL_MEMORY_HANDLE_TYPE_OPAQUE_WIN32_BIT;
    VkMemoryAllocateInfo mai = { VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO };
    mai.pNext = &expi;
    mai.allocationSize = mreq.size;
    mai.memoryTypeIndex = mem_type;
    VkDeviceMemory mem;
    VK_CHECK(vkAllocateMemory(dev, &mai, nullptr, &mem));
    VK_CHECK(vkBindBufferMemory(dev, buf, mem, 0));

    // ---- export the win32 handle
    auto pvkGetMemoryWin32HandleKHR = (PFN_vkGetMemoryWin32HandleKHR) vkGetDeviceProcAddr(dev, "vkGetMemoryWin32HandleKHR");
    if (!pvkGetMemoryWin32HandleKHR) { printf("vkGetMemoryWin32HandleKHR missing\n"); return 1; }
    VkMemoryGetWin32HandleInfoKHR ghi = { VK_STRUCTURE_TYPE_MEMORY_GET_WIN32_HANDLE_INFO_KHR };
    ghi.memory = mem;
    ghi.handleType = VK_EXTERNAL_MEMORY_HANDLE_TYPE_OPAQUE_WIN32_BIT;
    HANDLE h = nullptr;
    VK_CHECK(pvkGetMemoryWin32HandleKHR(dev, &ghi, &h));
    printf("exported handle: %p (alloc %llu bytes)\n", h, (unsigned long long) mreq.size);

    // ---- import into HIP
    hipExternalMemoryHandleDesc hdesc = {};
    hdesc.type = hipExternalMemoryHandleTypeOpaqueWin32;
    hdesc.handle.win32.handle = h;
    hdesc.size = mreq.size;
    hipExternalMemory_t ext_mem = nullptr;
    HIP_CHECK(hipImportExternalMemory(&ext_mem, &hdesc));

    hipExternalMemoryBufferDesc bdesc = {};
    bdesc.offset = 0;
    bdesc.size = BUF_SIZE;
    void * dptr = nullptr;
    HIP_CHECK(hipExternalMemoryGetMappedBuffer(&dptr, ext_mem, &bdesc));
    printf("hip mapped ptr: %p\n", dptr);
    CloseHandle(h);

    // ---- kernel writes through the imported mapping
    const uint32_t n = (uint32_t) (BUF_SIZE / 4);
    hipLaunchKernelGGL(write_pattern, dim3((n + 255) / 256), dim3(256), 0, 0, (uint32_t *) dptr, n, 0u);
    HIP_CHECK(hipDeviceSynchronize());

    // ---- bidirectional cross-API verification through queue ops
    // staging buffer (host-visible) for Vulkan-side readback
    VkBufferCreateInfo sci = { VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO };
    sci.size = BUF_SIZE;
    sci.usage = VK_BUFFER_USAGE_TRANSFER_DST_BIT;
    sci.sharingMode = VK_SHARING_MODE_EXCLUSIVE;
    VkBuffer staging;
    VK_CHECK(vkCreateBuffer(dev, &sci, nullptr, &staging));
    VkMemoryRequirements sreq;
    vkGetBufferMemoryRequirements(dev, staging, &sreq);
    uint32_t s_type = UINT32_MAX;
    for (uint32_t i = 0; i < mprops.memoryTypeCount; ++i) {
        const VkMemoryPropertyFlags f = mprops.memoryTypes[i].propertyFlags;
        if ((sreq.memoryTypeBits & (1u << i)) && (f & VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT) && (f & VK_MEMORY_PROPERTY_HOST_COHERENT_BIT)) { s_type = i; break; }
    }
    VkMemoryAllocateInfo smai = { VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO };
    smai.allocationSize = sreq.size;
    smai.memoryTypeIndex = s_type;
    VkDeviceMemory smem;
    VK_CHECK(vkAllocateMemory(dev, &smai, nullptr, &smem));
    VK_CHECK(vkBindBufferMemory(dev, staging, smem, 0));

    VkQueue queue;
    vkGetDeviceQueue(dev, qfam, 0, &queue);
    VkCommandPoolCreateInfo cpci = { VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO };
    cpci.flags = VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT;
    cpci.queueFamilyIndex = qfam;
    VkCommandPool cpool;
    VK_CHECK(vkCreateCommandPool(dev, &cpci, nullptr, &cpool));
    VkCommandBufferAllocateInfo cbai = { VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO };
    cbai.commandPool = cpool;
    cbai.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY;
    cbai.commandBufferCount = 1;
    VkCommandBuffer cb;
    VK_CHECK(vkAllocateCommandBuffers(dev, &cbai, &cb));
    VkFenceCreateInfo fci = { VK_STRUCTURE_TYPE_FENCE_CREATE_INFO };
    VkFence fence;
    VK_CHECK(vkCreateFence(dev, &fci, nullptr, &fence));

    auto submit_and_wait = [&]() -> VkResult {
        VkSubmitInfo si = { VK_STRUCTURE_TYPE_SUBMIT_INFO };
        si.commandBufferCount = 1;
        si.pCommandBuffers = &cb;
        VkResult r = vkQueueSubmit(queue, 1, &si, fence);
        if (r != VK_SUCCESS) return r;
        r = vkWaitForFences(dev, 1, &fence, VK_TRUE, UINT64_MAX);
        vkResetFences(dev, 1, &fence);
        return r;
    };
    VkCommandBufferBeginInfo cbbi = { VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO };

    // direction 1: HIP wrote pattern (above) -> Vulkan copies shared->staging -> CPU verifies
    VK_CHECK(vkBeginCommandBuffer(cb, &cbbi));
    VkBufferCopy region = { 0, 0, BUF_SIZE };
    vkCmdCopyBuffer(cb, buf, staging, 1, &region);
    VK_CHECK(vkEndCommandBuffer(cb));
    VK_CHECK(submit_and_wait());
    {
        void * smap = nullptr;
        VK_CHECK(vkMapMemory(dev, smem, 0, BUF_SIZE, 0, &smap));
        const uint32_t * u = (const uint32_t *) smap;
        uint64_t bad = 0;
        for (uint32_t i = 0; i < n; ++i) {
            if (u[i] != i * 3u + 7u) bad++;
        }
        vkUnmapMemory(dev, smem);
        printf("HIP-write -> VK-read verify: %s (%llu bad of %u)\n", bad == 0 ? "PASS" : "FAIL", (unsigned long long) bad, n);
        if (bad != 0) return 1;
    }

    // direction 2: Vulkan fills shared buffer -> HIP reads it back
    VK_CHECK(vkBeginCommandBuffer(cb, &cbbi));
    vkCmdFillBuffer(cb, buf, 0, BUF_SIZE, 0xA5A51234u);
    VK_CHECK(vkEndCommandBuffer(cb));
    VK_CHECK(submit_and_wait());
    {
        std::vector<uint32_t> hbuf(n);
        HIP_CHECK(hipMemcpy(hbuf.data(), dptr, BUF_SIZE, hipMemcpyDeviceToHost));
        uint64_t bad = 0;
        for (uint32_t i = 0; i < n; ++i) {
            if (hbuf[i] != 0xA5A51234u) bad++;
        }
        printf("VK-write -> HIP-read verify: %s (%llu bad of %u)\n", bad == 0 ? "PASS" : "FAIL", (unsigned long long) bad, n);
        if (bad != 0) return 1;
    }

    // ---- latency: HIP kernel launch + stream sync on the shared buffer vs native
    hipStream_t stream;
    HIP_CHECK(hipStreamCreate(&stream));
    auto bench = [&](uint32_t * p, const char * label) {
        const int iters = 10000;
        // warmup
        for (int i = 0; i < 100; ++i) {
            hipLaunchKernelGGL(write_pattern, dim3((n + 255) / 256), dim3(256), 0, stream, p, n, (uint32_t) i);
        }
        hipStreamSynchronize(stream);
        auto t0 = std::chrono::high_resolution_clock::now();
        for (int i = 0; i < iters; ++i) {
            hipLaunchKernelGGL(write_pattern, dim3((n + 255) / 256), dim3(256), 0, stream, p, n, (uint32_t) i);
            hipStreamSynchronize(stream);
        }
        auto t1 = std::chrono::high_resolution_clock::now();
        double us = std::chrono::duration<double, std::micro>(t1 - t0).count() / iters;
        printf("%s: %.2f us per launch+sync\n", label, us);
        // batched: 8 launches per sync (a chained draft loop shape)
        t0 = std::chrono::high_resolution_clock::now();
        for (int i = 0; i < iters / 8; ++i) {
            for (int j = 0; j < 8; ++j) {
                hipLaunchKernelGGL(write_pattern, dim3((n + 255) / 256), dim3(256), 0, stream, p, n, (uint32_t) j);
            }
            hipStreamSynchronize(stream);
        }
        t1 = std::chrono::high_resolution_clock::now();
        us = std::chrono::duration<double, std::micro>(t1 - t0).count() / (iters / 8);
        printf("%s: %.2f us per 8-launch chain+sync (%.2f us/launch)\n", label, us, us / 8.0);
    };
    bench((uint32_t *) dptr, "imported (vk-shared)");

    uint32_t * native = nullptr;
    HIP_CHECK(hipMalloc(&native, BUF_SIZE));
    bench(native, "native  (hipMalloc)");

    printf("RESULT: FEASIBLE\n");
    return 0;
}
