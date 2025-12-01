#!/usr/bin/env bash
# Enterprise Vibe Code - Setup Script
# Downloads pinned Hugo Extended version to ./bin/hugo
# Usage: ./scripts/setup.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BIN_DIR="$PROJECT_ROOT/bin"
HUGO_VERSION="0.152.2"

# Detect OS and architecture
detect_platform() {
    local OS

    case "$(uname -s)" in
        Darwin) OS="darwin-universal" ;;  # Hugo 0.140+ uses universal binary for macOS
        Linux)
            case "$(uname -m)" in
                x86_64|amd64) OS="linux-amd64" ;;
                arm64|aarch64) OS="linux-arm64" ;;
                *)            echo "Unsupported architecture: $(uname -m)"; exit 1 ;;
            esac
            ;;
        *)      echo "Unsupported OS: $(uname -s)"; exit 1 ;;
    esac

    echo "$OS"
}

download_hugo() {
    local PLATFORM="$1"
    local DOWNLOAD_URL="https://github.com/gohugoio/hugo/releases/download/v${HUGO_VERSION}/hugo_extended_${HUGO_VERSION}_${PLATFORM}.tar.gz"
    local TMP_DIR

    echo "Downloading Hugo Extended v${HUGO_VERSION} for ${PLATFORM}..."

    TMP_DIR=$(mktemp -d)
    trap "rm -rf $TMP_DIR" EXIT

    curl -sL "$DOWNLOAD_URL" | tar -xz -C "$TMP_DIR"

    mkdir -p "$BIN_DIR"
    mv "$TMP_DIR/hugo" "$BIN_DIR/hugo"
    chmod +x "$BIN_DIR/hugo"

    echo "Hugo installed to $BIN_DIR/hugo"
    "$BIN_DIR/hugo" version
}

main() {
    # Check if already installed with correct version
    if [[ -x "$BIN_DIR/hugo" ]]; then
        local INSTALLED_VERSION
        INSTALLED_VERSION=$("$BIN_DIR/hugo" version 2>/dev/null | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "")
        if [[ "$INSTALLED_VERSION" == "v${HUGO_VERSION}" ]]; then
            echo "Hugo v${HUGO_VERSION} already installed at $BIN_DIR/hugo"
            return 0
        fi
        echo "Upgrading Hugo from $INSTALLED_VERSION to v${HUGO_VERSION}..."
    fi

    local PLATFORM
    PLATFORM=$(detect_platform)
    download_hugo "$PLATFORM"
}

main "$@"
