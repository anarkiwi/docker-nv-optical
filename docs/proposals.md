# Proposed extras (not implemented)

Optional additions to the `optical` target. Versions and sizes are from PyPI / NVIDIA
apt metadata as of 2026-11-16. "Unverified" marks facts not confirmed from a primary source.

GpuMat interop baseline: OpenCV 4.14.0 `cv2.cuda.GpuMat` does not implement
`__cuda_array_interface__` or DLPack. Zero-copy exchange uses `GpuMat.cudaPtr()`
(export) and `cv2.cuda.createGpuMatFromCudaMemory(rows, cols, type, ptr, step)` (import);
`cv2.cuda.Stream.cudaPtr()` exposes the stream handle for ordering work across libraries.

## CuPy

- Adds: NumPy/SciPy-compatible GPU arrays and custom `RawKernel`/`ElementwiseKernel` for
  flow post-processing (warping, consistency checks, statistics) without host round-trips.
- Install: `pip install cupy-cuda13x` (14.2.0, cp312 manylinux2014 x86_64). Uses the image's
  CUDA 13.0 toolkit; the `[ctk]` extra pulls CUDA wheels instead and is not needed.
- Size: 69.4 MB wheel; installed size unverified.
- Licence: MIT. Redistributable.
- sm_120 / CUDA 13: CUDA 13 wheel published; kernels compiled at runtime by NVRTC for the
  device arch, so sm_120 is covered by the toolkit's NVRTC.
- Interop: `__cuda_array_interface__` and DLPack (`cupy.from_dlpack`, `__dlpack__`).
  GpuMat -> CuPy via `cupy.cuda.UnownedMemory(gm.cudaPtr(), ...)` + `cupy.ndarray(..., strides=(gm.step, ...))`;
  CuPy -> GpuMat via `createGpuMatFromCudaMemory(..., arr.data.ptr, arr.strides[0])`.

## PyTorch + RAFT

- Adds: learned dense flow (`torchvision.models.optical_flow.raft_large` / `raft_small`) as a
  higher-accuracy alternative or reference for NVOF 2.0; input `(N,3,H,W)` float in [-1, 1],
  H and W divisible by 8.
- Install: `pip install torch torchvision` (torch 2.15.0, torchvision 0.29.2). The PyPI
  torch wheel already depends on CUDA 13 wheels (`cuda-toolkit[...]==13.2.2`,
  `nvidia-cudnn-cu13==9.26.0.51`, `nvidia-nccl-cu13`, `nvidia-cusparselt-cu13`,
  `nvidia-nvshmem-cu13`); `--index-url https://download.pytorch.org/whl/cu130` is the
  explicit alternative. Weights fetched to `$TORCH_HOME` at first use; pre-fetch at build time
  for offline use.
- Size: torch wheel 539.2 MB; cuDNN + cuSPARSELt + NCCL + NVSHMEM wheels 1.04 GB; plus
  cuBLAS/cuFFT/cuSOLVER/cuSPARSE/NVRTC/CUPTI/cuFile wheels. Installed total multi-GB
  (exact figure unverified). Weights: `raft_large_C_T_SKHT_V2` 21.1 MB, `raft_small_C_T_V2` 4.0 MB.
- Licence: torch PyPI metadata `Apache-2.0 AND ... BSD-3-Clause ...` (composite); torchvision
  BSD-3-Clause. The `nvidia-*` dependency wheels are under NVIDIA proprietary licences
  (CUDA EULA / cuDNN SLA) that permit redistribution of the runtime libraries with an
  application; whether a general-purpose public image qualifies is unverified.
- RAFT weights: torchvision's weight metadata carries no licence field. Ported V1 weights come
  from princeton-vl/RAFT (code BSD-3-Clause); V2 were retrained by torchvision. Training data
  includes Sintel and KITTI (KITTI is CC BY-NC-SA 3.0); licence status of the weights
  themselves unverified. Safer to download at runtime than to bake into a public image.
- sm_120 / CUDA 13: PyTorch states all CUDA 12.8+ builds support Blackwell; the exact
  `torch.cuda.get_arch_list()` of 2.15.0 is unverified. Bundled CUDA runtime 13.2 needs a
  driver >= the 13.2 minimum (driver 620 satisfies CUDA 13.x; unverified for 13.2 specifically).
- Interop: `torch.from_dlpack` / `__dlpack__`, `torch.as_tensor` on any
  `__cuda_array_interface__` object (e.g. CuPy). GpuMat via CuPy wrapper or
  `createGpuMatFromCudaMemory(..., t.data_ptr(), t.stride(0) * t.element_size())`.

## NVIDIA VPI

- Adds: CUDA-backend CV primitives (pyramidal LK, remap, pyramids, stereo, filters) with a
  stream/backend model. Dense optical flow is `VPI_BACKEND_OFA` only, documented for Jetson
  Orin/Thor; availability on x86_64 dGPU unverified (likely absent).
- Install: apt, repo `deb https://repo.download.nvidia.com/jetson/x86_64/noble r39.2 main`
  (key `jetson-ota-public.asc`); packages `libnvvpi4` (4.1.4), `python3.12-vpi4`, `vpi4-dev`.
  Installs to `/opt/nvidia/vpi4`; the Python module targets system Python 3.12, so `/opt/venv`
  would need `--system-site-packages` or a `.pth` entry (unverified path). PyPI `vpi` is an
  unrelated GPL Raspberry Pi package.
- Size: `libnvvpi4` 318 MB download, ~1.9 GB installed (Installed-Size 1909068 KiB);
  `python3.12-vpi4` ~4 MB.
- Licence: proprietary NVIDIA SDK EULA. The VPI supplement marks "any portion of the SDK"
  distributable, but only "as incorporated in object code format into a software application"
  with "material additional functionality" and accessed only by that application. A
  general-purpose public image is not clearly covered; treat as not redistributable without
  NVIDIA confirmation.
- sm_120 / CUDA 13: x86_64 dGPU builds exist for Ubuntu 24.04 (4.0.5 notes: CUDA 13, Volta+,
  tested on 24.04). 4.1.3 notes "compatibility with CUDA 13.2". Blackwell / sm_120 not
  mentioned (unverified).
- Interop: `vpi.asimage` / `vpi.asarray` wrap `__cuda_array_interface__` objects (CuPy,
  torch); GpuMat via CuPy wrapper. PyTorch interop requires a CUDA 13.2-compatible torch
  (4.1.3 known issue).

## PyNvVideoCodec

- Adds: Python NVDEC/NVENC decode/encode/transcode with frames delivered in device memory,
  feeding flow without host copies; complements `cv2.cudacodec`.
- Install: `pip install pynvvideocodec` (2.2.4, cp312 manylinux_2_28 x86_64); one wheel with
  CUDA 12.1 and 13.0 extension modules.
- Size: 26.9 MB wheel, 43.2 MB unpacked.
- Licence: MIT; wheel bundles FFmpeg `libavformat.so.63` / `libavutil.so.61` under LGPL-3.0
  (NOTICES.txt) and a cudart 12.3. Redistributable; duplicates FFmpeg libs already in the image.
- sm_120 / CUDA 13: Blackwell listed in system requirements; Linux driver >= 530.41.03.
  Codec support follows NVDEC/NVENC hardware, not sm arch.
- Interop: decoded frames expose `__dlpack__` and `__cuda_array_interface__` (CuPy, torch,
  VPI direct; GpuMat via `createGpuMatFromCudaMemory`).

## Comparison

| Package | Install | Size (approx.) | Licence | Public-image redistribution | CUDA 13 / sm_120 | Interop |
|---|---|---|---|---|---|---|
| CuPy 14.2.0 | `pip cupy-cuda13x` | 69 MB wheel | MIT | Yes | Yes (NVRTC) | CAI, DLPack |
| torch 2.15.0 + torchvision 0.29.2 | `pip torch torchvision` | multi-GB | Apache/BSD + NVIDIA EULA libs | Likely (NVIDIA runtime terms); weights unverified | CUDA 13.2 wheels; Blackwell yes | CAI, DLPack |
| VPI 4.1.4 | apt Jetson x86_64 noble r39.2 | ~1.9 GB | NVIDIA proprietary EULA | Not clearly permitted | CUDA 13.x; sm_120 unverified | CAI |
| PyNvVideoCodec 2.2.4 | `pip pynvvideocodec` | 43 MB | MIT + LGPL FFmpeg | Yes | Yes (Blackwell listed) | CAI, DLPack |

Recommendation: add CuPy and PyNvVideoCodec as a `optical-extras` target `FROM optical`,
PyTorch + RAFT as a further `optical-torch` target `FROM optical-extras` (weights fetched at
runtime), and leave VPI out of published images (local build only) so `optical` stays slim
and redistributable.
