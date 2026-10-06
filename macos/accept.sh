#!/usr/bin/env bash
# Acceptance checks for a macOS build. Fails on the first category with a
# problem, after printing every missing item in it.
# Usage: macos/accept.sh <dir-with-ffmpeg-and-ffprobe> <expected-version>
set -euo pipefail

BIN="${1:?bin dir}"
VERSION="${2:?expected version}"
FF="$BIN/ffmpeg"
FP="$BIN/ffprobe"
fail=0

first="$("$FF" -hide_banner -version | head -n1)"
echo "$first"
[[ "$first" == "ffmpeg version ${VERSION}"* ]] || { echo "FAIL: ffmpeg version is not ${VERSION}" >&2; fail=1; }
"$FP" -hide_banner -version | head -n1 | grep -q "ffprobe version ${VERSION}" || { echo "FAIL: ffprobe version is not ${VERSION}" >&2; fail=1; }

# Licence gates. Nothing nonfree, no proprietary DeckLink SDK, no libklvanc, and
# no source-built OpenH264 (Cisco's patent licence covers only Cisco's binaries).
if "$FF" -hide_banner -L | grep -Eqi "nonfree|not legally redistributable"; then
  echo "FAIL: ffmpeg -L reports nonfree parts or says the build is not redistributable" >&2; fail=1
fi
"$FF" -hide_banner -L | head -n 3
buildconf="$("$FF" -hide_banner -buildconf)"
for flag in --enable-nonfree --enable-decklink --enable-libklvanc --enable-libopenh264 \
            --enable-openssl --enable-libass --enable-libfreetype --enable-fontconfig --enable-libharfbuzz \
            --enable-libxml2 --enable-sdl2; do
  if grep -q -- "${flag}\b" <<<"$buildconf"; then
    echo "FAIL: configured with ${flag}" >&2; fail=1
  fi
done
grep -q -- "--enable-gpl" <<<"$buildconf" || { echo "FAIL: not configured with --enable-gpl" >&2; fail=1; }

check_list() {
  local what="$1" listing="$2"; shift 2
  local item
  for item in "$@"; do
    grep -Eq "^[[:space:]]*([A-Z.]+[[:space:]]+)?${item}([[:space:]]|$)" <<<"$listing" || { echo "FAIL: ${what} missing ${item}" >&2; fail=1; }
  done
}
check_list encoder "$("$FF" -hide_banner -encoders)" hevc_videotoolbox h264_videotoolbox libx264 libvpx-vp9 aac prores_ks
check_list filter "$("$FF" -hide_banner -filters)" scale_vt xfade overlay concat fade tpad acrossfade
check_list hwaccel "$("$FF" -hide_banner -hwaccels | tail -n +2)" videotoolbox

for exe in "$FF" "$FP"; do
  bad="$(otool -L "$exe" | tail -n +2 | awk '{print $1}' | grep -Ev '^(/usr/lib/|/System/)' || true)"
  if [[ -n "$bad" ]]; then
    echo "FAIL: $(basename "$exe") links non-system libraries:" >&2; echo "$bad" >&2; fail=1
  fi
done

# Crossfade smoke test: the same tpad + xfade graph shape the RaceDash composite builds.
T="$(mktemp -d)"
for n in a b; do
  "$FF" -hide_banner -loglevel error -y -f lavfi -i "testsrc2=s=320x180:r=30" -f lavfi -i "sine=r=48000" -t 2 \
    -c:v libx264 -pix_fmt yuv420p -c:a aac "$T/$n.mp4"
done
if "$FF" -hide_banner -loglevel error -y -i "$T/a.mp4" -i "$T/b.mp4" -filter_complex \
  "[0:v]setpts=PTS-STARTPTS[v0];[0:a]asetpts=PTS-STARTPTS[a0];[1:v]setpts=PTS-STARTPTS[v1];[1:a]asetpts=PTS-STARTPTS[a1];[v0]tpad=stop_mode=clone:stop_duration=0.3[hv];[hv][v1]xfade=transition=fade:duration=0.3:offset=2[v];[a0]apad=pad_dur=0.3[ha];[ha][a1]acrossfade=d=0.3[a]" \
  -map "[v]" -map "[a]" -c:v libx264 -pix_fmt yuv420p -c:a aac -frames:v 120 "$T/out.mp4"; then
  frames="$("$FP" -v error -count_frames -select_streams v:0 -show_entries stream=nb_read_frames -of csv=p=0 "$T/out.mp4")"
  [[ "$frames" == "120" ]] || { echo "FAIL: crossfade output has ${frames} frames, expected 120" >&2; fail=1; }
else
  echo "FAIL: crossfade smoke encode failed" >&2; fail=1
fi
rm -rf "$T"

if [[ $fail -ne 0 ]]; then
  echo "acceptance FAILED" >&2
  exit 1
fi
echo "acceptance passed"
