# racedash-ffmpeg

Pinned FFmpeg builds for RaceDash, each published together with its **complete corresponding source**.

RaceDash ships `ffmpeg` and `ffprobe` as separate executables. Those binaries are GPL-3.0 builds of FFmpeg, so every binary released here sits next to:
- the exact source it was built from;
- the scripts that built it;
- a `BUILDINFO.json` that records where every piece came from.

## Releases

| Platform | Release tag pattern | How it is produced |
|---|---|---|
| Windows x64 | `ffmpeg-n<version>-win64-<run>` | Mirrored, unmodified, from [BtbN/FFmpeg-Builds](https://github.com/BtbN/FFmpeg-Builds) (static `gpl` variant, never `nonfree`) by [`mirror-windows.yml`](.github/workflows/mirror-windows.yml) |
| Linux x64 (CI only) | `ffmpeg-n<version>-linux64-<run>` | Same workflow, with the `linux64-gpl` asset |
| macOS arm64 | `ffmpeg-<version>-macos-arm64-<run>` | Built here by [`build-macos.yml`](.github/workflows/build-macos.yml) from a trimmed, pinned fork of Martin Riedl's build script |

Every release holds:

| Asset | Contents |
|---|---|
| `ffmpeg[.exe]`, `ffprobe[.exe]` | The binaries |
| `racedash-ffmpeg-*-src.tar` (split into `.partNN` when over 2 GiB) | The complete corresponding source (below) |
| `BUILDINFO.json` | Provenance: upstream release, build run and commit, image digests, the FFmpeg revision, and the SHA-256 of every source archive and binary |
| `SHA256SUMS` | Checksums of every asset |
| `LICENSE-GPL-3.0.txt`, `NOTICE.txt` | Licence and notices |

## Where the source is

### Windows and Linux (BtbN mirror)

The source tar contains `src/` with:
- `ffmpeg-<commit>.tar.xz`: FFmpeg at the exact revision in the binary's version string (`…-g<rev>`);
- `FFmpeg-Builds-<commit>.tar.xz`: BtbN's build repository at the commit whose "Build FFmpeg" run produced the upstream release. It contains every build script, patch and image definition;
- `<stage>_<hash>.tar.xz`: one per dependency the build enabled for that target and variant.

The dependency archives are fetched with BtbN's own download commands, inside BtbN's base image. Each one is named exactly as the build's source cache, `.cache/downloads/<stage>_<hash>.tar.xz`, so you can drop it into a checkout of the build repository.

**To rebuild:**
1. Extract `FFmpeg-Builds-<commit>`.
2. Put the stage archives in `.cache/downloads/`.
3. Run `./makeimage.sh <target> <variant> <addin>`, then `./build.sh <target> <variant> <addin>`. In `build.sh`, point the FFmpeg checkout at the included revision; it clones by branch.

### macOS (built here)

The source tar contains:
- every tarball the build downloaded, each checked against [`macos/sources.sha256`](macos/sources.sha256) before use:
  - FFmpeg release tarball;
  - x264 at a pinned commit;
  - libvpx;
  - the build tools the script compiles;
- the patched build script as it ran.

**To rebuild:** run `macos/build.sh` on an Apple-silicon Mac with Xcode command-line tools. [`build-macos.yml`](.github/workflows/build-macos.yml) shows the exact invocation.

## What is linked into each binary

| Platform | Linked libraries (static) | Licences |
|---|---|---|
| macOS arm64 | FFmpeg; x264 (`0480cb05`); libvpx 1.16.0; zlib 1.3.2; Apple system frameworks (VideoToolbox, CoreMedia, CoreVideo, AudioToolbox, Metal, …; GPLv3 system-library exception) | GPL-3.0-or-later (FFmpeg `--enable-gpl --enable-version3`); x264 GPL-2.0-or-later; libvpx BSD-3-Clause; zlib Zlib |
| Windows x64 | Exactly the libraries BtbN's `win64 gpl 9.0` build enables, listed with their configure flags in `BUILDINFO.json` (`buildconf`) and one source archive each in `sources` | Each archive carries its own licence. The whole binary is GPL-3.0-or-later |

**macOS.** The vendored script also *builds* openssl, libxml2, fribidi, freetype, fontconfig, harfbuzz, libass, libogg and SDL, plus its build tools. Patch 04 keeps every one of them **out** of the binary. The acceptance step fails if any of them is configured in. Their tarballs are still archived, because they are part of what the script ran.

**Never included.** Acceptance and the mirror's licence gate fail a release whose configuration contains any of:
- `--enable-nonfree`;
- `--enable-decklink` (a proprietary SDK);
- `--enable-libklvanc`;
- `--enable-libopenh264` (Cisco's patent licence covers only Cisco's own binaries);
- `--enable-libfdk-aac`.

**Windows toolchain.** BtbN's `base-win64` image builds its cross toolchain (GCC, binutils, mingw-w64) with crosstool-ng, which it clones at an unpinned revision. The toolchain is therefore pinned only through the recorded image digest (`upstream.image`). The parts of it that end up in the binary are:
- libgcc and libstdc++, under the GCC Runtime Library Exception;
- the mingw-w64 CRT and winpthreads, under permissive licences.

None of these carries a source obligation for the binary. The image definitions are included in the build-repository archive.

## `BUILDINFO.json` (schema 2)

```jsonc
{
  "schema": 2,
  "platform": "darwin-arm64" | "win32-x64" | "linux-x64",
  "kind": "build" | "mirror",
  "license": "GPL-3.0-or-later",
  "ffmpegVersion": "9.0.2" | "n9.0.2-22-g46d8f462ee",   // `ffmpeg -version` starts with "ffmpeg version <ffmpegVersion>"
  "ffmpegRevision": "n9.0.2" | "<40-hex FFmpeg commit>",  // release tag (mac) or exact commit (mirror)
  "buildconf": "<the configure line>",
  "racedashFfmpegCommit": "<commit of this repository>",
  "runUrl": "<workflow run that produced the release>",
  "runnerImage": "<ImageOS ImageVersion>",
  "upstream": {                                           // kind-specific provenance
    // build:  script, scriptCommit, x264Commit, macosVersion, xcodebuildVersion, mesonVersion
    // mirror: release, asset, assetSha256, buildRepo, buildRepoCommit, runUrl, image, sourceFetchImage, target, variant, addin
  },
  "binaries": {
    "ffmpeg":  { "file": "ffmpeg[.exe]",  "sha256": "<hex>", "size": <bytes> },
    "ffprobe": { "file": "ffprobe[.exe]", "sha256": "<hex>", "size": <bytes> }
  },
  "sourceArchives": [ { "file": "racedash-ffmpeg-…-src.tar[.partNN]", "sha256": "<hex>", "size": <bytes> } ],
  "sources": [                                            // every item inside the source archive(s)
    { "name": "<path in the archive>", "url": "<upstream>", "revision": "<commit|rev|null>",
      "stage": "<BtbN scripts.d path|null>", "sha256": "<hex>", "extra": "<other SCRIPT_* pins, optional>" }
  ]
}
```

Consumers verify a binary with `binaries.<tool>.sha256`. `SHA256SUMS` lists every release asset, `BUILDINFO.json` included.

## Licences

- **The ffmpeg/ffprobe binaries and their sources:** GPL-3.0-or-later ([`LICENSE-GPL-3.0.txt`](LICENSE-GPL-3.0.txt)). The individual source archives keep their own licence files.
- **`macos/build-script/`:** Martin Riedl's [FFmpeg build script](https://git.martin-riedl.de/ffmpeg/build-script) at commit `6a611e1`, Apache License 2.0 ([`macos/build-script/LICENSE`](macos/build-script/LICENSE)). Our changes are listed in [`macos/BUILD-SCRIPT-NOTICE.txt`](macos/BUILD-SCRIPT-NOTICE.txt), and the patches are in [`macos/patches/`](macos/patches/).
- **Workflow and glue scripts written for this repository:** Apache License 2.0 ([`LICENSE-APACHE-2.0.txt`](LICENSE-APACHE-2.0.txt)).

FFmpeg is a trademark of Fabrice Bellard. These are unofficial builds, not endorsed by the FFmpeg project. See [`NOTICE.txt`](NOTICE.txt).
