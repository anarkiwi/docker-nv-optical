#!/bin/sh
# Build an empty-bodied shared library exporting every symbol name read from
# stdin, so binaries linked against NVIDIA driver libraries can be linked and
# loaded without a driver. Usage: nvstub.sh OUTDIR SONAME < symbols
set -eu
out=$1
soname=$2
mkdir -p "$out"
src=$(mktemp --suffix=.c)
sed 's/@.*//' | sort -u | sed 's/.*/void &(void) {}/' >"$src"
cc -shared -fPIC -O0 -Wl,-soname,"$soname" -o "$out/$soname" "$src"
ln -sf "$soname" "$out/${soname%.*}"
rm -f "$src"
