# nv-optical

CUDA container images for GPU video work on NVIDIA GPUs (Turing through Blackwell, including sm_120).

| Target | Tag | Contents |
| --- | --- | --- |
| `ffmpeg` | `anarkiwi/nv-optical:<version>-ffmpeg` | FFmpeg with NVENC/NVDEC, CUDA filters (`--enable-cuda-llvm`), Vulkan, libx264, libx265, SVT-AV1, libvpx, dav1d, libvmaf (CPU and CUDA). GPL, no nonfree components. |
| `optical` | `anarkiwi/nv-optical:<version>-optical` | The same FFmpeg, plus Python, numpy and OpenCV with CUDA and contrib: `cv2.cuda.NvidiaOpticalFlow_2_0`, `cv2.cudacodec`, videoio on FFmpeg. |

## Run

Requires an NVIDIA driver supporting CUDA 13.0 and the NVIDIA Container Toolkit.

```sh
docker run --rm --gpus all anarkiwi/nv-optical:<version>-ffmpeg \
    ffmpeg -hwaccel cuda -hwaccel_output_format cuda -i in.mp4 -vf scale_cuda=1280:720 -c:v hevc_nvenc out.mp4

docker run --rm --device nvidia.com/gpu=all anarkiwi/nv-optical:<version>-optical \
    python -c 'import cv2; print(cv2.cuda.getCudaEnabledDeviceCount())'
```

## Build

```sh
docker buildx build --target ffmpeg -t nv-optical:ffmpeg .
docker buildx build --target optical -t nv-optical:optical .
```

## Documentation

- [docs/build.md](docs/build.md): stages, pinned versions, build arguments, licensing.
- [docs/testing.md](docs/testing.md): smoke and GPU tests, CI.
- [docs/proposals.md](docs/proposals.md): proposed extras (CuPy, PyTorch + RAFT, VPI, PyNvVideoCodec).
