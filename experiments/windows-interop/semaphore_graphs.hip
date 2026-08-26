// SPDX-License-Identifier: MIT

// Campaign 3 gates 2+3: cross-API external semaphores (Vulkan <-> HIP) and
// explicit HIP graph construction/launch on Windows (stream capture unsupported).
#define NOMINMAX
#include <windows.h>
#define VK_USE_PLATFORM_WIN32_KHR
#include <vulkan/vulkan.h>
#include <hip/hip_runtime.h>
#include <cstdio>
#include <cstring>
#include <chrono>
#include <vector>

#define VK_CHECK(x) do { VkResult r_ = (x); if (r_ != VK_SUCCESS) { printf("VK fail %d at line %d\n", (int) r_, __LINE__); return 1; } } while (0)
#define HIP_CHECK(x) do { hipError_t e_ = (x); if (e_ != hipSuccess) { printf("HIP fail %s at line %d\n", hipGetErrorString(e_), __LINE__); return 1; } } while (0)

__global__ void bump(uint32_t * p) {
    if (threadIdx.x == 0 && blockIdx.x == 0) p[0] += 1;
}

int main() {
    // ---- Vulkan setup (device 0; identity established by spike 1)
    VkApplicationInfo app = { VK_STRUCTURE_TYPE_APPLICATION_INFO };
    app.pApplicationName = "hip-interop-spike2";
    app.apiVersion = VK_API_VERSION_1_2;
    VkInstanceCreateInfo ici = { VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO };
    ici.pApplicationInfo = &app;
    VkInstance inst;
    VK_CHECK(vkCreateInstance(&ici, nullptr, &inst));

    uint32_t n_pd = 0;
    vkEnumeratePhysicalDevices(inst, &n_pd, nullptr);
    std::vector<VkPhysicalDevice> pds(n_pd);
    vkEnumeratePhysicalDevices(inst, &n_pd, pds.data());
    VkPhysicalDevice pd = pds[0];

    // capability: can we export a TIMELINE semaphore as OPAQUE_WIN32?
    VkSemaphoreTypeCreateInfo type_probe = { VK_STRUCTURE_TYPE_SEMAPHORE_TYPE_CREATE_INFO };
    type_probe.semaphoreType = VK_SEMAPHORE_TYPE_TIMELINE;
    VkPhysicalDeviceExternalSemaphoreInfo esi = { VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_EXTERNAL_SEMAPHORE_INFO };
    esi.pNext = &type_probe;
    esi.handleType = VK_EXTERNAL_SEMAPHORE_HANDLE_TYPE_OPAQUE_WIN32_BIT;
    VkExternalSemaphoreProperties esp = { VK_STRUCTURE_TYPE_EXTERNAL_SEMAPHORE_PROPERTIES };
    vkGetPhysicalDeviceExternalSemaphoreProperties(pd, &esi, &esp);
    printf("OPAQUE_WIN32 semaphore: exportable=%d importable=%d\n",
           !!(esp.externalSemaphoreFeatures & VK_EXTERNAL_SEMAPHORE_FEATURE_EXPORTABLE_BIT),
           !!(esp.externalSemaphoreFeatures & VK_EXTERNAL_SEMAPHORE_FEATURE_IMPORTABLE_BIT));
    const bool sem_ok = (esp.externalSemaphoreFeatures & VK_EXTERNAL_SEMAPHORE_FEATURE_EXPORTABLE_BIT) != 0;

    float prio = 1.0f;
    uint32_t qfam = 0;
    VkDeviceQueueCreateInfo qci = { VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO };
    qci.queueFamilyIndex = qfam;
    qci.queueCount = 1;
    qci.pQueuePriorities = &prio;
    const char * dev_exts[] = {
        VK_KHR_EXTERNAL_SEMAPHORE_EXTENSION_NAME,
        VK_KHR_EXTERNAL_SEMAPHORE_WIN32_EXTENSION_NAME,
    };
    VkPhysicalDeviceTimelineSemaphoreFeatures tsf = { VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_TIMELINE_SEMAPHORE_FEATURES };
    tsf.timelineSemaphore = VK_TRUE;
    VkDeviceCreateInfo dci = { VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO };
    dci.pNext = &tsf;
    dci.queueCreateInfoCount = 1;
    dci.pQueueCreateInfos = &qci;
    dci.enabledExtensionCount = 2;
    dci.ppEnabledExtensionNames = dev_exts;
    VkDevice dev;
    VK_CHECK(vkCreateDevice(pd, &dci, nullptr, &dev));
    VkQueue queue;
    vkGetDeviceQueue(dev, qfam, 0, &queue);

    // =========================== GATE 2: semaphores ===========================
    if (sem_ok) {
        auto make_sem = [&](VkSemaphore & s) -> VkResult {
            static VkSemaphoreTypeCreateInfo tci = { VK_STRUCTURE_TYPE_SEMAPHORE_TYPE_CREATE_INFO };
            tci.semaphoreType = VK_SEMAPHORE_TYPE_TIMELINE;
            tci.initialValue = 0;
            static VkExportSemaphoreCreateInfo esci = { VK_STRUCTURE_TYPE_EXPORT_SEMAPHORE_CREATE_INFO };
            esci.pNext = &tci;
            esci.handleTypes = VK_EXTERNAL_SEMAPHORE_HANDLE_TYPE_OPAQUE_WIN32_BIT;
            VkSemaphoreCreateInfo sci = { VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO };
            sci.pNext = &esci;
            return vkCreateSemaphore(dev, &sci, nullptr, &s);
        };
        VkSemaphore semA, semB; // A: HIP -> VK, B: VK -> HIP
        VK_CHECK(make_sem(semA));
        VK_CHECK(make_sem(semB));

        auto pvkGetSemaphoreWin32HandleKHR = (PFN_vkGetSemaphoreWin32HandleKHR) vkGetDeviceProcAddr(dev, "vkGetSemaphoreWin32HandleKHR");
        if (!pvkGetSemaphoreWin32HandleKHR) { printf("vkGetSemaphoreWin32HandleKHR missing\n"); return 1; }
        auto export_sem = [&](VkSemaphore s, HANDLE & h) -> VkResult {
            VkSemaphoreGetWin32HandleInfoKHR gi = { VK_STRUCTURE_TYPE_SEMAPHORE_GET_WIN32_HANDLE_INFO_KHR };
            gi.semaphore = s;
            gi.handleType = VK_EXTERNAL_SEMAPHORE_HANDLE_TYPE_OPAQUE_WIN32_BIT;
            return pvkGetSemaphoreWin32HandleKHR(dev, &gi, &h);
        };
        HANDLE hA = nullptr, hB = nullptr;
        VK_CHECK(export_sem(semA, hA));
        VK_CHECK(export_sem(semB, hB));

        hipExternalSemaphore_t extA = nullptr, extB = nullptr;
        hipExternalSemaphoreHandleDesc sd = {};
        sd.type = hipExternalSemaphoreHandleTypeTimelineSemaphoreWin32;
        sd.handle.win32.handle = hA;
        hipError_t e1 = hipImportExternalSemaphore(&extA, &sd);
        sd.handle.win32.handle = hB;
        hipError_t e2 = extA ? hipImportExternalSemaphore(&extB, &sd) : hipErrorUnknown;
        if (e1 != hipSuccess || e2 != hipSuccess) {
            printf("GATE 2: hipImportExternalSemaphore FAILED (%s / %s)\n", hipGetErrorString(e1), hipGetErrorString(e2));
        } else {
            printf("GATE 2: semaphores imported into HIP OK\n");
            CloseHandle(hA);
            CloseHandle(hB);

            hipStream_t stream;
            HIP_CHECK(hipStreamCreate(&stream));

            // timeline ping-pong with monotonic values: HIP signals A=v on its stream;
            // VK submit waits A>=v, signals B=v; HIP stream waits B>=v.
            // One iteration = one full cross-API round trip.
            const VkPipelineStageFlags wait_stage = VK_PIPELINE_STAGE_ALL_COMMANDS_BIT;
            uint64_t v = 0;

            const int iters = 2000;
            auto round = [&]() -> int {
                v++;
                hipExternalSemaphoreSignalParams sigp = {};
                sigp.params.fence.value = v;
                hipExternalSemaphoreWaitParams waitp = {};
                waitp.params.fence.value = v;
                HIP_CHECK(hipSignalExternalSemaphoresAsync(&extA, &sigp, 1, stream));
                VkTimelineSemaphoreSubmitInfo tssi = { VK_STRUCTURE_TYPE_TIMELINE_SEMAPHORE_SUBMIT_INFO };
                tssi.waitSemaphoreValueCount = 1;
                tssi.pWaitSemaphoreValues = &v;
                tssi.signalSemaphoreValueCount = 1;
                tssi.pSignalSemaphoreValues = &v;
                VkSubmitInfo si = { VK_STRUCTURE_TYPE_SUBMIT_INFO };
                si.pNext = &tssi;
                si.waitSemaphoreCount = 1;
                si.pWaitSemaphores = &semA;
                si.pWaitDstStageMask = &wait_stage;
                si.signalSemaphoreCount = 1;
                si.pSignalSemaphores = &semB;
                VK_CHECK(vkQueueSubmit(queue, 1, &si, VK_NULL_HANDLE));
                HIP_CHECK(hipWaitExternalSemaphoresAsync(&extB, &waitp, 1, stream));
                HIP_CHECK(hipStreamSynchronize(stream));
                return 0;
            };
            // warmup one round to fault everything in
            if (round() != 0) return 1;

            auto t0 = std::chrono::high_resolution_clock::now();
            for (int i = 0; i < iters; ++i) {
                if (round() != 0) return 1;
            }
            auto t1 = std::chrono::high_resolution_clock::now();
            VK_CHECK(vkQueueWaitIdle(queue));
            double us = std::chrono::duration<double, std::micro>(t1 - t0).count() / iters;
            printf("GATE 2: cross-API timeline round trip: %.2f us (HIP signal -> VK wait/signal -> HIP wait)\n", us);
        }
    } else {
        printf("GATE 2: binary OPAQUE_WIN32 semaphores not exportable on this driver\n");
    }

    // =========================== GATE 3: explicit HIP graphs ===========================
    {
        uint32_t * buf = nullptr;
        HIP_CHECK(hipMalloc(&buf, 4096));
        HIP_CHECK(hipMemset(buf, 0, 4096));
        hipStream_t stream;
        HIP_CHECK(hipStreamCreate(&stream));

        auto build_and_time = [&](int n_nodes, const char * label) -> int {
            hipGraph_t graph;
            HIP_CHECK(hipGraphCreate(&graph, 0));
            std::vector<hipGraphNode_t> nodes(n_nodes);
            void * kargs[] = { (void *) &buf };
            hipKernelNodeParams kp = {};
            kp.func = (void *) bump;
            kp.gridDim = dim3(1);
            kp.blockDim = dim3(64);
            kp.sharedMemBytes = 0;
            kp.kernelParams = kargs;
            for (int i = 0; i < n_nodes; ++i) {
                // serial chain: each node depends on the previous (drafter shape)
                HIP_CHECK(hipGraphAddKernelNode(&nodes[i], graph, i ? &nodes[i-1] : nullptr, i ? 1 : 0, &kp));
            }
            hipGraphExec_t exec;
            hipError_t einst = hipGraphInstantiate(&exec, graph, nullptr, nullptr, 0);
            if (einst != hipSuccess) {
                printf("GATE 3: hipGraphInstantiate(%s) FAILED: %s\n", label, hipGetErrorString(einst));
                return 1;
            }
            // warmup
            for (int i = 0; i < 50; ++i) {
                HIP_CHECK(hipGraphLaunch(exec, stream));
            }
            HIP_CHECK(hipStreamSynchronize(stream));

            const int iters = 5000;
            auto t0 = std::chrono::high_resolution_clock::now();
            for (int i = 0; i < iters; ++i) {
                hipGraphLaunch(exec, stream);
                hipStreamSynchronize(stream);
            }
            auto t1 = std::chrono::high_resolution_clock::now();
            double us = std::chrono::duration<double, std::micro>(t1 - t0).count() / iters;
            printf("GATE 3: %s: %.2f us per graph launch+sync (%.2f us/node)\n", label, us, us / n_nodes);

            hipGraphExecDestroy(exec);
            hipGraphDestroy(graph);
            return 0;
        };
        if (build_and_time(8,  "graph  8 serial nodes") != 0) return 1;
        if (build_and_time(50, "graph 50 serial nodes") != 0) return 1;

        // verify the counter actually advanced (graphs really ran)
        uint32_t count = 0;
        HIP_CHECK(hipMemcpy(&count, buf, 4, hipMemcpyDeviceToHost));
        printf("GATE 3: counter=%u (expected %u) %s\n", count,
               (unsigned) (50*8 + 5000*8 + 50*50 + 5000*50),
               count == (unsigned) (50*8 + 5000*8 + 50*50 + 5000*50) ? "PASS" : "FAIL");
    }

    printf("DONE\n");
    return 0;
}
