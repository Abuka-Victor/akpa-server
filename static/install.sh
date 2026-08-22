#!/usr/bin/env bash
#
# akpa installer
#
#   curl -fsSL https://akpa.victorabuka.com/install.sh | bash
#
# Environment overrides:
#   AKPA_VERSION      install a specific tag (default: latest)   e.g. v1.2.0
#   AKPA_INSTALL_DIR  where to put the binary (default: ~/.local/bin)
#
set -euo pipefail

REPO="Abuka-Victor/akpa-cli"   # <-- your CLI repo, NOT the server repo
BIN="akpa"
INSTALL_DIR="${AKPA_INSTALL_DIR:-$HOME/.local/bin}"
VERSION="${AKPA_VERSION:-latest}"

# ---------------------------------------------------------------- output ----
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  BOLD=$(printf '\033[1m'); DIM=$(printf '\033[2m')
  RED=$(printf '\033[31m'); GREEN=$(printf '\033[32m'); RESET=$(printf '\033[0m')
else
  BOLD=""; DIM=""; RED=""; GREEN=""; RESET=""
fi

info() { printf '%s==>%s %s\n' "$BOLD" "$RESET" "$1"; }
warn() { printf '%s==>%s %s\n' "$BOLD" "$RESET" "$1" >&2; }
die()  { printf '%serror:%s %s\n' "$RED" "$RESET" "$1" >&2; exit 1; }

need() { command -v "$1" >/dev/null 2>&1 || die "'$1' is required but not installed."; }

# ------------------------------------------------------------ preflight -----
need uname
need mktemp
need tar

if command -v curl >/dev/null 2>&1; then
  HAVE_CURL=1
  fetch() { curl -fsSL -o "$1" "$2"; }
elif command -v wget >/dev/null 2>&1; then
  HAVE_CURL=0
  fetch() { wget -q -O "$1" "$2"; }
else
  die "need curl or wget."
fi

# Print the URL that a redirect finally lands on.
resolve_redirect() {
  if [ "$HAVE_CURL" = "1" ]; then
    curl -fsSLI -o /dev/null -w '%{url_effective}' "$1"
  else
    wget --max-redirect=0 -S --spider "$1" 2>&1 \
      | awk '/^  Location:/ {print $2; exit}'
  fi
}

# --------------------------------------------------------- platform ---------
os=$(uname -s | tr '[:upper:]' '[:lower:]')
arch=$(uname -m)

case "$os" in
  linux|darwin) ;;
  msys*|mingw*|cygwin*) die "Windows: download the .zip from https://github.com/$REPO/releases" ;;
  *) die "unsupported OS: $os" ;;
esac

case "$arch" in
  x86_64|amd64)  arch="amd64" ;;
  aarch64|arm64) arch="arm64" ;;
  *) die "unsupported architecture: $arch" ;;
esac

# ---------------------------------------------------------- resolve tag -----
# Follow the /releases/latest redirect rather than hitting api.github.com —
# the API is rate-limited to 60 requests/hour per IP for unauthenticated calls,
# and a shared office or campus NAT blows through that fast.
if [ "$VERSION" = "latest" ]; then
  info "Resolving latest release…"
  location=$(resolve_redirect "https://github.com/$REPO/releases/latest" 2>/dev/null) \
    || die "could not reach GitHub. Are you online?"
  VERSION="${location##*/}"
  case "$VERSION" in
    v*) ;;
    *) die "could not determine the latest version (got '$VERSION'). Set AKPA_VERSION explicitly." ;;
  esac
fi

ARCHIVE="${BIN}_${os}_${arch}.tar.gz"
BASE_URL="https://github.com/$REPO/releases/download/$VERSION"

# ------------------------------------------------------------ download ------
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

info "Downloading ${BOLD}${BIN} ${VERSION}${RESET} (${os}/${arch})…"
fetch "$tmp/$ARCHIVE" "$BASE_URL/$ARCHIVE" \
  || die "download failed: $BASE_URL/$ARCHIVE
       That release may not ship a ${os}/${arch} build."

# ------------------------------------------------------------ verify --------
# A checksum is not optional. Without it, anyone who can sit between this
# machine and GitHub can hand you a different binary and you will run it.
if fetch "$tmp/checksums.txt" "$BASE_URL/checksums.txt" 2>/dev/null; then
  if command -v sha256sum >/dev/null 2>&1; then
    SHA="sha256sum"
  elif command -v shasum >/dev/null 2>&1; then
    SHA="shasum -a 256"
  else
    SHA=""
  fi

  if [ -n "$SHA" ]; then
    info "Verifying checksum…"
    expected=$(grep " $ARCHIVE\$" "$tmp/checksums.txt" | awk '{print $1}')
    [ -n "$expected" ] || die "no checksum listed for $ARCHIVE"
    actual=$($SHA "$tmp/$ARCHIVE" | awk '{print $1}')
    [ "$expected" = "$actual" ] || die "checksum mismatch!
       expected: $expected
       actual:   $actual
       Do not run this binary. Please report it at https://github.com/$REPO/issues"
  else
    warn "no sha256 tool found — skipping checksum verification."
  fi
else
  warn "checksums.txt unavailable — skipping verification."
fi

# ------------------------------------------------------------ install -------
tar -xzf "$tmp/$ARCHIVE" -C "$tmp"
[ -f "$tmp/$BIN" ] || die "archive did not contain a '$BIN' binary."

mkdir -p "$INSTALL_DIR"
if [ -w "$INSTALL_DIR" ]; then
  install -m 755 "$tmp/$BIN" "$INSTALL_DIR/$BIN"
else
  warn "$INSTALL_DIR is not writable, using sudo…"
  sudo install -m 755 "$tmp/$BIN" "$INSTALL_DIR/$BIN"
fi

# macOS quarantines anything downloaded by curl; clear it so Gatekeeper
# doesn't refuse to run the binary.
if [ "$os" = "darwin" ] && command -v xattr >/dev/null 2>&1; then
  xattr -d com.apple.quarantine "$INSTALL_DIR/$BIN" 2>/dev/null || true
fi

# --------------------------------------------------------------- done -------
printf '\n%s✓%s %s installed to %s%s/%s%s\n\n' \
  "$GREEN" "$RESET" "$BIN" "$BOLD" "$INSTALL_DIR" "$BIN" "$RESET"

case ":$PATH:" in
  *":$INSTALL_DIR:"*)
    printf '  Run %s%s%s in any directory to share it.\n\n' "$BOLD" "$BIN" "$RESET"
    ;;
  *)
    printf '%s  %s is not on your PATH. Add it:%s\n\n' "$BOLD" "$INSTALL_DIR" "$RESET"
    printf '    echo '"'"'export PATH="%s:$PATH"'"'"' >> ~/.bashrc\n' "$INSTALL_DIR"
    printf '    %s# or ~/.zshrc if you use zsh%s\n\n' "$DIM" "$RESET"
    ;;
esac
