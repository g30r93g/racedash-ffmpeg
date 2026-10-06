#!/usr/bin/env bash
# Build the RaceDash macOS ffmpeg/ffprobe from the vendored, patched build
# script, and collect everything it downloaded as the corresponding source.
#
# Usage: macos/build.sh <work-dir>
#
# Environment:
#   RACEDASH_SOURCES_STRICT  YES (default) fails on any download without a
#                            pinned sha256 in macos/sources.sha256; NO only
#                            warns, to bootstrap the list after a version bump.
#   RACEDASH_MESON_VERSION   meson version installed by the script (default in patch 01).
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
WORK="${1:?usage: macos/build.sh <work-dir>}"
mkdir -p "$WORK"
WORK="$(cd "$WORK" && pwd)"

rm -rf "$WORK/build-script" "$WORK/build" "$WORK/source-archive"
cp -R "$HERE/build-script" "$WORK/build-script"
for p in "$HERE"/patches/*.patch; do
  (cd "$WORK/build-script" && patch -p1 --forward < "$p")
done

export RACEDASH_SOURCES_SHA256="$HERE/sources.sha256"
export RACEDASH_SOURCE_ARCHIVE="$WORK/source-archive"
export RACEDASH_SOURCES_STRICT="${RACEDASH_SOURCES_STRICT:-YES}"
mkdir -p "$WORK/build" "$RACEDASH_SOURCE_ARCHIVE"

# Only x264 (software fallback) and libvpx (VP9 alpha) as optional codecs.
# VideoToolbox comes from the system. The script always builds its base set
# (zlib, openssl, libxml2, fribidi, freetype, fontconfig, harfbuzz, libass,
# libogg, SDL) and its build tools; their sources are archived like the rest.
(cd "$WORK/build" && sh "$WORK/build-script/build.sh" \
  -SKIP_BUNDLE=YES -SKIP_TEST=YES \
  -SKIP_LIBBLURAY=YES -SKIP_SNAPPY=YES -SKIP_SRT=YES -SKIP_LIBVMAF=YES -SKIP_ZIMG=YES -SKIP_ZVBI=YES \
  -SKIP_AOM=YES -SKIP_DAV1D=YES -SKIP_OPEN_H264=YES -SKIP_OPEN_JPEG=YES -SKIP_RAV1E=YES -SKIP_SVT_AV1=YES \
  -SKIP_LIBTHEORA=YES -SKIP_VVENC=YES -SKIP_LIBWEBP=YES -SKIP_X265=YES -SKIP_X265_MULTIBIT=YES \
  -SKIP_LAME=YES -SKIP_OPUS=YES -SKIP_LIBVORBIS=YES -SKIP_LIBKLVANC=YES -SKIP_DECKLINK=YES \
  -SKIP_X264=NO -SKIP_VPX=NO)

# The scripts that controlled compilation, as they ran.
cp -R "$WORK/build-script" "$RACEDASH_SOURCE_ARCHIVE/build-script-patched"
mkdir -p "$RACEDASH_SOURCE_ARCHIVE/racedash-ffmpeg"
cp -R "$HERE/patches" "$HERE/build.sh" "$HERE/accept.sh" "$HERE/sources.sha256" "$RACEDASH_SOURCE_ARCHIVE/racedash-ffmpeg/"
cp "$HERE/../.github/workflows/build-macos.yml" "$RACEDASH_SOURCE_ARCHIVE/racedash-ffmpeg/"

echo "built: $WORK/build/out/bin"
ls -la "$WORK/build/out/bin"
