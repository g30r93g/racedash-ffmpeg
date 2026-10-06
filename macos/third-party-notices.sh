#!/usr/bin/env bash
# Write THIRD-PARTY-NOTICES.txt for the macOS binaries: the licence texts of
# FFmpeg and of every library linked into them, taken from the exact source
# tarballs the build used.
# Usage: macos/third-party-notices.sh <source-archive/downloads> <out-file>
set -euo pipefail

DL="${1:?downloads dir}"
OUT="${2:?output file}"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

# name | tarball glob in downloads/ | licence files inside the tarball (first dir level)
LIBS=(
  "FFmpeg 9.0.2|*-ffmpeg.tar.bz2|LICENSE.md COPYING.GPLv3 COPYING.GPLv2 COPYING.LGPLv3 COPYING.LGPLv2.1"
  "x264 (commit 0480cb05fa188d37ae87e8f4fd8f1aea3711f7ee)|*-x264-*.tar.gz|COPYING"
  "libvpx 1.16.0|*-vpx.tar.gz|LICENSE PATENTS"
  "zlib 1.3.2|*-zlib.tar.gz|LICENSE"
)

{
  echo "Third-party notices for the RaceDash ffmpeg / ffprobe binaries (macOS arm64)"
  echo "==========================================================================="
  echo
  echo "These binaries are FFmpeg built with --enable-gpl --enable-version3 and"
  echo "statically linked with the libraries below. Apple system frameworks and"
  echo "libraries (/System, /usr/lib) are used as system libraries and are not"
  echo "distributed. The complete corresponding source is the source archive on"
  echo "the same release."
  echo
} > "$OUT"

for entry in "${LIBS[@]}"; do
  IFS='|' read -r name glob files <<<"$entry"
  tarball="$(ls "$DL"/$glob 2>/dev/null | head -n1)"
  [[ -n "$tarball" ]] || { echo "no tarball matching $glob in $DL" >&2; exit 1; }
  dir="$T/$(basename "$tarball")"
  mkdir -p "$dir"
  tar -xf "$tarball" -C "$dir"
  top="$(find "$dir" -mindepth 1 -maxdepth 1 -type d | head -n1)"
  found=0
  for f in $files; do
    [[ -f "$top/$f" ]] || continue
    found=1
    {
      echo "--------------------------------------------------------------------------"
      echo "$name: $f"
      echo "--------------------------------------------------------------------------"
      cat "$top/$f"
      echo
    } >> "$OUT"
  done
  [[ $found -eq 1 ]] || { echo "no licence file found for $name in $tarball" >&2; exit 1; }
done
echo "wrote $OUT"
