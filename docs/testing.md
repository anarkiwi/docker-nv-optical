# Testing

Tests run inside the image with `tests/` bind-mounted read-only.

| Script | GPU | Checks |
| --- | --- | --- |
| `tests/smoke_ffmpeg.sh` | no | encoder, decoder, filter and hwaccel lists; GPL without nonfree; x264, x265, SVT-AV1 and VP9 encodes; dav1d decode; libvmaf score |
| `tests/smoke_optical.py` | no | `cv2.getBuildInformation()` reports CUDA with NVCUVID/NVCUVENC, the CUDA modules and FFmpeg; Python bindings for `NvidiaOpticalFlow_2_0` and `cudacodec`; videoio round trip |
| `tests/gpu.sh` | yes | NVENC (H.264, HEVC, AV1), NVDEC (hwaccel and cuvid), `scale_cuda`, `libvmaf` and `libvmaf_cuda`, `scale_vulkan`, then `tests/gpu_optical.py` |
| `tests/gpu_optical.py` | yes | `NvidiaOpticalFlow_2_0` recovers a known translation between two frames; `cudacodec` decodes to GPU memory |

All test media is generated with FFmpeg's `testsrc2` or numpy.

```sh
docker run --rm -v "$PWD/tests:/tests:ro" nv-optical:ffmpeg /tests/smoke_ffmpeg.sh
docker run --rm -v "$PWD/tests:/tests:ro" nv-optical:optical-smoke python /tests/smoke_optical.py
docker run --rm --gpus all -v "$PWD/tests:/tests:ro" nv-optical:optical /tests/gpu.sh
```

Without a GPU, `cv2` can only be imported in `optical-smoke`, whose `LD_LIBRARY_PATH` points at
link stubs for the driver libraries. Bind mounts must come from a path the Docker daemon accepts.

## CI

`.github/workflows/ci.yml` runs hadolint, shellcheck, black and pylint, then builds `ffmpeg` and
`optical-smoke` with Buildx and the GitHub Actions cache and runs the smoke tests. CI sets
`CUDA_ARCH_BIN=12.0` and an empty `CUDA_ARCH_PTX`, which keeps the OpenCV build within a hosted
runner's time limit; the smoke tests do not execute GPU code, so they cover the same build.

`.github/workflows/release.yml` pushes `anarkiwi/nv-optical:<version>-ffmpeg` and
`-optical` on `v*` tags through the `release` environment, whose secrets `DOCKERHUB_USERNAME` and
`DOCKERHUB_TOKEN` it uses; restrict that environment to `v*` tags and require a reviewer. It builds the
full arch list. Set the `RELEASE_RUNNER` repository variable to a larger or self-hosted runner label
if the full build exceeds a hosted runner's limit.
