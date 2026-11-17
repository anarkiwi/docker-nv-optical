# syntax=docker/dockerfile:1

ARG CUDA_ARCH_BIN="7.5 8.6 8.9 9.0 12.0"
ARG CUDA_ARCH_PTX="12.0"
ARG NV_CODEC_HEADERS_VERSION=13.0.19.1
ARG VULKAN_SDK_VERSION=1.4.357.0
ARG X264_COMMIT=b35605ace3ddf7c1a5d67a2eb553f034aef41d55
ARG X265_VERSION=4.2
ARG SVTAV1_VERSION=4.2.0
ARG LIBVPX_VERSION=1.17.0
ARG DAV1D_VERSION=1.5.4
ARG VMAF_VERSION=3.2.1
ARG FFMPEG_VERSION=8.1.3
ARG NUMPY_VERSION=2.5.4
ARG OPENCV_VERSION=4.14.0
ARG TORCHCODEC_COMMIT=d9dc54238e173000bc3969eb3959777026ff9ae8
ARG RUNTIME_PACKAGES="libegl1 libnuma1 libvulkan1 libx11-6 libxext6"
ARG NVIDIA_DRIVER_CAPABILITIES=compute,utility,video,graphics

FROM nvidia/cuda:13.5.0-devel-ubuntu24.04 AS devel
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ENV DEBIAN_FRONTEND=noninteractive CMAKE_GENERATOR=Ninja CMAKE_BUILD_TYPE=Release
# hadolint ignore=DL3008
RUN apt-get update && apt-get install -y --no-install-recommends \
        autoconf automake build-essential bzip2 ca-certificates clang cmake curl git \
        libbz2-dev liblzma-dev libnuma-dev libtool llvm meson nasm ninja-build \
        pkg-config python3 python3-dev python3-venv xxd xz-utils zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /src

FROM devel AS nv-codec-headers
ARG NV_CODEC_HEADERS_VERSION
RUN curl -fsSL "https://github.com/FFmpeg/nv-codec-headers/archive/refs/tags/n${NV_CODEC_HEADERS_VERSION}.tar.gz" \
        | tar xz --strip-components=1 \
    && make PREFIX=/usr/local DESTDIR=/out install

FROM devel AS vulkan
ARG VULKAN_SDK_VERSION
RUN curl -fsSL "https://github.com/KhronosGroup/Vulkan-Headers/archive/refs/tags/vulkan-sdk-${VULKAN_SDK_VERSION}.tar.gz" \
        | tar xz \
    && cmake -S "Vulkan-Headers-vulkan-sdk-${VULKAN_SDK_VERSION}" -B headers -DCMAKE_INSTALL_PREFIX=/usr/local \
    && DESTDIR=/out cmake --install headers \
    && git clone --depth 1 -b "vulkan-sdk-${VULKAN_SDK_VERSION}" https://github.com/KhronosGroup/glslang.git
WORKDIR /src/glslang
RUN python3 update_glslang_sources.py --site github \
    && cmake -S . -B build -DCMAKE_INSTALL_PREFIX=/usr/local \
        -DBUILD_SHARED_LIBS=OFF -DCMAKE_POSITION_INDEPENDENT_CODE=ON -DENABLE_OPT=ON -DGLSLANG_TESTS=OFF \
        -DSPIRV_SKIP_TESTS=ON -DSPIRV_SKIP_EXECUTABLES=ON \
    && cmake --build build -j"$(nproc)" \
    && DESTDIR=/out cmake --install build

FROM devel AS x264
ARG X264_COMMIT
RUN curl -fsSL "https://code.videolan.org/videolan/x264/-/archive/${X264_COMMIT}/x264-${X264_COMMIT}.tar.bz2" \
        | tar xj --strip-components=1 \
    && ./configure --prefix=/usr/local --enable-shared --enable-pic --disable-cli \
    && make -j"$(nproc)" \
    && make install DESTDIR=/out

FROM devel AS x265
ARG X265_VERSION
RUN curl -fsSL "https://bitbucket.org/multicoreware/x265_git/downloads/x265_${X265_VERSION}.tar.gz" \
        | tar xz --strip-components=1 \
    && cmake -S source -B b12 -DENABLE_CLI=OFF -DENABLE_PIC=ON -DHIGH_BIT_DEPTH=ON -DMAIN12=ON -DEXPORT_C_API=OFF -DENABLE_SHARED=OFF \
    && cmake -S source -B b10 -DENABLE_CLI=OFF -DENABLE_PIC=ON -DHIGH_BIT_DEPTH=ON -DEXPORT_C_API=OFF -DENABLE_SHARED=OFF \
    && cmake --build b12 -j"$(nproc)" \
    && cmake --build b10 -j"$(nproc)" \
    && cmake -S source -B b8 -DENABLE_CLI=OFF -DENABLE_PIC=ON -DCMAKE_INSTALL_PREFIX=/usr/local -DENABLE_SHARED=ON \
        -DEXTRA_LIB="/src/b10/libx265.a;/src/b12/libx265.a" -DLINKED_10BIT=ON -DLINKED_12BIT=ON \
    && cmake --build b8 -j"$(nproc)" \
    && DESTDIR=/out cmake --install b8 \
    && rm -f /out/usr/local/lib/libx265.a

FROM devel AS svtav1
ARG SVTAV1_VERSION
RUN curl -fsSL "https://github.com/AOMediaCodec/SVT-AV1/archive/refs/tags/v${SVTAV1_VERSION}.tar.gz" \
        | tar xz --strip-components=1 \
    && cmake -S . -B build -DCMAKE_INSTALL_PREFIX=/usr/local \
        -DCMAKE_INSTALL_LIBDIR=lib -DBUILD_SHARED_LIBS=ON -DBUILD_APPS=OFF -DBUILD_TESTING=OFF \
    && cmake --build build -j"$(nproc)" \
    && DESTDIR=/out cmake --install build

FROM devel AS libvpx
ARG LIBVPX_VERSION
RUN curl -fsSL "https://github.com/webmproject/libvpx/archive/refs/tags/v${LIBVPX_VERSION}.tar.gz" \
        | tar xz --strip-components=1 \
    && ./configure --prefix=/usr/local --as=nasm --enable-shared --disable-static --enable-pic \
        --enable-vp9-highbitdepth --disable-examples --disable-tools --disable-docs --disable-unit-tests \
    && make -j"$(nproc)" \
    && make install DESTDIR=/out

FROM devel AS dav1d
ARG DAV1D_VERSION
RUN curl -fsSL "https://code.videolan.org/videolan/dav1d/-/archive/${DAV1D_VERSION}/dav1d-${DAV1D_VERSION}.tar.bz2" \
        | tar xj --strip-components=1 \
    && meson setup build --prefix=/usr/local --libdir=lib --buildtype=release -Denable_tools=false -Denable_tests=false \
    && ninja -C build \
    && DESTDIR=/out meson install -C build

FROM devel AS vmaf
ARG VMAF_VERSION
COPY --from=nv-codec-headers /out/ /
RUN curl -fsSL "https://github.com/Netflix/vmaf/archive/refs/tags/v${VMAF_VERSION}.tar.gz" \
        | tar xz --strip-components=1 \
    && meson setup libvmaf/build libvmaf --prefix=/usr/local --libdir=lib --buildtype=release \
        -Denable_cuda=true -Denable_tests=false -Denable_docs=false -Denable_tools=false \
    && ninja -C libvmaf/build \
    && DESTDIR=/out meson install -C libvmaf/build

FROM devel AS ffmpeg-build
ARG FFMPEG_VERSION
COPY --from=nv-codec-headers /out/ /
COPY --from=vulkan /out/ /
COPY --from=x264 /out/ /
COPY --from=x265 /out/ /
COPY --from=svtav1 /out/ /
COPY --from=libvpx /out/ /
COPY --from=dav1d /out/ /
COPY --from=vmaf /out/ /
RUN ldconfig \
    && curl -fsSL "https://ffmpeg.org/releases/ffmpeg-${FFMPEG_VERSION}.tar.xz" | tar xJ --strip-components=1 \
    && ./configure --prefix=/usr/local --enable-gpl --enable-shared --disable-static --disable-doc --disable-debug \
        --disable-autodetect --enable-pthreads --enable-iconv --enable-zlib --enable-bzlib --enable-lzma \
        --enable-ffnvcodec --enable-cuda --enable-cuda-llvm --enable-cuvid --enable-nvenc --enable-nvdec \
        --enable-vulkan --enable-libglslang \
        --enable-libx264 --enable-libx265 --enable-libsvtav1 --enable-libvpx --enable-libdav1d --enable-libvmaf \
        --extra-ldflags=-L/usr/local/lib \
    && make -j"$(nproc)" \
    && make install DESTDIR=/out \
    && rm -rf /src/*

FROM scratch AS ffmpeg-dist
COPY --from=x264 /out/ /
COPY --from=x265 /out/ /
COPY --from=svtav1 /out/ /
COPY --from=libvpx /out/ /
COPY --from=dav1d /out/ /
COPY --from=vmaf /out/ /
COPY --from=ffmpeg-build /out/ /

FROM devel AS pyenv
ARG NUMPY_VERSION
RUN python3 -m venv /opt/venv \
    && /opt/venv/bin/pip install --no-cache-dir "numpy==${NUMPY_VERSION}"

FROM devel AS nvstubs
ARG TORCHCODEC_COMMIT
COPY --from=nv-codec-headers /out/ /
COPY docker/nvstub.sh /usr/local/bin/nvstub
RUN mkdir -p /out/include \
    && for h in nvcuvid.h cuviddec.h; do \
        curl -fsSL -o "/out/include/$h" \
            "https://raw.githubusercontent.com/pytorch/torchcodec/${TORCHCODEC_COMMIT}/src/torchcodec/_core/nvcuvid_include/$h"; \
    done \
    && cp /usr/local/include/ffnvcodec/nvEncodeAPI.h /out/include/ \
    && grep -hoE '\bcuvid[A-Za-z0-9_]+[[:space:]]*\(' /out/include/nvcuvid.h /out/include/cuviddec.h \
        | tr -d ' (' | nvstub /out/lib libnvcuvid.so.1 \
    && grep -hoE '\bNvEncodeAPI[A-Za-z0-9_]+[[:space:]]*\(' /out/include/nvEncodeAPI.h \
        | tr -d ' (' | nvstub /out/lib libnvidia-encode.so.1 \
    && nm -D --defined-only /usr/local/cuda/lib64/stubs/libcuda.so | awk '{print $3}' \
        | nvstub /out/lib libcuda.so.1

FROM devel AS opencv-build
ARG OPENCV_VERSION
ARG CUDA_ARCH_BIN
ARG CUDA_ARCH_PTX
COPY --from=ffmpeg-dist /usr/local/ /usr/local/
COPY --from=pyenv /opt/venv /opt/venv
COPY --from=nvstubs /out/include/ /usr/local/cuda/include/
COPY --from=nvstubs /out/lib/ /opt/nvstubs/
RUN --mount=type=cache,target=/root/.cache/opencv \
    ldconfig \
    && curl -fsSL "https://github.com/opencv/opencv/archive/refs/tags/${OPENCV_VERSION}.tar.gz" | tar xz \
    && curl -fsSL "https://github.com/opencv/opencv_contrib/archive/refs/tags/${OPENCV_VERSION}.tar.gz" | tar xz \
    && cmake -S "opencv-${OPENCV_VERSION}" -B build \
        -DCMAKE_INSTALL_PREFIX=/usr/local \
        -DOPENCV_EXTRA_MODULES_PATH="/src/opencv_contrib-${OPENCV_VERSION}/modules" \
        -DOPENCV_DOWNLOAD_PATH=/root/.cache/opencv -DOPENCV_ENABLE_NONFREE=OFF \
        -DWITH_CUDA=ON -DCUDA_ARCH_BIN="${CUDA_ARCH_BIN}" -DCUDA_ARCH_PTX="${CUDA_ARCH_PTX}" \
        -DWITH_CUBLAS=ON -DWITH_CUFFT=ON -DWITH_CUDNN=OFF -DOPENCV_DNN_CUDA=OFF \
        -DWITH_NVCUVID=ON -DWITH_NVCUVENC=ON \
        -DCUDA_CUDA_LIBRARY=/opt/nvstubs/libcuda.so -DCUDA_nvcuvid_LIBRARY=/opt/nvstubs/libnvcuvid.so \
        -DCUDA_nvidia-encode_LIBRARY=/opt/nvstubs/libnvidia-encode.so \
        -DWITH_FFMPEG=ON -DWITH_GSTREAMER=OFF -DWITH_GTK=OFF -DWITH_QT=OFF -DWITH_OPENGL=OFF -DWITH_VTK=OFF \
        -DWITH_OPENEXR=OFF -DWITH_1394=OFF \
        -DBUILD_JPEG=ON -DBUILD_PNG=ON -DBUILD_TIFF=ON -DBUILD_WEBP=ON -DBUILD_OPENJPEG=ON \
        -DBUILD_TESTS=OFF -DBUILD_PERF_TESTS=OFF -DBUILD_EXAMPLES=OFF -DBUILD_DOCS=OFF \
        -DBUILD_opencv_apps=OFF -DBUILD_JAVA=OFF \
        -DBUILD_opencv_python3=ON -DPYTHON3_EXECUTABLE=/opt/venv/bin/python \
        -DPYTHON3_PACKAGES_PATH="$(/opt/venv/bin/python -c 'import sysconfig; print(sysconfig.get_path("platlib"))')" \
        -DOPENCV_GENERATE_PKGCONFIG=ON -DCMAKE_SKIP_INSTALL_RPATH=ON \
    && cmake --build build -j"$(nproc)" \
    && DESTDIR=/out cmake --install build \
    && rm -rf /src/*

FROM nvidia/cuda:13.5.0-base-ubuntu24.04 AS ffmpeg
ARG RUNTIME_PACKAGES
ARG NVIDIA_DRIVER_CAPABILITIES
ENV NVIDIA_DRIVER_CAPABILITIES=${NVIDIA_DRIVER_CAPABILITIES}
# hadolint ignore=DL3008
RUN apt-get update && apt-get install -y --no-install-recommends ${RUNTIME_PACKAGES} \
    && rm -rf /var/lib/apt/lists/*
COPY --from=ffmpeg-dist /usr/local/ /usr/local/
COPY docker/rootfs/ /
RUN ldconfig && ffmpeg -hide_banner -version
CMD ["ffmpeg", "-hide_banner", "-buildconf"]

FROM nvidia/cuda:13.5.0-runtime-ubuntu24.04 AS optical
ARG RUNTIME_PACKAGES
ARG NVIDIA_DRIVER_CAPABILITIES
ENV NVIDIA_DRIVER_CAPABILITIES=${NVIDIA_DRIVER_CAPABILITIES}
# hadolint ignore=DL3008
RUN apt-get update && apt-get install -y --no-install-recommends ${RUNTIME_PACKAGES} python3 \
    && rm -rf /var/lib/apt/lists/*
COPY --from=ffmpeg-dist /usr/local/ /usr/local/
COPY --from=pyenv /opt/venv /opt/venv
COPY --from=opencv-build /out/ /
COPY docker/rootfs/ /
ENV PATH=/opt/venv/bin:${PATH}
RUN ldconfig && ffmpeg -hide_banner -version && python -c "import numpy"
CMD ["python"]

FROM optical AS optical-smoke
COPY --from=nvstubs /out/lib/ /opt/nvstubs/
ENV LD_LIBRARY_PATH=/opt/nvstubs:${LD_LIBRARY_PATH}

FROM optical
