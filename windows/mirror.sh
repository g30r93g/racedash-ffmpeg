#!/usr/bin/env bash
# Mirror one BtbN/FFmpeg-Builds static binary and collect its complete
# corresponding source.
#
# The source collection reuses BtbN's own download step: for every build stage
# that `generate.sh <target> <variant> <addin>` enables, the stage's
# `ffbuild_dockerdl` commands are run inside BtbN's base image, exactly as
# BtbN's `download.sh` does, and the result is archived under the same
# `<stage>_<hash>.tar.xz` name the build mounted as its source cache.
#
# Required environment:
#   BTBN_TAG         BtbN release tag, e.g. autobuild-2026-10-06-13-06
#   BTBN_ASSET       asset file name, e.g. ffmpeg-n9.0.2-22-g46d8f462ee-win64-gpl-9.0.zip
#   BTBN_RUN_ID      id of the BtbN "Build FFmpeg" run that produced the release
#   BTBN_TARGET      e.g. win64
#   BTBN_VARIANT     e.g. gpl            (never nonfree*)
#   BTBN_ADDIN       e.g. 9.0
#   IMAGE_DIGEST     sha256:... of ghcr.io/btbn/ffmpeg-builds/<target>-<variant>-<addin> used by that run
#   OUT_DIR          where release assets are written
#   GH_TOKEN         for the GitHub API (read-only use of public data)
set -euo pipefail
[[ -n "${TRACE:-}" ]] && set -x

: "${BTBN_TAG:?}" "${BTBN_ASSET:?}" "${BTBN_RUN_ID:?}" "${BTBN_TARGET:?}" "${BTBN_VARIANT:?}" "${BTBN_ADDIN:?}"
: "${IMAGE_DIGEST:?}" "${OUT_DIR:?}"

case "$BTBN_VARIANT" in
  nonfree*) echo "refusing a nonfree variant: it is not redistributable" >&2; exit 1 ;;
esac

WORK="$(mktemp -d)"
SRC="$WORK/src"
mkdir -p "$SRC" "$OUT_DIR"
REL_URL="https://github.com/BtbN/FFmpeg-Builds/releases/download/${BTBN_TAG}"

# 1. Binary: download, verify against BtbN's published checksums, extract.
curl -fsSL -o "$WORK/$BTBN_ASSET" "$REL_URL/$BTBN_ASSET"
curl -fsSL -o "$WORK/btbn-checksums.sha256" "$REL_URL/checksums.sha256"
(cd "$WORK" && grep " ${BTBN_ASSET}\$" btbn-checksums.sha256 | sha256sum -c -)
ASSET_SHA256="$(sha256sum "$WORK/$BTBN_ASSET" | cut -d' ' -f1)"
(cd "$WORK" && unzip -q "$BTBN_ASSET")
PKG="$WORK/${BTBN_ASSET%.zip}"
for tool in ffmpeg ffprobe; do
  cp "$PKG/bin/${tool}.exe" "$OUT_DIR/${tool}.exe"
done
cp "$PKG/LICENSE.txt" "$OUT_DIR/LICENSE-ffmpeg-upstream.txt"

# FFmpeg revision from the asset name: ffmpeg-n9.0.2-22-g46d8f462ee-... -> 46d8f462ee
FF_SHORT="$(sed -E 's/^ffmpeg-.*-g([0-9a-f]{7,})-.*$/\1/' <<<"$BTBN_ASSET")"
[[ "$FF_SHORT" =~ ^[0-9a-f]{7,}$ ]] || { echo "cannot parse the FFmpeg revision from $BTBN_ASSET" >&2; exit 1; }

# 2. Provenance: the run that built the release, and its build-repo commit.
RUN_JSON="$(gh api "repos/BtbN/FFmpeg-Builds/actions/runs/${BTBN_RUN_ID}")"
BUILD_REPO_COMMIT="$(jq -r .head_sha <<<"$RUN_JSON")"
RUN_URL="$(jq -r .html_url <<<"$RUN_JSON")"
[[ "$(jq -r .name <<<"$RUN_JSON")" == "Build FFmpeg" && "$(jq -r .conclusion <<<"$RUN_JSON")" == "success" ]] || {
  echo "run ${BTBN_RUN_ID} is not a successful Build FFmpeg run" >&2; exit 1; }
# The release tag must point at the run's commit, and the release must have
# been published after the run started, on the same day.
TAG_COMMIT="$(gh api "repos/BtbN/FFmpeg-Builds/git/ref/tags/${BTBN_TAG}" -q .object.sha)"
[[ "$TAG_COMMIT" == "$BUILD_REPO_COMMIT" ]] || {
  echo "tag ${BTBN_TAG} points at ${TAG_COMMIT}, run ${BTBN_RUN_ID} built ${BUILD_REPO_COMMIT}" >&2; exit 1; }
REL_PUBLISHED="$(gh api "repos/BtbN/FFmpeg-Builds/releases/tags/${BTBN_TAG}" -q .published_at)"
RUN_STARTED="$(jq -r .run_started_at <<<"$RUN_JSON")"
[[ "$REL_PUBLISHED" > "$RUN_STARTED" && "${REL_PUBLISHED:0:10}" == "${RUN_STARTED:0:10}" ]] || {
  echo "release ${BTBN_TAG} (published ${REL_PUBLISHED}) does not follow run ${BTBN_RUN_ID} (${RUN_STARTED})" >&2; exit 1; }

# 3. Source: BtbN build repository at that commit (scripts, patches, image definitions).
git clone -q https://github.com/BtbN/FFmpeg-Builds.git "$WORK/btbn"
git -C "$WORK/btbn" checkout -q "$BUILD_REPO_COMMIT"
git -C "$WORK/btbn" archive --format=tar --prefix="FFmpeg-Builds-${BUILD_REPO_COMMIT}/" "$BUILD_REPO_COMMIT" \
  | xz -T0 -9 > "$SRC/FFmpeg-Builds-${BUILD_REPO_COMMIT}.tar.xz"

# 4. Source: FFmpeg at the exact revision.
git clone -q --filter=blob:none https://github.com/FFmpeg/FFmpeg.git "$WORK/ffmpeg"
FF_COMMIT="$(git -C "$WORK/ffmpeg" rev-parse --verify "${FF_SHORT}^{commit}")"
git -C "$WORK/ffmpeg" archive --format=tar --prefix="ffmpeg-${FF_COMMIT}/" "$FF_COMMIT" \
  | xz -T0 -9 > "$SRC/ffmpeg-${FF_COMMIT}.tar.xz"

# 5. Source: every enabled dependency stage, fetched with BtbN's own download commands.
(cd "$WORK/btbn" && ./generate.sh "$BTBN_TARGET" "$BTBN_VARIANT" "$BTBN_ADDIN") || { echo "generate.sh failed" >&2; exit 1; }
# Pair each stage script with the source cache it mounts. generate.sh writes
# `ENV SELF="<script>" ...` immediately before that stage's RUN line.
awk '
  /^ENV SELF="/ { match($0, /SELF="[^"]+"/); self = substr($0, RSTART + 6, RLENGTH - 7); next }
  /\.cache\/downloads\// && self != "" {
    match($0, /\.cache\/downloads\/[^,[:space:]]+\.tar\.xz/)
    print self, substr($0, RSTART + 17, RLENGTH - 17); self = ""
  }
' "$WORK/btbn/Dockerfile" | sort -u > "$WORK/stage-caches.txt"
[[ -s "$WORK/stage-caches.txt" ]] || { echo "generate.sh produced no download stages" >&2; exit 1; }
mapfile -t STAGE_CACHES < <(cut -d' ' -f2 "$WORK/stage-caches.txt")
echo "enabled stages with sources: ${#STAGE_CACHES[@]}"

DL_SCRIPTS="$WORK/dl-stages"
mkdir -p "$DL_SCRIPTS" "$WORK/dldir"
while read -r STAGE CACHE; do
  STAGENAME="${CACHE%_*}"
  [[ -f "$WORK/btbn/$STAGE" ]] || { echo "no script $STAGE for $CACHE" >&2; exit 1; }
  # Same body as BtbN download.sh, minus the hash-only mode.
  cat >"$DL_SCRIPTS/${STAGENAME}.sh" <<STAGE_EOF
set -xe -o pipefail
shopt -s dotglob
source /dl_functions.sh
source "/$STAGE"
STG="\$(ffbuild_dockerdl)"
[[ -n "\$STG" ]] || exit 0
DLHASH="\$(sha256sum <<<"\$STG" | cut -d" " -f1)"
TGT="/dldir/${STAGENAME}_\${DLHASH}.tar.xz"
WORKDIR="\$(mktemp -d)"
cd "\$WORKDIR"
eval "set -e; \$STG"
tar -I "xz -T0" -cpf "\$TGT.tmp" .
mv "\$TGT.tmp" "\$TGT"
STAGE_EOF
done < "$WORK/stage-caches.txt"

BASE_IMAGE="ghcr.io/btbn/ffmpeg-builds/base:latest"
docker pull -q "$BASE_IMAGE"
BASE_IMAGE_DIGEST="$(docker inspect --format '{{index .RepoDigests 0}}' "$BASE_IMAGE")"
docker run --rm -u "$(id -u):$(id -g)" \
  -v "$DL_SCRIPTS":/stages -v "$WORK/dldir":/dldir \
  -v "$WORK/btbn/scripts.d":/scripts.d -v "$WORK/btbn/util/dl_functions.sh":/dl_functions.sh \
  "$BASE_IMAGE" bash -c 'set -xe && for STAGE in /stages/*.sh; do bash $STAGE; done'

# Every cache the build mounted must now exist under the same name.
for CACHE in "${STAGE_CACHES[@]}"; do
  [[ -f "$WORK/dldir/$CACHE" ]] || { echo "missing source archive $CACHE" >&2; exit 1; }
  mv "$WORK/dldir/$CACHE" "$SRC/$CACHE"
done

# 6. One source archive (split if it exceeds the 2 GiB release-asset limit).
SRC_NAME="racedash-ffmpeg-${FF_SHORT}-${BTBN_TARGET}-src.tar"
tar -C "$WORK" -cf "$WORK/$SRC_NAME" src
SRC_PARTS=()
if [[ "$(stat -c %s "$WORK/$SRC_NAME")" -gt 1900000000 ]]; then
  split -b 1900m -d -a 2 "$WORK/$SRC_NAME" "$OUT_DIR/${SRC_NAME}.part"
  mapfile -t SRC_PARTS < <(cd "$OUT_DIR" && ls "${SRC_NAME}".part*)
else
  mv "$WORK/$SRC_NAME" "$OUT_DIR/$SRC_NAME"
  SRC_PARTS=("$SRC_NAME")
fi

# 7. BUILDINFO.json and SHA256SUMS.
SOURCES_JSON="$(cd "$SRC" && for f in *; do jq -n --arg file "$f" --arg sha256 "$(sha256sum "$f" | cut -d' ' -f1)" '{file: $file, sha256: $sha256}'; done | jq -s .)"
jq -n \
  --arg upstreamRelease "https://github.com/BtbN/FFmpeg-Builds/releases/tag/${BTBN_TAG}" \
  --arg upstreamAsset "$BTBN_ASSET" --arg upstreamAssetSha256 "$ASSET_SHA256" \
  --arg upstreamBuildRepo "https://github.com/BtbN/FFmpeg-Builds" \
  --arg upstreamBuildRepoCommit "$BUILD_REPO_COMMIT" --arg upstreamRunUrl "$RUN_URL" \
  --arg upstreamImage "ghcr.io/btbn/ffmpeg-builds/${BTBN_TARGET}-${BTBN_VARIANT}-${BTBN_ADDIN}@${IMAGE_DIGEST}" \
  --arg sourceFetchImage "$BASE_IMAGE_DIGEST" \
  --arg target "$BTBN_TARGET" --arg variant "$BTBN_VARIANT" --arg addin "$BTBN_ADDIN" \
  --arg ffmpegRepo "https://github.com/FFmpeg/FFmpeg" --arg ffmpegRevision "$FF_COMMIT" \
  --arg buildRepo "https://github.com/${GITHUB_REPOSITORY:-g30r93g/racedash-ffmpeg}" \
  --arg buildRepoCommit "${GITHUB_SHA:-unknown}" \
  --arg workflowRunUrl "${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY:-}/actions/runs/${GITHUB_RUN_ID:-}" \
  --arg ffmpegSha256 "$(sha256sum "$OUT_DIR/ffmpeg.exe" | cut -d' ' -f1)" \
  --arg ffprobeSha256 "$(sha256sum "$OUT_DIR/ffprobe.exe" | cut -d' ' -f1)" \
  --argjson sourceArchives "$(printf '%s\n' "${SRC_PARTS[@]}" | jq -R . | jq -s .)" \
  --argjson sources "$SOURCES_JSON" \
  '{schema: 1, kind: "mirror", license: "GPL-3.0-or-later",
    target: $target, variant: $variant, addin: $addin,
    upstreamRelease: $upstreamRelease, upstreamAsset: $upstreamAsset, upstreamAssetSha256: $upstreamAssetSha256,
    upstreamBuildRepo: $upstreamBuildRepo, upstreamBuildRepoCommit: $upstreamBuildRepoCommit,
    upstreamRunUrl: $upstreamRunUrl, upstreamImage: $upstreamImage, sourceFetchImage: $sourceFetchImage,
    ffmpegRepo: $ffmpegRepo, ffmpegRevision: $ffmpegRevision,
    buildRepo: $buildRepo, buildRepoCommit: $buildRepoCommit, workflowRunUrl: $workflowRunUrl,
    binaries: {"ffmpeg.exe": $ffmpegSha256, "ffprobe.exe": $ffprobeSha256},
    sourceArchives: $sourceArchives,
    sources: $sources}' > "$OUT_DIR/BUILDINFO.json"

cp "$(dirname "$0")/../LICENSE-GPL-3.0.txt" "$(dirname "$0")/../NOTICE.txt" "$OUT_DIR/"
(cd "$OUT_DIR" && sha256sum -- * | grep -v ' SHA256SUMS$' > SHA256SUMS)
echo "mirror complete: $OUT_DIR"
ls -la "$OUT_DIR"
