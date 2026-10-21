#!/bin/bash
# Offline Claude Code installer. Works from a clone of this repo with no
# network access: it uses the binaries mirror.sh stored under releases/
# instead of downloads.claude.ai.
#
# Usage: ./install.sh [latest|stable|VERSION]

set -e

TARGET="${1:-latest}"
if [[ ! "$TARGET" =~ ^(stable|latest|[0-9]+\.[0-9]+\.[0-9]+(-[^[:space:]]+)?)$ ]]; then
    echo "Usage: $0 [stable|latest|VERSION]" >&2
    exit 1
fi

if [ "$(id -u)" -eq 0 ] && [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ] && [ -z "${CLAUDE_INSTALL_ALLOW_SUDO:-}" ]; then
    echo "Error: do not run this installer with sudo." >&2
    echo "Claude Code installs into your home directory and does not need root access." >&2
    echo "To install for root on purpose, set CLAUDE_INSTALL_ALLOW_SUDO=1." >&2
    exit 1
fi

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
RELEASES_DIR="$REPO_DIR/releases"

case "$(uname -s)" in
    Darwin) os="darwin" ;;
    Linux) os="linux" ;;
    *) echo "Unsupported operating system: $(uname -s)" >&2; exit 1 ;;
esac

case "$(uname -m)" in
    x86_64|amd64) arch="x64" ;;
    arm64|aarch64) arch="arm64" ;;
    *) echo "Unsupported architecture: $(uname -m)" >&2; exit 1 ;;
esac

if [ "$os" = "darwin" ] && [ "$arch" = "x64" ]; then
    if [ "$(sysctl -n sysctl.proc_translated 2>/dev/null)" = "1" ]; then
        arch="arm64"
    fi
fi

if [ "$os" = "linux" ]; then
    if [ -f /lib/libc.musl-x86_64.so.1 ] || [ -f /lib/libc.musl-aarch64.so.1 ] || ldd /bin/ls 2>&1 | grep -q musl; then
        platform="linux-${arch}-musl"
    else
        platform="linux-${arch}"
    fi
else
    platform="${os}-${arch}"
fi

if [ "$TARGET" = "latest" ] || [ "$TARGET" = "stable" ]; then
    if [ ! -f "$RELEASES_DIR/$TARGET" ]; then
        echo "No $TARGET version mirrored. Run mirror.sh first." >&2
        exit 1
    fi
    version=$(cat "$RELEASES_DIR/$TARGET")
else
    version="$TARGET"
fi

pdir="$RELEASES_DIR/$version/$platform"
if [ ! -f "$pdir/checksum" ]; then
    echo "Claude Code $version for $platform is not in this mirror." >&2
    echo "Mirrored: $(ls "$RELEASES_DIR" | grep -E '^[0-9]' | tr '\n' ' ')" >&2
    exit 1
fi
checksum=$(cat "$pdir/checksum")

checksum_matches() {
    local actual
    if [ "$os" = "darwin" ]; then
        actual=$(shasum -a 256 "$1" | cut -d' ' -f1)
    else
        actual=$(sha256sum "$1" | cut -d' ' -f1)
    fi
    [ "$actual" = "$2" ]
}

echo "Setting up Claude Code $version..."

# `claude install` always contacts downloads.claude.ai, even for a pinned
# version, so lay out the native install the same way it does: the binary at
# ~/.local/share/claude/versions/<version>, symlinked from ~/.local/bin/claude.
versions_dir="$HOME/.local/share/claude/versions"
bin_dir="$HOME/.local/bin"
mkdir -p "$versions_dir" "$bin_dir"
binary_path="$versions_dir/$version"
tmp_path="$binary_path.tmp.$$"
cat "$pdir"/claude.part-* > "$tmp_path"
if ! checksum_matches "$tmp_path" "$checksum"; then
    echo "Checksum verification failed (is the clone complete?)" >&2
    rm -f "$tmp_path"
    exit 1
fi
chmod +x "$tmp_path"
mv -f "$tmp_path" "$binary_path"
ln -sfn "$binary_path" "$bin_dir/claude"

# No network for updates, so turn off the auto-updater.
settings="$HOME/.claude/settings.json"
mkdir -p "$HOME/.claude"
if [ ! -f "$settings" ]; then
    printf '{\n  "env": {\n    "DISABLE_AUTOUPDATER": "1"\n  }\n}\n' > "$settings"
elif command -v jq >/dev/null 2>&1; then
    jq '.env.DISABLE_AUTOUPDATER = "1"' "$settings" > "$settings.tmp" && mv "$settings.tmp" "$settings"
else
    echo "Note: add \"DISABLE_AUTOUPDATER\": \"1\" under \"env\" in $settings to stop update checks." >&2
fi

"$bin_dir/claude" --version

echo ""
echo "✅ Installation complete!"
case ":$PATH:" in
    *":$bin_dir:"*) ;;
    *)
        echo ""
        echo "$bin_dir is not in your PATH. Add it with:"
        echo "    echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.bashrc && source ~/.bashrc"
        ;;
esac
