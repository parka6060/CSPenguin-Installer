#!/usr/bin/env bash
# Rebuild the patched Wine unix libraries (winex11.so, win32u.so) reproducibly.
#
# Usage: patches/build-wine-unix-patches.sh [WINE_VERSION]
#   Runs an AlmaLinux 8 (glibc 2.28) container with podman (or docker), applies
#   the patches listed below to the official Wine source and builds only the
#   patched unix libraries. Results go to patches/x86_64-unix-wine<VERSION>/.
#
# An old glibc is used so the libraries run on as many distributions as the
# Kron4ek Wine builds they replace.
set -euo pipefail

WINE_VERSION="${1:-11.4}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="$SCRIPT_DIR/x86_64-unix-wine${WINE_VERSION}"
IMAGE="docker.io/library/almalinux:8"

# applied in this order
PATCHES=(
    winex11-unmanaged-owned-popups.patch   # menus open under the menu bar
    winex11-maximize-own-frame.patch       # maximize windows that draw their own frame
    win32u-clip-maximized-frame.patch      # keep the off screen frame out of the host window
)

if command -v podman >/dev/null 2>&1; then
    CTR=podman
elif command -v docker >/dev/null 2>&1; then
    CTR=docker
else
    echo "error: podman or docker is required" >&2
    exit 1
fi

mkdir -p "$OUT_DIR"

"$CTR" run --rm -i \
    -v "$SCRIPT_DIR:/patches:ro,z" \
    -v "$OUT_DIR:/out:z" \
    -e WINE_VERSION="$WINE_VERSION" \
    -e PATCHES="${PATCHES[*]}" \
    "$IMAGE" bash -euo pipefail -s << 'BUILD'
dnf -y -q install dnf-plugins-core >/dev/null
dnf config-manager --set-enabled powertools
dnf -y -q install gcc make flex bison patch xz curl \
    libX11-devel libXext-devel libXi-devel libXrandr-devel libXinerama-devel \
    libXcursor-devel libXcomposite-devel libXfixes-devel libXrender-devel \
    libXxf86vm-devel mesa-libGL-devel mesa-libEGL-devel vulkan-loader-devel \
    freetype-devel fontconfig-devel >/dev/null

major="${WINE_VERSION%%.*}"
cd /tmp
curl -fsSL "https://dl.winehq.org/wine/source/${major}.x/wine-${WINE_VERSION}.tar.xz" | tar -xJ
cd "wine-${WINE_VERSION}"
for p in $PATCHES; do
    echo "applying $p"
    patch -p1 < "/patches/$p"
done

mkdir build && cd build
../configure --enable-win64 --without-mingw --disable-tests \
    --without-wayland --without-gstreamer --without-oss --without-pcsclite \
    --without-sane --without-gphoto --without-cups --without-capi \
    --without-krb5 --without-netapi > configure.log 2>&1 \
    || { tail -40 configure.log; exit 1; }

# the replaced libraries must keep every feature of the stock build:
# pen pressure (XInput2), monitors (XRandR), GL/EGL/Vulkan, fonts (FreeType/fontconfig)
for f in HAVE_X11_EXTENSIONS_XINPUT2_H HAVE_X11_EXTENSIONS_XRANDR_H HAVE_LIBXSHAPE \
         HAVE_X11_EXTENSIONS_XSHM_H SONAME_LIBXCOMPOSITE SONAME_LIBGL SONAME_LIBEGL \
         SONAME_LIBVULKAN SONAME_LIBFREETYPE SONAME_LIBFONTCONFIG; do
    grep -q "#define $f" include/config.h || { echo "missing: $f" >&2; exit 1; }
done

make -j"$(nproc)" dlls/winex11.drv/winex11.so dlls/win32u/win32u.so > make.log 2>&1 \
    || { tail -40 make.log; exit 1; }
for lib in dlls/winex11.drv/winex11.so dlls/win32u/win32u.so; do
    strip --strip-unneeded "$lib"
    install -m 644 "$lib" "/out/$(basename "$lib")"
    echo "built: $(basename "$lib") (wine-${WINE_VERSION})"
done
BUILD

ls -la "$OUT_DIR"/winex11.so "$OUT_DIR"/win32u.so
