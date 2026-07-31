#!/bin/sh
set -eu

REPO="skillsynchq/skl-releases"
BINARY="skl"
# Root installs (CI images, cloud environment setup scripts) default to a
# system path so the binary is on every user's PATH; user installs stay in
# the home directory. SKL_INSTALL_DIR overrides either.
if [ "$(id -u)" -eq 0 ]; then
    default_install_dir="/usr/local/bin"
else
    default_install_dir="$HOME/.local/bin"
fi
INSTALL_DIR="${SKL_INSTALL_DIR:-$default_install_dir}"

main() {
    # An existing install means this is an upgrade, not a fresh setup,
    # so skip the interactive init at the end.
    if command -v "$BINARY" > /dev/null 2>&1; then
        already_installed=1
    else
        already_installed=0
    fi

    os="$(uname -s)"
    arch="$(uname -m)"

    case "$os" in
        Linux)  target_os="unknown-linux-musl" ;;
        Darwin) target_os="apple-darwin" ;;
        MINGW*|MSYS*|CYGWIN*)
            err "On Windows, run this in PowerShell instead:
  irm https://install.skillsync.com/install.ps1 | iex" ;;
        *)      err "Unsupported OS: $os" ;;
    esac

    case "$arch" in
        x86_64|amd64)  target_arch="x86_64" ;;
        aarch64|arm64) target_arch="aarch64" ;;
        *)             err "Unsupported architecture: $arch" ;;
    esac

    target="${target_arch}-${target_os}"

    if [ -n "${VERSION:-}" ]; then
        tag="v$VERSION"
    else
        tag="$(get_latest_tag)"
        # An empty tag would otherwise cascade into a nonsense download URL.
        case "$tag" in
            v[0-9]*) ;;
            *) err "Could not determine the latest release version" ;;
        esac
    fi

    version="${tag#v}"

    tmpdir="$(mktemp -d)"
    trap 'rm -rf "$tmpdir"' EXIT

    archive_dir="skl-cli-v${version}-${target}"
    archive="${archive_dir}.tar.gz"
    fetch "https://github.com/${REPO}/releases/download/${tag}/${archive}" "$tmpdir/$archive" \
        || err "Could not download ${tag} for ${target}"
    fetch "https://github.com/${REPO}/releases/download/${tag}/${archive}.sha256" "$tmpdir/$archive.sha256" \
        || err "Could not download checksum for ${archive}"

    verify_checksum "$tmpdir/$archive" "$tmpdir/$archive.sha256"

    echo "Installing ${BINARY} (${tag}) for ${target}"
    echo "Script source: https://github.com/${REPO}/blob/main/install.sh"
    echo ""

    tar xzf "$tmpdir/$archive" -C "$tmpdir"

    mkdir -p "$INSTALL_DIR"
    mv "$tmpdir/${archive_dir}/${BINARY}" "$INSTALL_DIR/${BINARY}"
    chmod +x "$INSTALL_DIR/${BINARY}"

    echo "Installed ${BINARY} to ${INSTALL_DIR}/${BINARY}"

    if ! echo "$PATH" | tr ':' '\n' | grep -qx "$INSTALL_DIR"; then
        echo ""
        echo "Add ${INSTALL_DIR} to your PATH:"
        echo "  export PATH=\"${INSTALL_DIR}:\$PATH\""
    fi

    # The init wizard is interactive (login prompt + selections, read from
    # /dev/tty — stdin is the curl pipe). Skip it when there is no controlling
    # terminal — CI, container/cloud setup scripts — or when the caller opts
    # out with SKL_NO_INIT.
    if [ "$already_installed" -eq 0 ] && [ -z "${SKL_NO_INIT:-}" ] && sh -c ': </dev/tty' 2>/dev/null; then
        echo ""
        echo "Running '${BINARY} init'..."
        "${INSTALL_DIR}/${BINARY}" init
    fi
}

fetch() {
    if command -v curl > /dev/null 2>&1; then
        curl -sSfL "$1" -o "$2"
    elif command -v wget > /dev/null 2>&1; then
        wget -q "$1" -O "$2"
    else
        err "Neither curl nor wget found. Install one and try again."
    fi
}

# Resolve the latest release tag from the /releases/latest web redirect
# (…/releases/tag/vX.Y.Z). Deliberately avoids api.github.com: its
# unauthenticated per-IP rate limit is permanently exhausted on shared
# egress (CI runners, cloud VMs), which surfaces as a 403 and an empty tag.
get_latest_tag() {
    if command -v curl > /dev/null 2>&1; then
        curl -fsSLI -o /dev/null -w '%{url_effective}' "https://github.com/${REPO}/releases/latest" \
            | sed 's#.*/tag/##'
    elif command -v wget > /dev/null 2>&1; then
        wget -q --max-redirect=0 -S -O /dev/null "https://github.com/${REPO}/releases/latest" 2>&1 \
            | sed -n 's#.*[Ll]ocation: .*/tag/\([^ ]*\).*#\1#p' | head -1
    else
        err "Neither curl nor wget found."
    fi
}

verify_checksum() {
    # Checksum files vary: some hold a bare hash, some "hash  filename".
    # The first field is always the hash.
    expected="$(awk '{print $1}' "$2")"
    if command -v sha256sum > /dev/null 2>&1; then
        actual="$(sha256sum "$1" | awk '{print $1}')"
    elif command -v shasum > /dev/null 2>&1; then
        actual="$(shasum -a 256 "$1" | awk '{print $1}')"
    else
        echo "Warning: no sha256sum or shasum found; skipping checksum verification" >&2
        return 0
    fi
    if [ "$expected" != "$actual" ]; then
        err "Checksum mismatch for $(basename "$1")
  expected: $expected
  actual:   $actual"
    fi
}

err() {
    echo "Error: $1" >&2
    exit 1
}

main
