#!/usr/bin/env bash
# Build Loggie binary.
# Usage:
#   ./build.sh           # linux/386 (default)
#   ./build.sh 386
#   ./build.sh amd64
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

ARCH="${1:-386}"
GOOS="${GOOS:-linux}"

# Prefer locally installed Go 1.18 if present
if [[ -x "${HOME}/.local/go/bin/go" ]]; then
  export PATH="${HOME}/.local/go/bin:${PATH}"
fi

if ! command -v go >/dev/null 2>&1; then
  echo "error: go not found in PATH" >&2
  exit 1
fi

echo "go:     $(go version)"
echo "target: ${GOOS}/${ARCH}"

case "${ARCH}" in
  386|i386|i686)
    ARCH=386
    SRC_SYSROOT="${HOME}/.local/i386-sysroot"
    SYSROOT="${TMPDIR:-/tmp}/i386-sysroot"

    if [[ ! -d "${SRC_SYSROOT}/usr/lib32" ]]; then
      echo "error: i386 sysroot not found at ${SRC_SYSROOT}" >&2
      echo "Prepare it once, for example:" >&2
      echo "  mkdir -p ${SRC_SYSROOT}/debs && cd ${SRC_SYSROOT}/debs" >&2
      echo "  apt-get download libc6-dev-i386 libc6-i386 lib32gcc-11-dev lib32gcc-s1 gcc-11-multilib" >&2
      echo "  for deb in *.deb; do dpkg-deb -x \"\$deb\" ${SRC_SYSROOT}; done" >&2
      exit 1
    fi

    # Writable copy: linker scripts need absolute paths under this sysroot
    rm -rf "${SYSROOT}"
    mkdir -p "${SYSROOT}"
    cp -a "${SRC_SYSROOT}/lib32" "${SRC_SYSROOT}/lib" "${SRC_SYSROOT}/usr" "${SYSROOT}/"
    rm -rf "${SYSROOT}/usr/share"

    ln -sfn "${SYSROOT}/lib32/ld-linux.so.2" "${SYSROOT}/lib/ld-linux.so.2"
    cat > "${SYSROOT}/usr/lib32/libc.so" <<EOF
/* GNU ld script */
OUTPUT_FORMAT(elf32-i386)
GROUP ( ${SYSROOT}/lib32/libc.so.6 ${SYSROOT}/usr/lib32/libc_nonshared.a  AS_NEEDED ( ${SYSROOT}/lib32/ld-linux.so.2 ) )
EOF

    find "${SYSROOT}/usr/lib32" -maxdepth 1 -type l | while read -r link; do
      base="$(basename "$(readlink "${link}")")"
      if [[ -e "${SYSROOT}/lib32/${base}" ]]; then
        ln -sfn "${SYSROOT}/lib32/${base}" "${link}"
      fi
    done
    ln -sfn "${SYSROOT}/lib32/libpthread.so.0" "${SYSROOT}/usr/lib32/libpthread.so"
    ln -sfn "${SYSROOT}/lib32/libdl.so.2" "${SYSROOT}/usr/lib32/libdl.so"

    export CGO_ENABLED=1
    export CC=gcc
    export CGO_CFLAGS="-m32 -I${SYSROOT}/usr/include/x86_64-linux-gnu -I/usr/include/x86_64-linux-gnu"
    export CGO_LDFLAGS="-m32 -B${SYSROOT}/usr/lib/gcc/x86_64-linux-gnu/11/32 -B${SYSROOT}/usr/lib32 -L${SYSROOT}/usr/lib32 -L${SYSROOT}/usr/lib/gcc/x86_64-linux-gnu/11/32"
    ;;
  amd64|x86_64)
    ARCH=amd64
    export CGO_ENABLED=1
    ;;
  *)
    echo "error: unsupported arch '${ARCH}' (use 386 or amd64)" >&2
    exit 1
    ;;
esac

OUT_DIR="${ROOT_DIR}/build"
mkdir -p "${OUT_DIR}"

make build GOOS="${GOOS}" GOARCH="${ARCH}"
mv -f "${ROOT_DIR}/loggie" "${OUT_DIR}/loggie"

echo
file "${OUT_DIR}/loggie"
ls -lh "${OUT_DIR}/loggie"
