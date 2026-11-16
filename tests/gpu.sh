#!/bin/bash
# GPU checks, run inside the optical image with a GPU attached:
# NVENC encode, NVDEC decode, scale_cuda, libvmaf (CPU and CUDA), Vulkan scaling,
# then the OpenCV CUDA checks in gpu_optical.py.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
frames=60
step=0
total=11
ff=(ffmpeg -hide_banner -loglevel error -y)

log() {
    step=$((step + 1))
    printf '[%d/%d] %s\n' "$step" "$total" "$*"
}

count_frames() {
    ffprobe -v error -count_frames -select_streams v:0 -show_entries stream=nb_read_frames -of csv=p=0 "$1"
}

expect() {
    [[ $2 == "$3" ]] || {
        echo "$1: got $2, want $3" >&2
        exit 1
    }
}

vmaf_score() {
    sed -n 's/.*VMAF score: \([0-9.]*\).*/\1/p'
}

nvidia-smi --query-gpu=name,compute_cap,driver_version --format=csv,noheader

log "synthetic 1280x720 source"
"${ff[@]}" -f lavfi -i "testsrc2=size=1280x720:rate=30" -frames:v "$frames" -pix_fmt yuv420p -c:v ffv1 "$work/src.nut"

for codec in h264_nvenc hevc_nvenc av1_nvenc; do
    log "NVENC $codec"
    "${ff[@]}" -i "$work/src.nut" -c:v "$codec" -preset p4 -rc vbr -cq 23 -b:v 0 "$work/$codec.mp4"
    expect "$codec frames" "$(count_frames "$work/$codec.mp4")" "$frames"
done

log "NVENC lossless HEVC reference"
"${ff[@]}" -i "$work/src.nut" -c:v hevc_nvenc -tune lossless "$work/ref.mp4"

log "NVDEC decode (cuda hwaccel and cuvid decoders)"
for codec in h264 hevc av1; do
    n=$("${ff[@]}" -hwaccel cuda -i "$work/${codec}_nvenc.mp4" -f framecrc - | grep -vc '^#')
    expect "$codec hwaccel decode" "$n" "$frames"
    n=$("${ff[@]}" -c:v "${codec}_cuvid" -i "$work/${codec}_nvenc.mp4" -f framecrc - | grep -vc '^#')
    expect "${codec}_cuvid decode" "$n" "$frames"
done

log "scale_cuda on decoded GPU frames, re-encoded with NVENC"
"${ff[@]}" -hwaccel cuda -hwaccel_output_format cuda -i "$work/h264_nvenc.mp4" \
    -vf scale_cuda=640:360 -c:v h264_nvenc "$work/scaled.mp4"
expect "scale_cuda size" "$(ffprobe -v error -show_entries stream=width,height -of csv=p=0 "$work/scaled.mp4")" "640,360"

log "libvmaf (CPU)"
cpu=$(ffmpeg -hide_banner -i "$work/hevc_nvenc.mp4" -i "$work/src.nut" -lavfi libvmaf -f null - 2>&1 | vmaf_score)
echo "VMAF hevc_nvenc vs source: $cpu"
awk -v s="$cpu" 'BEGIN { exit !(s > 80 && s <= 100) }'

log "libvmaf_cuda on NVDEC frames"
cuda=$(ffmpeg -hide_banner \
    -hwaccel cuda -hwaccel_output_format cuda -i "$work/hevc_nvenc.mp4" \
    -hwaccel cuda -hwaccel_output_format cuda -i "$work/ref.mp4" \
    -filter_complex "[0:v]scale_cuda=format=yuv420p[d];[1:v]scale_cuda=format=yuv420p[r];[d][r]libvmaf_cuda" \
    -f null - 2>&1 | vmaf_score)
echo "VMAF (CUDA) hevc_nvenc vs lossless reference: $cuda"
awk -v c="$cuda" -v s="$cpu" 'BEGIN { d = c - s; exit !(c > 80 && c <= 100 && d < 1 && d > -1) }'

log "Vulkan upload, scale_vulkan, download"
"${ff[@]}" -init_hw_device vulkan=vk -filter_hw_device vk -i "$work/src.nut" \
    -vf "hwupload,scale_vulkan=w=640:h=360,hwdownload,format=yuv420p" -c:v ffv1 "$work/vulkan.mkv"
expect "scale_vulkan size" "$(ffprobe -v error -show_entries stream=width,height -of csv=p=0 "$work/vulkan.mkv")" "640,360"

log "OpenCV CUDA: NvidiaOpticalFlow_2_0 and cudacodec"
"${ff[@]}" -i "$work/src.nut" -c:v hevc_nvenc "$work/cudacodec.mkv"
python "$here/gpu_optical.py" "$work/cudacodec.mkv"

echo "GPU tests passed"
