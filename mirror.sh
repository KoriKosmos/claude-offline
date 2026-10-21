#!/bin/bash
# Run this ONLINE. Downloads everything Claude Code's install.sh would fetch
# (version pointer, manifest, binaries) into releases/ so the repo can be
# pushed to a private GitHub repo and installed later with install.sh, offline.
#
# Usage: ./mirror.sh [latest|stable|VERSION] [PLATFORM ...]
#   PLATFORM: linux-x64 linux-arm64 linux-x64-musl linux-arm64-musl
#             darwin-x64 darwin-arm64   (default: all six)
#
# Binaries are ~280MB, over GitHub's 100MB per-file limit, so each one is
# stored as 95MB parts (claude.part-aa, -ab, ...) and reassembled on install.

set -e
cd "$(dirname "$0")"

CHANNEL="${1:-latest}"
shift || true
PLATFORMS=("$@")
if [ ${#PLATFORMS[@]} -eq 0 ]; then
    PLATFORMS=(linux-x64 linux-arm64 linux-x64-musl linux-arm64-musl darwin-x64 darwin-arm64)
fi

DOWNLOAD_BASE_URL="https://downloads.claude.ai/claude-code-releases"
PART_SIZE="95m"

for cmd in curl jq split; do
    command -v "$cmd" >/dev/null 2>&1 || { echo "$cmd is required" >&2; exit 1; }
done

sha256() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | cut -d' ' -f1
    else
        shasum -a 256 "$1" | cut -d' ' -f1
    fi
}

if [[ "$CHANNEL" =~ ^[0-9]+\.[0-9]+\.[0-9]+ ]]; then
    version="$CHANNEL"
else
    version=$(curl -fsSL "$DOWNLOAD_BASE_URL/$CHANNEL")
fi
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+ ]]; then
    echo "Got an unexpected version from downloads.claude.ai: $version" >&2
    exit 1
fi
echo "Mirroring Claude Code $version"

dest="releases/$version"
mkdir -p "$dest"
curl -fsSL -o "$dest/manifest.json" "$DOWNLOAD_BASE_URL/$version/manifest.json"

for platform in "${PLATFORMS[@]}"; do
    checksum=$(jq -r ".platforms[\"$platform\"].checksum // empty" "$dest/manifest.json")
    if [[ ! "$checksum" =~ ^[a-f0-9]{64}$ ]]; then
        echo "Platform $platform not found in manifest" >&2
        exit 1
    fi
    pdir="$dest/$platform"
    if [ -f "$pdir/checksum" ] && [ "$(cat "$pdir/checksum")" = "$checksum" ]; then
        echo "  $platform: already mirrored"
        continue
    fi
    echo "  $platform: downloading"
    rm -rf "$pdir"
    mkdir -p "$pdir"
    tmp="$pdir/claude.tmp"
    curl -fSL --progress-bar -o "$tmp" "$DOWNLOAD_BASE_URL/$version/$platform/claude"
    if [ "$(sha256 "$tmp")" != "$checksum" ]; then
        echo "Checksum verification failed for $platform" >&2
        rm -rf "$pdir"
        exit 1
    fi
    split -b "$PART_SIZE" "$tmp" "$pdir/claude.part-"
    rm -f "$tmp"
    echo "$checksum" > "$pdir/checksum"
done

# The offline installer resolves "latest" and "stable" from these files.
echo "$version" > releases/latest
if [ "$CHANNEL" = "stable" ] || [ ! -f releases/stable ]; then
    echo "$version" > releases/stable
fi

echo ""
echo "Done. Commit and push:"
echo "    git add releases && git commit -m \"Mirror Claude Code $version\" && git push"
