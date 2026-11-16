#!/bin/bash
# GPU-free checks of the ffmpeg build: feature lists, licence flags and CPU codec round trips.
set -euo pipefail

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
step=0
total=12

log() {
    step=$((step + 1))
    printf '[%d/%d] %s\n' "$step" "$total" "$*"
}

require_names() {
    local kind=$1
    shift
    local listing
    listing=$(ffmpeg -hide_banner "-$kind")
    for name in "$@"; do
        grep -qE "(^|[[:space:]])${name}([[:space:]]|$)" <<<"$listing" || {
            echo "missing $kind entry: $name" >&2
            exit 1
        }
    done
}

log "encoders"
require_names encoders h264_nvenc hevc_nvenc av1_nvenc libx264 libx265 libsvtav1 libvpx-vp9 ffv1_vulkan

log "decoders"
require_names decoders libdav1d h264_cuvid hevc_cuvid av1_cuvid vp9_cuvid libvpx-vp9

log "filters"
require_names filters scale_cuda bilateral_cuda bwdif_cuda chromakey_cuda colorspace_cuda overlay_cuda \
    thumbnail_cuda yadif_cuda hwupload_cuda libvmaf libvmaf_cuda scale_vulkan avgblur_vulkan hwupload hwdownload

log "hwaccels"
hwaccels=$(ffmpeg -hide_banner -hwaccels)
for name in cuda vulkan; do
    grep -qx "$name" <<<"$hwaccels" || {
        echo "missing hwaccel: $name" >&2
        exit 1
    }
done

log "buildconf is GPL without nonfree"
buildconf=$(ffmpeg -hide_banner -buildconf)
grep -q -- '--enable-gpl' <<<"$buildconf"
grep -q -- '--enable-cuda-llvm' <<<"$buildconf"
if grep -qE -- 'nonfree|libnpp|libfdk|cuda-nvcc' <<<"$buildconf"; then
    echo "buildconf contains a non-redistributable option" >&2
    exit 1
fi
ffmpeg -hide_banner -L | grep -q 'GNU General Public License'

log "synthetic source"
ffmpeg -hide_banner -loglevel error -f lavfi -i testsrc2=size=320x240:rate=25:duration=2 \
    -pix_fmt yuv420p -c:v ffv1 "$work/src.nut"

encode() {
    local codec=$1 ext=$2
    shift 2
    log "encode $codec"
    ffmpeg -hide_banner -loglevel error -i "$work/src.nut" -c:v "$codec" "$@" "$work/$codec.$ext"
    local frames
    frames=$(ffprobe -v error -count_frames -select_streams v:0 -show_entries stream=nb_read_frames \
        -of csv=p=0 "$work/$codec.$ext")
    [[ $frames == 50 ]] || {
        echo "$codec produced $frames frames" >&2
        exit 1
    }
}

encode libx264 mp4 -preset veryfast -crf 18
encode libx265 mp4 -preset veryfast -crf 18
encode libsvtav1 mkv -preset 12 -crf 30
encode libvpx-vp9 webm -deadline realtime -cpu-used 8 -b:v 1M

log "decode with libdav1d"
ffmpeg -hide_banner -loglevel error -c:v libdav1d -i "$work/libsvtav1.mkv" -f null -

log "libvmaf score"
score=$(ffmpeg -hide_banner -i "$work/libx264.mp4" -i "$work/src.nut" -lavfi libvmaf -f null - 2>&1 |
    sed -n 's/.*VMAF score: \([0-9.]*\).*/\1/p')
echo "VMAF $score"
awk -v s="$score" 'BEGIN { exit !(s > 80 && s <= 100) }'

echo "ffmpeg smoke tests passed"
