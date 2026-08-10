#!/usr/bin/env bash
set -Eeuo pipefail

VERBOSE=0
SKIP_WINETRICKS=0
DRY_RUN=0
UPDATE_WINE=0
UPDATE_ONLY=0
_ESYNC_RESTART=0
for arg in "$@"; do
    [[ "$arg" == "--verbose"         || "$arg" == "-v" ]] && VERBOSE=1
    [[ "$arg" == "--skip-winetricks" || "$arg" == "-s" ]] && SKIP_WINETRICKS=1
    [[ "$arg" == "--dry-run"         || "$arg" == "-n" ]] && DRY_RUN=1
    [[ "$arg" == "--update-wine"     || "$arg" == "-w" ]] && UPDATE_WINE=1
    [[ "$arg" == "--update"          || "$arg" == "-u" ]] && UPDATE_ONLY=1
done

DOWNLOAD_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/csp-install"

# colors
_setup_colors() {
    if [[ -t 1 ]] && [[ "${TERM:-dumb}" != "dumb" ]] \
       && command -v tput &>/dev/null \
       && [[ "$(tput colors 2>/dev/null || echo 0)" -ge 256 ]]; then
        TEAL='\033[38;5;30m'
        AMBER='\033[38;5;179m'
        YELLOW='\033[38;5;178m'
        RED='\033[38;5;160m'
        BOLD='\033[1m'
        DIM='\033[2m'
        RESET='\033[0m'
    else
        TEAL='' AMBER='' YELLOW='' RED='' BOLD='' DIM='' RESET=''
    fi
}
_setup_colors

# formatting
TOTAL_STEPS=7
STEP=0

# _log writes a plain-text (no ANSI codes) trail of what happened to
# LOG_FILE, independent of what run() captures from external commands.
_log() { [[ -n "${LOG_FILE:-}" ]] && echo "$1" >> "$LOG_FILE" 2>/dev/null; }

step() {
    STEP=$((STEP + 1))
    echo ""
    echo -e "  ${TEAL}│${RESET} ${TEAL}${BOLD}[${STEP}/${TOTAL_STEPS}] $1${RESET}"
    _log "[STEP ${STEP}/${TOTAL_STEPS}] $1"
}

ok()   { echo -e "  ${TEAL}│${RESET} ${AMBER}+${RESET} $1"; _log "OK: $1"; }
warn() { echo -e "  ${TEAL}│${RESET} ${YELLOW}!${RESET} ${YELLOW}$1${RESET}"; _log "WARN: $1"; }
info() { echo -e "  ${TEAL}│${RESET} ${DIM}- $1${RESET}"; _log "INFO: $1"; }
gap()  { echo -e "  ${TEAL}│${RESET}"; }
msg()  { echo -e "  ${TEAL}│${RESET} $1"; _log "$1"; }

die() {
    echo ""
    echo -e "  ${RED}✗ ERROR:${RESET} $1"
    [[ -n "${LOG_FILE:-}" ]] && echo -e "  ${DIM}log: $LOG_FILE${RESET}"
    echo -e "  ${DIM}https://github.com/parka6060/CSPenguin-Installer/issues${RESET}"
    _log "ERROR: $1"
    exit 1
}

# catch and log command failures
_on_error() {
    local _exit=$? _line="$1" _cmd="$2"
    _log "UNEXPECTED ERROR at line ${_line} (exit ${_exit}): ${_cmd}"
    echo ""
    echo -e "  ${RED}✗ ERROR:${RESET} unexpected failure at line ${_line}: ${_cmd} (exit ${_exit})"
    [[ -n "${LOG_FILE:-}" ]] && echo -e "  ${DIM}log: $LOG_FILE${RESET}"
    echo -e "  ${DIM}https://github.com/parka6060/CSPenguin-Installer/issues${RESET}"
}

# cleanup
_install_ok=0
cleanup() {
    [[ $DRY_RUN -eq 1 ]] && return
    rm -f "$DOWNLOAD_DIR"/*.part 2>/dev/null
    [[ $_install_ok -eq 0 ]] && [[ $UPDATE_ONLY -eq 0 ]] && wineserver -k 2>/dev/null || true
}
trap cleanup EXIT

# paths
_candidate="$(cd "$(dirname "${BASH_SOURCE[0]:-/}")" 2>/dev/null && pwd)"
if [[ -d "$_candidate/patches" ]]; then
    SCRIPT_DIR="$_candidate"
else
    SCRIPT_DIR="$DOWNLOAD_DIR"
fi

WINEPREFIX="${WINEPREFIX:-$HOME/.wine-csp}"
WINEARCH=win64

WINE_VERSION="11.14"
WINE_URL="https://github.com/Kron4ek/Wine-Builds/releases/download/${WINE_VERSION}/wine-${WINE_VERSION}-amd64.tar.xz"
FREETYPE_VERSION="2.13.2"
FREETYPE_URL="https://archive.archlinux.org/packages/f/freetype2/freetype2-${FREETYPE_VERSION}-1-x86_64.pkg.tar.zst"
FREETYPE32_URL="https://archive.archlinux.org/packages/l/lib32-freetype2/lib32-freetype2-${FREETYPE_VERSION}-1-x86_64.pkg.tar.zst"
WEBVIEW2_URL="https://msedge.sf.dl.delivery.mp.microsoft.com/filestreamingservice/files/76eb3dc4-7851-45b7-a392-460523b0e2bb/MicrosoftEdgeWebView2RuntimeInstallerX64.exe"
WINETRICKS_URL="https://raw.githubusercontent.com/Winetricks/winetricks/master/src/winetricks"
GECKO_VERSION="2.47.4"
GECKO_URL="https://dl.winehq.org/wine/wine-gecko/${GECKO_VERSION}/wine-gecko-${GECKO_VERSION}-x86_64.msi"
GECKO_MSI="$DOWNLOAD_DIR/wine-gecko-${GECKO_VERSION}-x86_64.msi"
GECKO_SHA="e590b7d988a32d6aa4cf1d8aa3aa3d33766fdd4cf4c89c2dcc2095ecb28d066f"
LAUNCHER_DIR="$HOME/.local/share/cspenguin"
WINE_DIR="$LAUNCHER_DIR/wine-${WINE_VERSION}"
WINE_BIN="$WINE_DIR/bin/wine"
WINESERVER_BIN="$WINE_DIR/bin/wineserver"
FREETYPE_DIR="$WINE_DIR/lib/freetype2-${FREETYPE_VERSION}"
WINETRICKS_BIN="$LAUNCHER_DIR/winetricks"
LAUNCH_SCRIPT="$LAUNCHER_DIR/csp-launch.sh"
LAUNCHER_STUDIO="$LAUNCHER_DIR/clipstudio-launch.sh"
CSP_INSTALL_PATH="$WINEPREFIX/drive_c/Program Files/CELSYS/CLIP STUDIO 1.5/CLIP STUDIO PAINT/CLIPStudioPaint.exe"
STUDIO_EXE="$WINEPREFIX/drive_c/Program Files/CELSYS/CLIP STUDIO 1.5/CLIP STUDIO/CLIPStudio.exe"
SYS32="$WINEPREFIX/drive_c/windows/system32"
LOG_FILE="${DOWNLOAD_DIR}/csp-install.log"

# helpers
run() {
    [[ $DRY_RUN -eq 1 ]] && return 0
    if [[ $VERBOSE -eq 1 ]]; then
        "$@" 2>&1 | tee -a "$LOG_FILE"
    else
        "$@" >> "$LOG_FILE" 2>&1
    fi
}

GH_RAW="https://raw.githubusercontent.com/parka6060/CSPenguin-Installer/main"

fetch_asset() {
    local rel="$1" dest="$2"
    if [[ -f "$dest" && -s "$dest" ]]; then
        return 0
    fi
    [[ $DRY_RUN -eq 1 ]] && return 0
    mkdir -p "$(dirname "$dest")"
    info "fetching $rel"
    local tmp="${dest}.part"
    wget -q -O "$tmp" "$GH_RAW/$rel" || { rm -f "$tmp"; die "failed to download $rel"; }
    mv "$tmp" "$dest"
}

ensure_asset() {
    local rel="$1" dest="$2"
    if [[ ! -f "$dest" ]]; then
        fetch_asset "$rel" "$dest"
    fi
}

# winetricks' cjkfonts pulls in a 112MB/28-face font (Source Han Sans >:C) that adds ~60s to every CSP startup. Swap it for something smaller to fix boot time. use --update to update your prefix.
install_cjk_font_fix() {
    local font_file="wqy-microhei.ttc"
    local font_name="WenQuanYi Micro Hei"

    if [[ $DRY_RUN -eq 1 ]]; then
        ok "CJK font: $font_name (dry run)"
        return
    fi

    local font_src="$SCRIPT_DIR/patches/fonts/$font_file"
    ensure_asset "patches/fonts/$font_file" "$font_src"
    if [[ ! -f "$font_src" ]]; then
        warn "CJK font asset missing, skipping"
        return
    fi

    local fonts_dir="$WINEPREFIX/drive_c/windows/Fonts"
    mkdir -p "$fonts_dir"
    cp "$font_src" "$fonts_dir/$font_file"
    rm -f "$fonts_dir/sourcehansans.ttc"

    local temp_dir="$WINEPREFIX/drive_c/windows/Temp"
    mkdir -p "$temp_dir"
    local reg_unix="$temp_dir/cjk-font.reg"
    cat > "$reg_unix" << REGEOF
REGEDIT4

[HKEY_LOCAL_MACHINE\Software\Microsoft\Windows NT\CurrentVersion\Fonts]
"Source Han Sans SC ExtraLight (TrueType)"=-
"Source Han Sans SC Light (TrueType)"=-
"Source Han Sans SC Normal (TrueType)"=-
"Source Han Sans SC (TrueType)"=-
"Source Han Sans SC Medium (TrueType)"=-
"Source Han Sans SC Bold (TrueType)"=-
"Source Han Sans SC Heavy (TrueType)"=-
"Source Han Sans TC ExtraLight (TrueType)"=-
"Source Han Sans TC Light (TrueType)"=-
"Source Han Sans TC Normal (TrueType)"=-
"Source Han Sans TC (TrueType)"=-
"Source Han Sans TC Medium (TrueType)"=-
"Source Han Sans TC Bold (TrueType)"=-
"Source Han Sans TC Heavy (TrueType)"=-
"Source Han Sans ExtraLight (TrueType)"=-
"Source Han Sans Light (TrueType)"=-
"Source Han Sans Normal (TrueType)"=-
"Source Han Sans (TrueType)"=-
"Source Han Sans Medium (TrueType)"=-
"Source Han Sans Bold (TrueType)"=-
"Source Han Sans Heavy (TrueType)"=-
"Source Han Sans K ExtraLight (TrueType)"=-
"Source Han Sans K Light (TrueType)"=-
"Source Han Sans K Normal (TrueType)"=-
"Source Han Sans K (TrueType)"=-
"Source Han Sans K Medium (TrueType)"=-
"Source Han Sans K Bold (TrueType)"=-
"Source Han Sans K Heavy (TrueType)"=-
"$font_name (TrueType)"="$font_file"

[HKEY_LOCAL_MACHINE\Software\Microsoft\Windows\CurrentVersion\Fonts]
"Source Han Sans SC ExtraLight (TrueType)"=-
"Source Han Sans SC Light (TrueType)"=-
"Source Han Sans SC Normal (TrueType)"=-
"Source Han Sans SC (TrueType)"=-
"Source Han Sans SC Medium (TrueType)"=-
"Source Han Sans SC Bold (TrueType)"=-
"Source Han Sans SC Heavy (TrueType)"=-
"Source Han Sans TC ExtraLight (TrueType)"=-
"Source Han Sans TC Light (TrueType)"=-
"Source Han Sans TC Normal (TrueType)"=-
"Source Han Sans TC (TrueType)"=-
"Source Han Sans TC Medium (TrueType)"=-
"Source Han Sans TC Bold (TrueType)"=-
"Source Han Sans TC Heavy (TrueType)"=-
"Source Han Sans ExtraLight (TrueType)"=-
"Source Han Sans Light (TrueType)"=-
"Source Han Sans Normal (TrueType)"=-
"Source Han Sans (TrueType)"=-
"Source Han Sans Medium (TrueType)"=-
"Source Han Sans Bold (TrueType)"=-
"Source Han Sans Heavy (TrueType)"=-
"Source Han Sans K ExtraLight (TrueType)"=-
"Source Han Sans K Light (TrueType)"=-
"Source Han Sans K Normal (TrueType)"=-
"Source Han Sans K (TrueType)"=-
"Source Han Sans K Medium (TrueType)"=-
"Source Han Sans K Bold (TrueType)"=-
"Source Han Sans K Heavy (TrueType)"=-
"$font_name (TrueType)"="$font_file"

[HKEY_CURRENT_USER\Software\Wine\Fonts\Replacements]
"Dengxian"="$font_name"
"FangSong"="$font_name"
"KaiTi"="$font_name"
"Microsoft YaHei"="$font_name"
"Microsoft YaHei UI"="$font_name"
"NSimSun"="$font_name"
"SimHei"="$font_name"
"SimKai"="$font_name"
"SimSun"="$font_name"
"SimSun-ExtB"="$font_name"
"DFKai-SB"="$font_name"
"Microsoft JhengHei"="$font_name"
"Microsoft JhengHei UI"="$font_name"
"MingLiU"="$font_name"
"PMingLiU"="$font_name"
"MingLiU-ExtB"="$font_name"
"PMingLiU-ExtB"="$font_name"
"Meiryo"="$font_name"
"Meiryo UI"="$font_name"
"MS Gothic"="$font_name"
"MS PGothic"="$font_name"
"MS Mincho"="$font_name"
"MS PMincho"="$font_name"
"MS UI Gothic"="$font_name"
"Yu Gothic"="$font_name"
"Yu Gothic UI"="$font_name"
"Yu Mincho"="$font_name"
"Batang"="$font_name"
"BatangChe"="$font_name"
"Dotum"="$font_name"
"DotumChe"="$font_name"
"Gulim"="$font_name"
"GulimChe"="$font_name"
"Gungsuh"="$font_name"
"GungsuhChe"="$font_name"
"Malgun Gothic"="$font_name"

[HKEY_CURRENT_USER\Software\Wine\X11 Driver]
"ClientSideAntiAliasWithCore"="Y"
"ClientSideAntiAliasWithRender"="Y"
"ClientSideWithRender"="Y"
REGEOF

    run wine regedit /S 'C:\windows\Temp\cjk-font.reg'
    rm -f "$reg_unix"
    ok "CJK font: $font_name (was Source Han Sans, ~60s faster CSP startup)"
}

# ============================================================
# install Wine Gecko (the MSHTML/IE engine) into the prefix
# ============================================================
_install_gecko() {
    if [[ -d "$WINEPREFIX/drive_c/windows/system32/gecko/$GECKO_VERSION/wine_gecko" ]]; then
        ok "Wine Gecko ${GECKO_VERSION} (already installed)"
        return
    fi
    if [[ $DRY_RUN -eq 1 ]]; then
        ok "Wine Gecko ${GECKO_VERSION} (dry run)"
        return
    fi
    download_progress "Wine Gecko ${GECKO_VERSION}" "$GECKO_URL" "$GECKO_MSI"
    local _sum
    _sum=$(sha256sum "$GECKO_MSI" | cut -d' ' -f1)
    if [[ "$_sum" != "$GECKO_SHA" ]]; then
        die "Wine Gecko checksum mismatch (got $_sum)"
    fi
    wait_for "installing Wine Gecko ${GECKO_VERSION}" env WINEDEBUG=-all wine msiexec /i "$GECKO_MSI" /qn
    [[ -d "$WINEPREFIX/drive_c/windows/system32/gecko/$GECKO_VERSION/wine_gecko" ]] \
        || warn "Wine Gecko ${GECKO_VERSION} did not fully install"
}

wait_for() {
    local msg="$1"; shift
    if [[ $DRY_RUN -eq 1 ]]; then
        ok "$msg (dry run)"
        return
    fi
    if [[ $VERBOSE -eq 1 ]]; then
        info "$msg"
        run "$@" || die "$msg failed"
        ok "$msg"
        return
    fi
    local -a frames=('|' '/' '-' '\')
    local i=0
    run "$@" &
    local pid=$!
    while kill -0 "$pid" 2>/dev/null; do
        printf "\r  ${TEAL}│${RESET} ${TEAL}%s${RESET} %s  " "${frames[$((i % 4))]}" "$msg"
        sleep 0.2
        i=$((i + 1))
    done
    wait "$pid" || die "$msg failed"
    printf "\r"
    ok "$msg"
}

download_progress() {
    local name="$1" url="$2" dest="$3"
    if [[ -f "$dest" && -s "$dest" ]]; then
        ok "$name (cached)"
        return
    fi
    if [[ $DRY_RUN -eq 1 ]]; then
        ok "$name (dry run)"
        return
    fi
    local total
    total=$(curl -fsSIL "$url" \
        | awk 'tolower($1)=="content-length:" {print $2}' \
        | tail -1 | tr -d '\r' || true)
    local tmp="${dest}.part"
    if [[ -z "$total" ]] || ! [[ "$total" =~ ^[0-9]+$ ]] || [[ "$total" -eq 0 ]]; then
        wait_for "$name" wget -q --timeout=30 --tries=3 -O "$tmp" "$url"
        mv "$tmp" "$dest"
        return
    fi
    info "$name"
    wget -q --timeout=30 --tries=3 -O "$tmp" "$url" &
    local pid=$!
    local bw=30 current=0 pct=0 filled=0 empty=0
    while kill -0 "$pid" 2>/dev/null; do
        [[ -f "$tmp" ]] && current=$(stat -c%s "$tmp" 2>/dev/null || echo 0)
        pct=$((current * 100 / total))
        [[ $pct -gt 100 ]] && pct=100
        filled=$((pct * bw / 100))
        empty=$((bw - filled))
        printf "\r  ${TEAL}│${RESET}   ${AMBER}%s${RESET}${DIM}%s${RESET} %3d%%  %dMB/%dMB  " \
            "$(printf '█%.0s' $(seq 1 $filled) 2>/dev/null)" \
            "$(printf '░%.0s' $(seq 1 $empty) 2>/dev/null)" \
            "$pct" "$((current / 1048576))" "$((total / 1048576))"
        sleep 0.3
    done
    wait "$pid" || die "download failed: $name"
    printf "\r  ${TEAL}│${RESET}   ${AMBER}%s${RESET} 100%%  %dMB/%dMB  \n" \
        "$(printf '█%.0s' $(seq 1 $bw))" "$((total / 1048576))" "$((total / 1048576))"
    mv "$tmp" "$dest"
    ok "$name"
}

_detect_pm() {
    command -v pacman >/dev/null 2>&1 && echo "pacman" && return
    command -v dnf    >/dev/null 2>&1 && echo "dnf"    && return
    command -v apt    >/dev/null 2>&1 && echo "apt"    && return
    echo "unknown"
}

# single install abstraction for the detected package manager
_pm_install() {
    case "$(_detect_pm)" in
        pacman) sudo pacman -S --needed --noconfirm "$@" ;;
        dnf)    sudo dnf install -y "$@" ;;
        apt)    sudo apt install -y "$@" ;;
        *)      die "unsupported distro, install \"$*\" manually" ;;
    esac
}

_gst_ok() { command -v gst-inspect-1.0 >/dev/null 2>&1 && gst-inspect-1.0 h264parse >/dev/null 2>&1; }

_install_deps_pacman() {
    local pkgs=()
    command -v wget    >/dev/null 2>&1 || pkgs+=(wget)
    command -v curl    >/dev/null 2>&1 || pkgs+=(curl)
    command -v wmctrl  >/dev/null 2>&1 || pkgs+=(wmctrl)
    command -v xprop   >/dev/null 2>&1 || pkgs+=(xorg-xprop)
    command -v unzstd  >/dev/null 2>&1 || pkgs+=(zstd)
    command -v file    >/dev/null 2>&1 || pkgs+=(file)
    _gst_ok          || pkgs+=(gst-plugins-bad gst-plugins-good)
    [[ ${#pkgs[@]} -gt 0 ]] && _pm_install "${pkgs[@]}"
}

_install_deps_dnf() {
    local pkgs=(freetype.i686)
    command -v wget    >/dev/null 2>&1 || pkgs+=(wget)
    command -v curl    >/dev/null 2>&1 || pkgs+=(curl)
    command -v wmctrl  >/dev/null 2>&1 || pkgs+=(wmctrl)
    command -v xprop   >/dev/null 2>&1 || pkgs+=(xprop)
    command -v unzstd  >/dev/null 2>&1 || pkgs+=(zstd)
    command -v file    >/dev/null 2>&1 || pkgs+=(file)
    _gst_ok          || pkgs+=(gstreamer1-tools gstreamer1-plugins-bad-free gstreamer1-plugins-good)
    _pm_install "${pkgs[@]}"
}

_install_deps_apt() {
    local pkgs=(dirmngr ca-certificates)
    command -v wget    >/dev/null 2>&1 || pkgs+=(wget)
    command -v curl    >/dev/null 2>&1 || pkgs+=(curl)
    command -v wmctrl  >/dev/null 2>&1 || pkgs+=(wmctrl)
    command -v xprop   >/dev/null 2>&1 || pkgs+=(x11-utils)
    command -v unzstd  >/dev/null 2>&1 || pkgs+=(zstd)
    command -v file    >/dev/null 2>&1 || pkgs+=(file)
    _gst_ok          || pkgs+=(gstreamer1.0-plugins-bad gstreamer1.0-plugins-good)
    _pm_install "${pkgs[@]}"
}

# log file
if [[ $DRY_RUN -eq 1 ]]; then
    LOG_FILE="/dev/null"
else
    mkdir -p "$DOWNLOAD_DIR"
    : > "$LOG_FILE"
    echo "CSPenguin-Installer > $(date)" >> "$LOG_FILE"
fi

# catch anything set -e would otherwise abort on without a friendly message
trap '_on_error "$LINENO" "$BASH_COMMAND"' ERR

# detect Wine version of existing install is actually using
_detect_installed_wine() {
    [[ -f "$LAUNCH_SCRIPT" ]] || return 1
    local _v
    _v=$(grep -oP 'wine-\K[0-9]+\.[0-9]+' "$LAUNCH_SCRIPT" 2>/dev/null | head -1)
    [[ -n "$_v" ]] || return 1
    echo "$_v"
}

# compare two Wine version strings (e.g. "11.4" vs "11.12")
# echoes 1 if $1 > $2, -1 if $1 < $2, 0 if equal
_wine_version_cmp() {
    [[ "$1" == "$2" ]] && { echo 0; return; }
    local _newest
    _newest=$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -1)
    [[ "$_newest" == "$1" ]] && echo 1 || echo -1
}

# ============================================================
# detect latest Wine version from Kron4ek (excluding Proton)
# ============================================================
_latest_kron4ek_wine() {
    local _tags
    _tags=$(curl -s "https://api.github.com/repos/Kron4ek/Wine-Builds/releases" 2>/dev/null \
            | grep -oP '"tag_name":\s*"\K[^"]+' | grep -v '^proton' | head -20)
    if [[ -n "$_tags" ]]; then
        echo "$_tags" | head -1
    fi
}

# ============================================================
# find the closest available patch version numerically
# ============================================================
_closest_patch_version() {
    local _target="${1//./}"
    local _best="" _best_dist=999999
    for _pd in "$SCRIPT_DIR"/patches/x86_64-windows-wine*; do
        [[ -d "$_pd" ]] || continue
        [[ -f "$_pd/mfplat.dll" ]] || continue
        _ver="${_pd##*wine}"
        _ver="${_ver//./}"
        _dist=$(( _target > _ver ? _target - _ver : _ver - _target ))
        if (( _dist < _best_dist )); then
            _best="$_pd"
            _best_dist=$_dist
        fi
    done
    echo "$_best"
}

# ============================================================
# fetch a patch file from local or remote
# ============================================================
_try_fetch_patch() {
    local _dir="$1" _rel="$2" _file="$3"
    [[ -f "$_dir/$_file" ]] && return 0
    mkdir -p "$_dir"
    local _tmp="${_dir}/${_file}.part"
    if wget -q -O "$_tmp" "$GH_RAW/$_rel/$_file" 2>/dev/null; then
        mv "$_tmp" "$_dir/$_file"
        return 0
    fi
    rm -f "$_tmp" 2>/dev/null
    return 1
}

# ============================================================
# extract Wine tarball to LAUNCHER_DIR
# ============================================================
_extract_wine() {
    local _wine_tar="$1"
    info "extracting Wine ${WINE_VERSION}..."
    rm -rf "$WINE_DIR"
    mkdir -p "$LAUNCHER_DIR"
    tar -xf "$_wine_tar" -C "$LAUNCHER_DIR"
    for _d in "$LAUNCHER_DIR/wine-${WINE_VERSION}-staging-amd64" \
               "$LAUNCHER_DIR/wine-${WINE_VERSION}-amd64" \
               "$LAUNCHER_DIR/wine-${WINE_VERSION}-plain-amd64"; do
        [[ -d "$_d" ]] && mv "$_d" "$WINE_DIR" && break
    done
    [[ -x "$WINE_BIN" ]] || die "Wine ${WINE_VERSION} extraction failed"
    ok "Wine ${WINE_VERSION} extracted"
}

# ============================================================
# bundle FreeType into WINE_DIR
# ============================================================
# map a missing freetype dependency (.so name) to the distro packages that
# provide it (native + 32-bit variant)
_freetype_dep_pkgs() {
    local lib="$1" pm="$2"
    case "$pm" in
        pacman)
            case "$lib" in
                libz.so*)        echo "zlib lib32-zlib" ;;
                libbz2.so*)      echo "bzip2 lib32-bzip2" ;;
                libpng16.so*)    echo "libpng lib32-libpng" ;;
                libharfbuzz.so*) echo "harfbuzz lib32-harfbuzz" ;;
                libbrotli*.so*)  echo "brotli lib32-brotli" ;;
            esac ;;
        dnf)
            case "$lib" in
                libz.so*)        echo "zlib zlib.i686" ;;
                libbz2.so*)      echo "bzip2-libs bzip2-libs.i686" ;;
                libpng16.so*)    echo "libpng libpng.i686" ;;
                libharfbuzz.so*) echo "harfbuzz harfbuzz.i686" ;;
                libbrotli*.so*)  echo "brotli brotli.i686" ;;
            esac ;;
        apt)
            case "$lib" in
                libz.so*)        echo "zlib1g zlib1g:i386" ;;
                libbz2.so*)      echo "libbz2-1.0 libbz2-1.0:i386" ;;
                libpng16.so*)    echo "libpng16-16 libpng16-16:i386" ;;
                libharfbuzz.so*) echo "libharfbuzz0b libharfbuzz0b:i386" ;;
                libbrotli*.so*)  echo "libbrotli1 libbrotli1:i386" ;;
            esac ;;
    esac
}

# unique list of the shared libraries the bundled FreeType cannot resolve
_freetype_missing() {
    ldd "$FREETYPE_DIR/lib64/libfreetype.so.6" "$FREETYPE_DIR/lib32/libfreetype.so.6" 2>/dev/null \
        | grep "not found" \
        | sed 's/^[[:space:]]*\([^ ]*\) => not found.*/\1/' \
        | sort -u \
        || true
}

# copy-pasteable fix command for the given libs
_freetype_fix_hint() {
    local pm="$1"; shift
    local prefix pkgs=() lib _pair _bits
    case "$pm" in
        pacman) prefix="sudo pacman -S" ;;
        dnf)    prefix="sudo dnf install" ;;
        apt)    prefix="sudo dpkg --add-architecture i386 && sudo apt update && sudo apt install" ;;
        *)      return ;;
    esac
    for lib in "$@"; do
        _pair=$(_freetype_dep_pkgs "$lib" "$pm")
        [[ -n "$_pair" ]] || continue
        read -r -a _bits <<< "$_pair"
        [[ ${#_bits[@]} -ge 2 ]] || continue
        pkgs+=("${_bits[1]}")
    done
    [[ ${#pkgs[@]} -gt 0 ]] || return
    printf 'install the 32-bit libraries, for example:\n    %s %s\n' "$prefix" "${pkgs[*]}"
}

# some distros ship a library under a different soname than the Arch-built
# FreeType expects (e.g. Fedora ships libbz2.so.1, FreeType wants libbz2.so.1.0).
# if the real file exists on disk, link the expected name to it.
_freetype_fix_symlink() {
    local lib="$1"
    local base="${lib%.so*}.so"
    local real target
    while IFS= read -r real; do
        [[ -f "$real" ]] || continue
        target="${real%/*}/$lib"
        [[ -e "$target" ]] && continue
        info "linking ${target##*/} -> $(basename "$real")"
        sudo ln -s "$(basename "$real")" "$target" 2>/dev/null || true
    done < <(find /usr/lib /usr/lib32 /usr/lib64 /lib /lib32 /lib64 -maxdepth 1 -name "$base.*" -type f 2>/dev/null)
}

# ensure the bundled FreeType can resolve its dependencies, installing the
# missing 32-bit libraries when possible; dies with a fix hint if not
_freetype_resolve() {
    local _missing _pkgs=() _lib _pair _pm _hint
    _missing=$(_freetype_missing)
    [[ -n "$_missing" ]] || return 0
    if [[ $DRY_RUN -eq 1 ]]; then
        info "FreeType needs extra libraries (dry run, not installing): $(tr '\n' ' ' <<< "$_missing")"
        return 0
    fi
    _pm="$(_detect_pm)"
    [[ "$_pm" != "unknown" ]] || die "bundled FreeType is missing dependencies: $(tr '\n' ' ' <<< "$_missing")
install the missing 32-bit libraries for your distribution, then re-run the installer"
    while IFS= read -r _lib; do
        read -r -a _pair <<< "$(_freetype_dep_pkgs "$_lib" "$_pm")"
        _pkgs+=("${_pair[@]}")
    done <<< "$_missing"
    if [[ ${#_pkgs[@]} -gt 0 ]]; then
        info "installing FreeType dependencies: ${_pkgs[*]}"
        if [[ "$_pm" == "apt" ]]; then
            sudo dpkg --add-architecture i386 2>/dev/null || true
            sudo apt update 2>/dev/null || true
        fi
        _pm_install "${_pkgs[@]}" || true
    fi
    _missing=$(_freetype_missing)
    if [[ -n "$_missing" ]]; then
        while IFS= read -r _lib; do
            _freetype_fix_symlink "$_lib"
        done <<< "$_missing"
        _missing=$(_freetype_missing)
    fi
    if [[ -n "$_missing" ]]; then
        _hint=$(_freetype_fix_hint "$_pm" $_missing)
        if [[ -n "$_hint" ]]; then
            die "bundled FreeType is still missing dependencies: $(tr '\n' ' ' <<< "$_missing")

$_hint
then re-run the installer"
        else
            die "bundled FreeType is still missing dependencies: $(tr '\n' ' ' <<< "$_missing")
install the missing 32-bit libraries for your distribution, then re-run the installer"
        fi
    fi
}

_bundle_freetype() {
    local _freetype_tar="$DOWNLOAD_DIR/freetype2-${FREETYPE_VERSION}-1-x86_64.pkg.tar.zst"
    local _freetype32_tar="$DOWNLOAD_DIR/lib32-freetype2-${FREETYPE_VERSION}-1-x86_64.pkg.tar.zst"
    if [[ ! -f "$_freetype_tar" ]]; then
        download_progress "FreeType ${FREETYPE_VERSION}" "$FREETYPE_URL" "$_freetype_tar"
    else
        ok "FreeType ${FREETYPE_VERSION} (cached)"
    fi
    if [[ ! -f "$_freetype32_tar" ]]; then
        download_progress "FreeType ${FREETYPE_VERSION} (32-bit)" "$FREETYPE32_URL" "$_freetype32_tar"
    else
        ok "FreeType ${FREETYPE_VERSION} 32-bit (cached)"
    fi
    info "bundling FreeType ${FREETYPE_VERSION} (32-bit + 64-bit)..."
    rm -rf "$FREETYPE_DIR"
    mkdir -p "$FREETYPE_DIR/lib64" "$FREETYPE_DIR/lib32"
    mkdir -p /tmp/freetype-extract
    unzstd -c "$_freetype_tar" | tar -xf - -C /tmp/freetype-extract
    cp /tmp/freetype-extract/usr/lib/libfreetype.so* "$FREETYPE_DIR/lib64/"
    rm -rf /tmp/freetype-extract/usr/lib
    unzstd -c "$_freetype32_tar" | tar -xf - -C /tmp/freetype-extract
    cp /tmp/freetype-extract/usr/lib32/libfreetype.so* "$FREETYPE_DIR/lib32/"
    rm -rf /tmp/freetype-extract
    _freetype_resolve
    ok "FreeType ${FREETYPE_VERSION} bundled"
}

# ============================================================
# write both launcher scripts (PAINT + STUDIO)
# ============================================================
_write_launchers() {
    cat > "$LAUNCH_SCRIPT" << LAUNCHEOF
#!/usr/bin/env bash
export LD_LIBRARY_PATH="$FREETYPE_DIR/lib64:$FREETYPE_DIR/lib32:\${LD_LIBRARY_PATH:-}"
export PATH="$WINE_DIR/bin:\$PATH"
export WINESERVER="$WINESERVER_BIN"
export WINEPREFIX="$WINEPREFIX"
export WINEDEBUG=-all
export WINEESYNC=1
export WINEFSYNC=1
export WINEDLLPATH="$LAUNCHER_DIR:\${WINEDLLPATH:-}"
export DXVK_ASYNC=1
export DXVK_STATE_CACHE=1
export DXVK_CONFIG_FILE="$WINEPREFIX/dxvk.conf"
export DXVK_STATE_CACHE_PATH="$WINEPREFIX"
export mesa_glthread=true
export __GL_SHADER_DISK_CACHE=1
export __GL_SHADER_DISK_CACHE_PATH="$WINEPREFIX"
export RADV_PERFTEST=gpl
export WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS="--no-sandbox --disable-gpu-compositing --disable-gpu-vsync --in-process-gpu --disable-background-networking --no-first-run --disable-sync"
CSP_EXE="$CSP_INSTALL_PATH"
if [[ -n "\$1" ]] && command -v winepath &>/dev/null; then
    WIN_PATH="\$(WINEPREFIX="$WINEPREFIX" winepath --windows "\$1")"
    wine "\$CSP_EXE" "\$WIN_PATH" &
else
    wine "\$CSP_EXE" &
fi
WINE_PID=\$!

if command -v wmctrl &>/dev/null && command -v xprop &>/dev/null; then
    (
        while kill -0 "\$WINE_PID" 2>/dev/null; do
            while IFS= read -r _wid; do
                _st=\$(xprop -id "\$_wid" _NET_WM_STATE 2>/dev/null)
                if [[ "\$_st" == *FULLSCREEN* ]]; then
                    wmctrl -ir "\$_wid" -b remove,fullscreen 2>/dev/null || true
                    xprop -id "\$_wid" -spy _NET_WM_STATE 2>/dev/null | while IFS= read -r _line; do
                        [[ "\$_line" == *FULLSCREEN* ]] && wmctrl -ir "\$_wid" -b remove,fullscreen 2>/dev/null || true
                    done
                    exit 0
                fi
            done < <(xprop -root _NET_CLIENT_LIST 2>/dev/null | tr ',' '\n' | while IFS= read -r _r; do
                _w=\$(echo "\$_r" | tr -d ' #')
                [[ \$(xprop -id "0x\$_w" WM_CLASS 2>/dev/null) == *clipstudiopaint* ]] && echo "0x\$_w"
            done)
            sleep 0.5
        done
    ) &
fi

wait "\$WINE_PID"
LAUNCHEOF
    chmod +x "$LAUNCH_SCRIPT"

    cat > "$LAUNCHER_STUDIO" << LAUNCHEOF
#!/usr/bin/env bash
export LD_LIBRARY_PATH="$FREETYPE_DIR/lib64:$FREETYPE_DIR/lib32:\${LD_LIBRARY_PATH:-}"
export PATH="$WINE_DIR/bin:\$PATH"
export WINESERVER="$WINESERVER_BIN"
export WINEPREFIX="$WINEPREFIX"
export WINEDEBUG=-all
export WINEESYNC=1
export WINEFSYNC=1
export WINEDLLPATH="$LAUNCHER_DIR:\${WINEDLLPATH:-}"
export DXVK_ASYNC=1
export DXVK_STATE_CACHE=1
export DXVK_CONFIG_FILE="$WINEPREFIX/dxvk.conf"
export DXVK_STATE_CACHE_PATH="$WINEPREFIX"
export mesa_glthread=true
export __GL_SHADER_DISK_CACHE=1
export __GL_SHADER_DISK_CACHE_PATH="$WINEPREFIX"
export RADV_PERFTEST=gpl
export WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS="--no-sandbox --disable-gpu-compositing --disable-gpu-vsync --in-process-gpu"
exec wine "$STUDIO_EXE"
LAUNCHEOF
    chmod +x "$LAUNCHER_STUDIO"
}

_install_patches() {
    local _patches_win="$SCRIPT_DIR/patches/x86_64-windows-wine${WINE_VERSION}"
    local _patches_unix="$SCRIPT_DIR/patches/x86_64-unix-wine${WINE_VERSION}"

    if [[ ! -d "$_patches_win" ]] || [[ ! -f "$_patches_win/mfplat.dll" ]]; then
        # try to fetch the exact version from remote
        local _fallback="$DOWNLOAD_DIR/patches/x86_64-windows-wine${WINE_VERSION}"
        if _try_fetch_patch "$_fallback" "patches/x86_64-windows-wine${WINE_VERSION}" "mfplat.dll" &&
           _try_fetch_patch "$_fallback" "patches/x86_64-windows-wine${WINE_VERSION}" "mfreadwrite.dll" &&
           _try_fetch_patch "$_fallback" "patches/x86_64-windows-wine${WINE_VERSION}" "winegstreamer.dll"; then
            _patches_win="$_fallback"
            local _ufallback="$DOWNLOAD_DIR/patches/x86_64-unix-wine${WINE_VERSION}"
            _try_fetch_patch "$_ufallback" "patches/x86_64-unix-wine${WINE_VERSION}" "winegstreamer.so" || true
            _patches_unix="$_ufallback"
        else
            local _closest
            _closest=$(_closest_patch_version "$WINE_VERSION")
            if [[ -n "$_closest" ]]; then
                _patches_win="$_closest"
                _patches_unix="${_closest/x86_64-windows/x86_64-unix}"
                warn "no patches for Wine ${WINE_VERSION}, using $(basename "$_patches_win")"
            fi
        fi
    fi

    local _ok=0
    if [[ -d "$_patches_win" ]] && [[ -f "$_patches_win/mfplat.dll" ]]; then
        mkdir -p "$SYS32"
        local _wine_win="$WINE_DIR/lib/wine/x86_64-windows"
        [[ -d "$_wine_win" ]] || _wine_win="$WINE_DIR/lib64/wine/x86_64-windows"
        local _wine_unix="$WINE_DIR/lib/wine/x86_64-unix"
        [[ -d "$_wine_unix" ]] || _wine_unix="$WINE_DIR/lib64/wine/x86_64-unix"

        if [[ -d "$_wine_win" ]]; then
            for dll in mfplat.dll mfreadwrite.dll winegstreamer.dll; do
                [[ -f "$_patches_win/$dll" ]] && cp "$_patches_win/$dll" "$_wine_win/$dll" && cp "$_patches_win/$dll" "$SYS32/$dll"
            done
            _ok=1
        fi
        if [[ -d "$_patches_unix" ]] && [[ -d "$_wine_unix" ]]; then
            [[ -f "$_patches_unix/winegstreamer.so" ]] && cp "$_patches_unix/winegstreamer.so" "$_wine_unix/winegstreamer.so"
        fi
    fi

    if [[ $_ok -eq 1 ]]; then
        run wine reg add "HKCU\\Software\\Wine\\DllOverrides" /v "mfplat" /t REG_SZ /d "native,builtin" /f || warn "failed to set mfplat override"
        run wine reg add "HKCU\\Software\\Wine\\DllOverrides" /v "mfreadwrite" /t REG_SZ /d "native,builtin" /f || warn "failed to set mfreadwrite override"
        ok "patches applied: video export"
    else
        warn "patches not available for Wine ${WINE_VERSION}, video export or rotated/circular text may not work"
    fi
}

# existing install found and no mode flag given -- ask what to do
if [[ $UPDATE_ONLY -eq 0 ]] && [[ $UPDATE_WINE -eq 0 ]] && [[ -f "$LAUNCH_SCRIPT" ]]; then
    _found_wine=$(_detect_installed_wine || echo "unknown")
    echo ""
    echo -e "  ${YELLOW}${BOLD}existing CSPenguin install found${RESET} ${DIM}(Wine $_found_wine, $LAUNCHER_DIR)${RESET}"
    echo ""
    echo "    1) update       - regenerate launch scripts/config only; keeps your CSP install and Wine version as-is (fast)"
    echo "    2) update wine  - like update, but also upgrades the bundled Wine to the latest release"
    echo "    3) reinstall    - wipe and do a full fresh install"
    echo "    4) cancel"
    echo ""
    _choice=""
    read -t 10 -rp "  choice [will automatically cancel in 10s]: " _choice </dev/tty || true
    echo ""
    _log "menu (existing install found): choice='${_choice:-<empty/timeout>}'"
    case "${_choice:-4}" in
        1) UPDATE_ONLY=1; info "selected: update" ;;
        2) UPDATE_WINE=1; info "selected: update wine" ;;
        3) ok "proceeding with fresh install" ;;
        *) info "cancelled"; exit 0 ;;
    esac
fi

# --update/--update-wine given but no existing install found
if [[ $UPDATE_ONLY -eq 1 || $UPDATE_WINE -eq 1 ]] && [[ ! -f "$LAUNCH_SCRIPT" ]]; then
    _flag_name="--update"
    [[ $UPDATE_WINE -eq 1 ]] && _flag_name="--update-wine"
    echo ""
    echo -e "  ${YELLOW}${BOLD}no existing CSPenguin install found${RESET} ${DIM}($LAUNCHER_DIR)${RESET}"
    echo "  $_flag_name needs an existing install to update."
    echo ""
    echo "    1) install now - run a full fresh install instead"
    echo "    2) cancel"
    echo ""
    _choice=""
    read -t 10 -rp "  choice [will automatically cancel in 10s]: " _choice </dev/tty || true
    echo ""
    _log "menu (no existing install, $_flag_name given): choice='${_choice:-<empty/timeout>}'"
    case "${_choice:-2}" in
        1) UPDATE_ONLY=0; UPDATE_WINE=0; ok "proceeding with fresh install" ;;
        *) info "cancelled"; exit 0 ;;
    esac
fi

# ============================================================
# --update-wine / -w : upgrade Wine without reinstalling CSP
# ============================================================
if [[ $UPDATE_WINE -eq 1 ]]; then
    echo ""
    echo -e "  ${TEAL}${BOLD}[*] Wine update mode${RESET}"
    echo ""

    # detect currently installed Wine version
    _current_wine=$(_detect_installed_wine) \
        || die "could not detect installed Wine version from $LAUNCH_SCRIPT"
    info "currently installed:     Wine $_current_wine"
    info "this installer supports: Wine $WINE_VERSION"

    # informational only -- let the user know if upstream has moved past
    # what this installer currently supports
    info "checking upstream for newer Wine releases..."
    _upstream_latest=$(_latest_kron4ek_wine || true)
    if [[ -n "$_upstream_latest" ]] && [[ "$_upstream_latest" != "$WINE_VERSION" ]]; then
        warn "Wine $_upstream_latest is available upstream, but this installer's patches are only tested against Wine $WINE_VERSION"
        info "check https://github.com/parka6060/CSPenguin-Installer for an updated installer script"
    fi

    if [[ "$_current_wine" == "$WINE_VERSION" ]]; then
        echo ""
        echo -e "  ${YELLOW}${BOLD}already at supported Wine $WINE_VERSION${RESET} ${DIM}-- nothing to update${RESET}"
        echo ""
        echo "    1) update    - regenerate launch scripts/config anyway"
        echo "    2) reinstall - wipe and do a full fresh install"
        echo "    3) cancel"
        echo ""
        _choice=""
        read -t 10 -rp "  choice [will automatically cancel in 10s]: " _choice </dev/tty || true
        echo ""
        _log "menu (already at supported Wine $WINE_VERSION): choice='${_choice:-<empty/timeout>}'"
        case "${_choice:-3}" in
            1) UPDATE_WINE=0; UPDATE_ONLY=1; info "selected: update" ;;
            2) UPDATE_WINE=0; UPDATE_ONLY=0; ok "proceeding with fresh install" ;;
            *) info "cancelled"; exit 0 ;;
        esac
    else
        if [[ "$(_wine_version_cmp "$WINE_VERSION" "$_current_wine")" == "-1" ]]; then
            echo ""
            echo -e "  ${YELLOW}${BOLD}current wine version: $_current_wine is newer than the recommended wine version: $WINE_VERSION${RESET}"
            echo -e "  ${DIM}continuing will downgrade to $WINE_VERSION to ensure compatibility.${RESET}"
            echo ""
            _confirm=""
            read -t 10 -rp "  continue with downgrade? [y/N, cancels in 10s]: " _confirm </dev/tty || true
            _log "downgrade confirmation ($_current_wine -> $WINE_VERSION): answer='${_confirm:-<empty/timeout>}'"
            [[ "$_confirm" =~ ^[Yy]$ ]] || { info "cancelled"; exit 0; }
            ok "downgrading Wine $_current_wine -> $WINE_VERSION"
        else
            ok "upgrading Wine $_current_wine -> $WINE_VERSION"
        fi

        # download new Wine
        _wine_url="https://github.com/Kron4ek/Wine-Builds/releases/download/${WINE_VERSION}/wine-${WINE_VERSION}-amd64.tar.xz"
        _wine_tar="$DOWNLOAD_DIR/wine-${WINE_VERSION}-amd64.tar.xz"
        mkdir -p "$DOWNLOAD_DIR"
        download_progress "Wine ${WINE_VERSION}" "$_wine_url" "$_wine_tar"

        _extract_wine "$_wine_tar"
        _bundle_freetype

        # clean up old Wine version
        _old_wine_dir="$LAUNCHER_DIR/wine-${_current_wine}"
        if [[ -d "$_old_wine_dir" ]] && [[ "$_old_wine_dir" != "$WINE_DIR" ]]; then
            rm -rf "$_old_wine_dir"
            info "removed old Wine ${_current_wine}"
        fi

        export PATH="$WINE_DIR/bin:$PATH"
        export WINEPREFIX WINEARCH WINESERVER="$WINESERVER_BIN"

        # dcomp (login/store panels) – always needed
        DCOMP_DLL="$SCRIPT_DIR/patches/dcomp/dcomp.dll"
        PTHREAD_DLL="$SCRIPT_DIR/patches/dcomp/libwinpthread-1.dll"
        ensure_asset "patches/dcomp/dcomp.dll"          "$DCOMP_DLL"
        ensure_asset "patches/dcomp/libwinpthread-1.dll" "$PTHREAD_DLL"
        [[ -f "$DCOMP_DLL" ]] || die "dcomp.dll not found"
        cp "$DCOMP_DLL"    "$LAUNCHER_DIR/dcomp.dll"
        mkdir -p "$SYS32"
        cp "$DCOMP_DLL"    "$SYS32/dcomp.dll"
        cp "$PTHREAD_DLL"  "$SYS32/libwinpthread-1.dll"
        run wine reg add "HKCU\\Software\\Wine\\DllOverrides" /v "dcomp" /t REG_SZ /d "native,builtin" /f || true
        ok "dcomp.dll (login/store panels)"

        _install_patches

        _write_launchers
        info "launcher scripts regenerated"

        # refresh desktop database
        update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true

        # kill old wineserver, start new one
        "$WINESERVER_BIN" -k 2>/dev/null || true

        ok "update to Wine ${WINE_VERSION} complete!"
        exit 0
    fi
fi

# --update: skip install steps, just regenerate launch scripts + config
if [[ $UPDATE_ONLY -eq 1 ]]; then
    # WINE_VERSION above is the pin, not necessarily what's on disk -- if it
    # doesn't exist, fall back to whatever Wine version is actually installed.
    if [[ ! -d "$WINE_DIR" ]]; then
        _installed_wine=$(_detect_installed_wine || true)
        if [[ -n "$_installed_wine" ]] && [[ -d "$LAUNCHER_DIR/wine-${_installed_wine}" ]]; then
            WINE_VERSION="$_installed_wine"
            WINE_DIR="$LAUNCHER_DIR/wine-${WINE_VERSION}"
            WINE_BIN="$WINE_DIR/bin/wine"
            WINESERVER_BIN="$WINE_DIR/bin/wineserver"
            FREETYPE_DIR="$WINE_DIR/lib/freetype2-${FREETYPE_VERSION}"
        fi
    fi

    export PATH="$WINE_DIR/bin:$PATH"
    export WINEPREFIX WINEARCH WINESERVER="$WINESERVER_BIN"

    if [[ ! -d "$WINE_DIR" ]]; then
        die "Wine not found at $WINE_DIR — run a full install first"
    fi
    if [[ ! -f "$CSP_INSTALL_PATH" ]]; then
        die "CSP not found at $CSP_INSTALL_PATH — run a full install first"
    fi

    echo ""
    echo -e "  ${TEAL}${BOLD}CSPenguin update mode${RESET}"
    echo -e "  ${DIM}regenerating launch scripts, config, and service${RESET}"
    echo ""

    # registry tweaks
    step "configuration"
    run wine reg add "HKCU\\Software\\Wine\\WineDbg" /v ShowCrashDialog /t REG_DWORD /d 0 /f || true
    run wine reg add "HKLM\\System\\CurrentControlSet\\Services\\PlugPlay" /v Start /t REG_DWORD /d 4 /f || true
    run wine reg add "HKLM\\System\\CurrentControlSet\\Services\\WineBus" /v Start /t REG_DWORD /d 4 /f || true
    cat > "$WINEPREFIX/dxvk.conf" << 'DXVKEOF'
dxgi.deferSurfaceCreation = True
dxvk.enableGraphicsPipelineLibrary = True
dxvk.numCompilerThreads = 0
DXVKEOF
    ok "registry + dxvk.conf"
    install_cjk_font_fix
    _bundle_freetype
    _install_gecko

    # fall through to step 6 and step 7, heh 6 7 >:D
fi

if [[ $UPDATE_ONLY -eq 0 ]]; then

# banner + version select

echo ""
echo ""
echo -e "          .--."
echo -e "         |o_o |  ${TEAL}${BOLD}CSPenguin-Installer!${RESET}"
echo -e "         |:_/ |  ${DIM}Never stop drawing.${RESET}"
echo -e "        //   \\ \\"
echo -e "       (|     | )  ${DIM}this script will ask for your password${RESET}"
echo -e "      /'\_   _/\`\\  ${DIM}once or twice to install packages${RESET}"
echo -e "      \___)=(___/  ${DIM}and set system limits.${RESET}"
echo ""
echo ""
echo -e "  ${BOLD}Which version of Clip Studio Paint?${RESET}"
echo "    1) 5.1.2 (latest)"
echo "    2) 5.0.4 (perpetual)"
echo "    3) 4.1.0"
echo "    4) 4.0.10 (perpetual)"
echo "    5) 3.2.3"
echo "    6) 3.0.8 (perpetual)"
echo "    7) 2.3.4"
echo "    8) 2.0.6 (perpetual)"
echo "    9) 1.13.2"
echo "    10) custom installer path or URL"
echo ""

CSP_VERSION="" CSP_URL="" CSP_EXE_NAME=""
while true; do
    read -rp "  choice [1]: " choice </dev/tty
    choice="${choice:-1}"
    case "$choice" in
        1) CSP_VERSION="512"; break ;;
        2) CSP_VERSION="504"; break ;;
        3) CSP_VERSION="410"; break ;;
        4) CSP_VERSION="4010"; break ;;
        5) CSP_VERSION="323"; break ;;
        6) CSP_VERSION="308"; break ;;
        7) CSP_VERSION="234"; break ;;
        8) CSP_VERSION="206"; break ;;
        9) CSP_VERSION="1132"; break ;;
        10)
            read -rp "  path or URL: " custom </dev/tty
            if [[ "$custom" == http* ]]; then
                CSP_URL="$custom"
                CSP_EXE_NAME="$(basename "$custom")"
                CSP_VERSION="custom"
            elif [[ -f "$custom" ]]; then
                CSP_EXE_NAME="$(basename "$custom")"
                if [[ $DRY_RUN -eq 0 ]]; then
                    mkdir -p "$DOWNLOAD_DIR"
                    cp "$(realpath "$custom")" "$DOWNLOAD_DIR/$CSP_EXE_NAME"
                fi
                CSP_URL=""
                CSP_VERSION="custom"
            else
                echo "  file not found: $custom"; continue
            fi
            break ;;
        *) echo "  pick 1-10" ;;
    esac
done

if [[ "$CSP_VERSION" != "custom" ]]; then
    CSP_URL="https://vd.clipstudio.net/clipcontent/paint/app/${CSP_VERSION}/CSP_${CSP_VERSION}w_setup.exe"
    CSP_EXE_NAME="CSP_${CSP_VERSION}w_setup.exe"
fi
# [1/7] dependencies

step "dependencies"
info "checking for required system packages..."

_missing=()
command -v wget >/dev/null 2>&1 || _missing+=(wget)
command -v curl >/dev/null 2>&1 || _missing+=(curl)
command -v unzstd >/dev/null 2>&1 || _missing+=(zstd)
command -v wmctrl >/dev/null 2>&1 || _missing+=(wmctrl)
command -v xprop >/dev/null 2>&1 || _missing+=(xprop)
command -v file >/dev/null 2>&1 || _missing+=(file)
_gst_ok         || _missing+=("gstreamer plugins")

if [[ ${#_missing[@]} -gt 0 ]]; then
    warn "missing: ${_missing[*]}"
    _pm="$(_detect_pm)"
    if [[ "$_pm" == "unknown" ]]; then
        die "unsupported distro, install wget, curl, and gstreamer plugins manually"
    fi
    printf "  ${TEAL}│${RESET} "
    read -rp "  install automatically? [Y/n]: " _ans </dev/tty
    if [[ "${_ans:-y}" =~ ^[Yy]$ ]]; then
        if [[ $DRY_RUN -eq 1 ]]; then
            ok "dependencies (dry run)"
        else
            case "$_pm" in
                pacman) _install_deps_pacman ;;
                dnf)    _install_deps_dnf ;;
                apt)    _install_deps_apt ;;
            esac
        fi
    else
        die "install dependencies manually, then re-run"
    fi
fi

ok "dependencies"

# [2/7] downloads

step "downloads"
info "grabbing Wine, WebView2, and the CSP installer."
if [[ $DRY_RUN -eq 0 ]]; then
    mkdir -p "$DOWNLOAD_DIR" "$LAUNCHER_DIR"
fi

_wine_tar="$DOWNLOAD_DIR/wine-${WINE_VERSION}-amd64.tar.xz"
_need_wine=0
[[ ! -x "$WINE_BIN" ]] && _need_wine=1

if [[ -n "${CSP_URL:-}" ]]; then
    download_progress "Clip Studio Paint" "$CSP_URL" "$DOWNLOAD_DIR/$CSP_EXE_NAME"
else
    ok "Clip Studio Paint (local file)"
fi

_dl_pids=()
_dl_names=()
_dl_dests=()
_dl_tmps=()

_queue_dl() {
    local name="$1" url="$2" dest="$3"
    if [[ -f "$dest" && -s "$dest" ]]; then
        ok "$name (cached)"
        return
    fi
    if [[ $DRY_RUN -eq 1 ]]; then
        ok "$name (dry run)"
        return
    fi
    local tmp="${dest}.part"
    wget -q --timeout=30 --tries=3 -O "$tmp" "$url" &
    _dl_pids+=($!)
    _dl_names+=("$name")
    _dl_dests+=("$dest")
    _dl_tmps+=("$tmp")
}

[[ $_need_wine -eq 1 ]] && _queue_dl "Wine ${WINE_VERSION}" "$WINE_URL" "$_wine_tar" \
                         || ok "Wine ${WINE_VERSION} (cached)"
_queue_dl "WebView2 Runtime" "$WEBVIEW2_URL" "$DOWNLOAD_DIR/MicrosoftEdgeWebView2RuntimeInstallerX64.exe"
_queue_dl "winetricks" "$WINETRICKS_URL" "$WINETRICKS_BIN"

if [[ ${#_dl_pids[@]} -gt 0 ]]; then
    _frames=('|' '/' '-' '\')
    _i=0
    _remaining=${#_dl_pids[@]}
    while [[ $_remaining -gt 0 ]]; do
        for _j in "${!_dl_pids[@]}"; do
            if [[ -n "${_dl_pids[$_j]:-}" ]] && ! kill -0 "${_dl_pids[$_j]}" 2>/dev/null; then
                wait "${_dl_pids[$_j]}" || die "download failed: ${_dl_names[$_j]}"
                mv "${_dl_tmps[$_j]}" "${_dl_dests[$_j]}"
                printf "\r%80s\r" ""
                ok "${_dl_names[$_j]}"
                unset '_dl_pids[$_j]'
                _remaining=$((_remaining - 1))
            fi
        done
        if [[ $_remaining -gt 0 ]]; then
            _pending=""
            for _j in "${!_dl_names[@]}"; do
                [[ -n "${_dl_pids[$_j]:-}" ]] && _pending+="${_dl_names[$_j]}, "
            done
            _pending="${_pending%, }"
            printf "\r  ${TEAL}│${RESET} ${TEAL}%s${RESET} ${DIM}%s${RESET}  " "${_frames[$((_i % 4))]}" "$_pending"
            sleep 0.2
            _i=$((_i + 1))
        fi
    done
fi

if [[ $_need_wine -eq 1 ]] && [[ $DRY_RUN -eq 0 ]]; then
    _extract_wine "$_wine_tar"
    _bundle_freetype
fi

if [[ $DRY_RUN -eq 0 ]]; then
    chmod +x "$WINETRICKS_BIN"
    export PATH="$WINE_DIR/bin:$PATH"
fi

# [3/7] wine prefix

step "wine prefix"
info "setting up a fresh Wine environment for CSP."
if [[ $DRY_RUN -eq 0 ]]; then
    export WINEPREFIX WINEARCH WINESERVER="$WINESERVER_BIN"
    "$WINESERVER_BIN" -k 2>/dev/null || true
    wineserver -k 2>/dev/null || true
    sleep 0.5
fi
wait_for "initialising prefix" env WINEDEBUG=-all wineboot --init

if [[ $DRY_RUN -eq 1 ]]; then
    ok "esync file limits (dry run)"
else
    _nofile=$(ulimit -n 2>/dev/null || echo 0)
    if [[ "$_nofile" -ge 524288 ]]; then
        ok "esync file limits ($_nofile)"
    else
        _esync_set=0
        if systemctl --user status >/dev/null 2>&1; then
            mkdir -p "$HOME/.config/systemd/user.conf.d"
            cat > "$HOME/.config/systemd/user.conf.d/cspenguin-limits.conf" << 'EOF'
[Manager]
DefaultLimitNOFILE=524288
EOF
            ok "esync (systemd user config)"
            _esync_set=1
        fi
        _current_user="$(whoami)"
        if sudo tee /etc/security/limits.d/cspenguin.conf > /dev/null << EOF
# CSPenguin-Installer : esync file descriptor limit
$_current_user soft nofile 524288
$_current_user hard nofile 524288
EOF
        then
            [[ $_esync_set -eq 0 ]] && ok "esync (limits.d)"
            _esync_set=1
        fi
        if [[ $_esync_set -eq 0 ]]; then
            warn "could not set file limit"
        else
            _ESYNC_RESTART=1
        fi
    fi
fi

# [4/7] runtime + patches

step "runtime + patches"
info "installing fonts, libraries, and fixes."

if [[ $SKIP_WINETRICKS -eq 1 ]]; then
    ok "winetricks (skipped)"
else
    _wt_log="$WINEPREFIX/winetricks.log"
    _wt_needed=()
    for pkg in corefonts vcrun2022 dotnet48 dxvk vkd3d; do
        grep -qx "$pkg" "$_wt_log" 2>/dev/null || _wt_needed+=("$pkg")
    done
    if [[ ${#_wt_needed[@]} -eq 0 ]]; then
        ok "winetricks packages (already installed)"
    else
        [[ " ${_wt_needed[*]} " == *" dotnet48 "* ]] && warn "this can take 10-30 min, go pet a cat!"
        wait_for "${_wt_needed[*]}" env WINEDEBUG=-all "$WINETRICKS_BIN" -q "${_wt_needed[@]}"
    fi
fi

_install_gecko

# compatibility settings (must be after winetricks, dotnet48 resets the version)
if [[ $DRY_RUN -eq 0 ]]; then
    run wine reg add "HKCU\\Software\\Wine" /v Version /t REG_SZ /d "win10" /f || warn "failed to set windows version"
    run wine reg add "HKCU\\Software\\Wine\\DllOverrides" /v "concrt140" /t REG_SZ /d "native,builtin" /f || warn "failed to set concrt140 override"
    run wine reg add "HKCU\\Software\\Wine\\WineDbg" /v ShowCrashDialog /t REG_DWORD /d 0 /f || warn "failed to suppress crash dialog"

    # Disable unnecessary Wine services that slow down startup
    run wine reg add "HKLM\\System\\CurrentControlSet\\Services\\PlugPlay" /v Start /t REG_DWORD /d 4 /f || true
    run wine reg add "HKLM\\System\\CurrentControlSet\\Services\\WineBus" /v Start /t REG_DWORD /d 4 /f || true

    cat > "$WINEPREFIX/dxvk.conf" << 'EOF'
dxgi.deferSurfaceCreation = True
dxvk.enableGraphicsPipelineLibrary = True
dxvk.numCompilerThreads = 0
EOF
fi
ok "windows version: win10"
ok "dll overrides + dxvk.conf"

if [[ $DRY_RUN -eq 1 ]]; then
    ok "dcomp.dll (login/store panels)"
    ok "mfplat + winegstreamer (video export)"
    ok "CJK font: WenQuanYi Micro Hei (dry run)"
else
    mkdir -p "$LAUNCHER_DIR"

    DCOMP_DLL="$SCRIPT_DIR/patches/dcomp/dcomp.dll"
    PTHREAD_DLL="$SCRIPT_DIR/patches/dcomp/libwinpthread-1.dll"
    ensure_asset "patches/dcomp/dcomp.dll"          "$DCOMP_DLL"
    ensure_asset "patches/dcomp/libwinpthread-1.dll" "$PTHREAD_DLL"
    [[ -f "$DCOMP_DLL" ]] || die "dcomp.dll not found"

    cp "$DCOMP_DLL"    "$LAUNCHER_DIR/dcomp.dll"
    cp "$DCOMP_DLL"    "$SYS32/dcomp.dll"
    cp "$PTHREAD_DLL"  "$SYS32/libwinpthread-1.dll"
    run wine reg add "HKCU\\Software\\Wine\\DllOverrides" /v "dcomp" /t REG_SZ /d "native,builtin" /f || warn "failed to set dcomp override"
    ok "dcomp.dll (login/store panels)"

    _install_patches
    install_cjk_font_fix
fi

# [5/7] install CSP

step "install CSP"

if [[ $DRY_RUN -eq 1 ]]; then
    ok "WebView2 Runtime (dry run)"
    gap
    msg "${BOLD}press enter to launch the CSP installer.${RESET}"
    msg "${DIM}complete the installer as normal.${RESET}"
    gap
    printf "  ${TEAL}│${RESET}   "
    read -rp "press enter to continue..." </dev/tty
    ok "Clip Studio Paint (dry run)"
else
    info "installing WebView2 (for login/store panels)."
    warn "WebView2 will flash open briefly, that's normal"
    env WINEDEBUG=-all WINEDLLOVERRIDES="winemenubuilder.exe=d" \
        wine "$DOWNLOAD_DIR/MicrosoftEdgeWebView2RuntimeInstallerX64.exe" >> "$LOG_FILE" 2>&1 &
    wait $! || warn "WebView2 installer exited with an error"
    env WINEDEBUG=-all wineserver -k 2>/dev/null || true
    sleep 1
    ok "WebView2 Runtime"

    gap
    msg "${BOLD}press enter to launch the CSP installer.${RESET}"
    msg "${DIM}complete the installer as normal.${RESET}"
    gap
    printf "  ${TEAL}│${RESET}   "
    read -rp "press enter to continue..." </dev/tty
    info "CSP installer running, come back when done..."
    env WINEDEBUG=-all WINEDLLOVERRIDES="winemenubuilder.exe=d" \
        wine "$DOWNLOAD_DIR/$CSP_EXE_NAME" >> "$LOG_FILE" 2>&1 &
    wait $! || die "CSP installer failed"
    [[ -f "$CSP_INSTALL_PATH" ]] || die "CSP not found after install, did you complete the installer?"

    find "$HOME/.local/share/applications" -name "*CLIP STUDIO PAINT*.desktop" -delete 2>/dev/null || true
    find "$HOME/Desktop" -name "*CLIP STUDIO PAINT*.desktop" -delete 2>/dev/null || true
    ok "Removed installer-generated launchers"

    ok "Clip Studio Paint"

    run wine reg add "HKCU\\Software\\Wine\\AppDefaults\\msedgewebview2.exe" /v Version /t REG_SZ /d "win7" /f || warn "failed to set webview2 version"
    run wine reg add "HKCU\\Software\\Wine\\AppDefaults\\CLIPStudioPaint.exe" /v Version /t REG_SZ /d "win81" /f || warn "failed to set CSP version"
    run wine reg add "HKCU\\Software\\Wine\\AppDefaults\\CLIPStudio.exe" /v Version /t REG_SZ /d "win81" /f || warn "failed to set CLIP STUDIO version"
fi

fi # end UPDATE_ONLY skip

# [6/7] desktop integration

step "desktop integration"
info "creating app shortcuts and file previews."

if [[ $DRY_RUN -eq 1 ]]; then
    ok "launch scripts (dry run)"
    ok "desktop entries (dry run)"
    if [[ "${XDG_CURRENT_DESKTOP:-}" == *"KDE"* ]]; then
        ok "KDE window rules (dry run)"
    fi
    ok ".clip thumbnails + MIME type (dry run)"
else

# --- APP ICONS ---
# We pull the icons from the Wikimedea Commons and avoid shipping them in the repo to comply with trademark laws.
# This way if an icon is missing for some reason we still have a backup icon to use.
ICON_THEME_DIR="$HOME/.local/share/icons/hicolor/512x512/apps"
ICON_PAINT="$ICON_THEME_DIR/clipstudiopaint.png"
ICON_STUDIO="$ICON_THEME_DIR/clipstudio.png"
ICON_URL="https://upload.wikimedia.org/wikipedia/commons/1/14/Clipstudiopaint_app_logo.png"
mkdir -p "$ICON_THEME_DIR"

_fetch_icon() {
    local dest="$1"
    if [[ -f "$dest" ]] && file "$dest" | grep -q 'PNG image'; then
        ok "icon: $(basename "$dest") (cached)"
        return
    fi
    local tmp="${dest}.part"
    if wget -q --timeout=30 --tries=3 -O "$tmp" "$ICON_URL" && file "$tmp" | grep -q 'PNG image'; then
        mv "$tmp" "$dest"
        ok "icon: $(basename "$dest")"
    else
        rm -f "$tmp" 2>/dev/null || true
        warn "icon download failed: $(basename "$dest")"
    fi
}

_fetch_icon "$ICON_PAINT"
_fetch_icon "$ICON_STUDIO"

_write_launchers
ok "launch scripts"

DESKTOP_FILE="$HOME/.local/share/applications/clipstudiopaint.desktop"
DESKTOP_STUDIO="$HOME/.local/share/applications/clipstudio.desktop"
mkdir -p "$HOME/.local/share/applications"

cat > "$DESKTOP_FILE" << EOF
[Desktop Entry]
Name=Clip Studio Paint
Exec=$LAUNCH_SCRIPT %f
Terminal=false
Type=Application
Categories=Graphics;
MimeType=application/x-clip;
StartupWMClass=clipstudiopaint.exe
Icon=$ICON_PAINT
EOF

cat > "$DESKTOP_STUDIO" << EOF
[Desktop Entry]
Name=CLIP STUDIO
Exec=$LAUNCHER_STUDIO
Terminal=false
Type=Application
Categories=Graphics;
StartupWMClass=clipstudio.exe
Icon=$ICON_STUDIO
EOF

chmod +x "$DESKTOP_FILE" "$DESKTOP_STUDIO"
ok "desktop entries"

if [[ "${XDG_CURRENT_DESKTOP:-}" == *"KDE"* ]]; then
    cp "$DESKTOP_FILE"   "$HOME/Desktop/clipstudiopaint.desktop" 2>/dev/null || true
    cp "$DESKTOP_STUDIO" "$HOME/Desktop/clipstudio.desktop"      2>/dev/null || true

    _kwinrc="$HOME/.config/kwinrulesrc"
    _kwc="" _krc=""
    if command -v kwriteconfig6 >/dev/null 2>&1; then
        _kwc=kwriteconfig6; _krc=kreadconfig6
    elif command -v kwriteconfig5 >/dev/null 2>&1; then
        _kwc=kwriteconfig5; _krc=kreadconfig5
    fi

    if [[ -n "$_kwc" ]]; then
        _write_kwin_subwindow_rule() {
            local uuid="$1"
            $_kwc --file kwinrulesrc --group "$uuid" --key Description "CSPenguin: CSP subwindows on top"
            $_kwc --file kwinrulesrc --group "$uuid" --key below false
            $_kwc --file kwinrulesrc --group "$uuid" --key belowrule 3
            $_kwc --file kwinrulesrc --group "$uuid" --key above true
            $_kwc --file kwinrulesrc --group "$uuid" --key aboverule 3
            $_kwc --file kwinrulesrc --group "$uuid" --key fsplevel 3
            $_kwc --file kwinrulesrc --group "$uuid" --key fsplevelrule 2
            $_kwc --file kwinrulesrc --group "$uuid" --key hastransientparent true
            $_kwc --file kwinrulesrc --group "$uuid" --key hastransientparentmatch 1
            $_kwc --file kwinrulesrc --group "$uuid" --key skiptaskbar true
            $_kwc --file kwinrulesrc --group "$uuid" --key skiptaskbarrule 3
            $_kwc --file kwinrulesrc --group "$uuid" --key wmclass "clipstudiopaint.exe clipstudiopaint.exe"
            $_kwc --file kwinrulesrc --group "$uuid" --key wmclasscomplete true
            $_kwc --file kwinrulesrc --group "$uuid" --key wmclassmatch 1
        }

        _register_kwin_rule() {
            local uuid="$1" rules
            rules=$($_krc --file kwinrulesrc --group General --key rules 2>/dev/null || true)
            if [[ "$rules" != *"$uuid"* ]]; then
                local new_rules="${rules:+$rules,}$uuid"
                $_kwc --file kwinrulesrc --group General --key rules "$new_rules"
            fi
        }

        _reload_kwin() {
            qdbus org.kde.KWin /KWin reconfigure 2>/dev/null || \
                dbus-send --type=method_call --dest=org.kde.KWin /KWin org.kde.KWin.reconfigure 2>/dev/null || true
        }

        _csp_uuid=""
        _is_old_rule=0
        if grep -q "CSPenguin:" "$_kwinrc" 2>/dev/null; then
            _csp_uuid=$(awk -F'[][]' '/^\[/{grp=$2} /CSPenguin:/{print grp; exit}' "$_kwinrc" 2>/dev/null || true)
            if [[ -n "$_csp_uuid" ]]; then
                _below_val=$($_krc --file kwinrulesrc --group "$_csp_uuid" --key below 2>/dev/null || true)
                [[ "$_below_val" == "true" ]] && _is_old_rule=1
            fi
        fi

        if [[ -n "$_csp_uuid" ]]; then
            if [[ $_is_old_rule -eq 1 ]]; then
                warn "migrating old CSPenguin window rule..."
                _write_kwin_subwindow_rule "$_csp_uuid"
                _reload_kwin
                ok "KDE window rules (migrated)"
            else
                _wmclass=$($_krc --file kwinrulesrc --group "$_csp_uuid" --key wmclass 2>/dev/null || true)
                _wmclasscomplete=$($_krc --file kwinrulesrc --group "$_csp_uuid" --key wmclasscomplete 2>/dev/null || true)
                _above_val=$($_krc --file kwinrulesrc --group "$_csp_uuid" --key above 2>/dev/null || true)

                if [[ "$_wmclass" != "clipstudiopaint.exe clipstudiopaint.exe" ]] || \
                   [[ "$_wmclasscomplete" != "true" ]] || \
                   [[ "$_above_val" != "true" ]]; then
                    _write_kwin_subwindow_rule "$_csp_uuid"
                    _reload_kwin
                    ok "KDE window rules (updated)"
                else
                    ok "KDE window rules (already set)"
                fi
            fi
        else
            _uuid_above="cspenguin-$(uuidgen 2>/dev/null || echo above-rule)"
            _write_kwin_subwindow_rule "$_uuid_above"
            _register_kwin_rule "$_uuid_above"
            _reload_kwin
            ok "KDE window rules"
        fi
    else
        warn "kwriteconfig not found, set window rules manually"
    fi
    # rebuild the KDE menu database so updated .desktop entries + icons show up immediately
    if command -v kbuildsycoca6 >/dev/null 2>&1; then
        kbuildsycoca6 2>/dev/null || true
    elif command -v kbuildsycoca5 >/dev/null 2>&1; then
        kbuildsycoca5 2>/dev/null || true
    fi
fi

update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
gtk-update-icon-cache -f -t "$HOME/.local/share/icons/hicolor" 2>/dev/null || true

THUMBNAILER_SRC="$SCRIPT_DIR/patches/thumbnailer/clip-thumbnailer"
THUMBNAILER_BIN="$HOME/.local/bin/clip-thumbnailer"
ensure_asset "patches/thumbnailer/clip-thumbnailer" "$THUMBNAILER_SRC"

mkdir -p "$HOME/.local/bin"
if [[ -x "$THUMBNAILER_BIN" ]]; then
    ok ".clip thumbnails (already installed)"
else
    install -Dm755 "$THUMBNAILER_SRC" "$THUMBNAILER_BIN"

    _MIME_DIR="$HOME/.local/share/mime"
    mkdir -p "$_MIME_DIR/packages"
    if [[ ! -f "$_MIME_DIR/packages/clip.xml" ]]; then
        cat > "$_MIME_DIR/packages/clip.xml" << 'MIMEEOF'
<?xml version="1.0" encoding="UTF-8"?>
<mime-info xmlns="http://www.freedesktop.org/standards/shared-mime-info">
  <mime-type type="application/x-clip">
    <comment>Clip Studio Paint file</comment>
    <glob pattern="*.clip"/>
  </mime-type>
</mime-info>
MIMEEOF
        update-mime-database "$_MIME_DIR" 2>/dev/null || true
    fi

    _THUMB_DIR="$HOME/.local/share/thumbnailers"
    mkdir -p "$_THUMB_DIR"
    if [[ ! -f "$_THUMB_DIR/clip.thumbnailer" ]]; then
        cat > "$_THUMB_DIR/clip.thumbnailer" << THUMBEOF
[Thumbnailer Entry]
TryExec=$THUMBNAILER_BIN
Exec=$THUMBNAILER_BIN %i %o
MimeType=application/x-clip;
THUMBEOF
    fi
    ok ".clip thumbnails + MIME type"
fi

fi

# [7/7] finishing up

step "finishing up"

if pgrep -fi huion >/dev/null 2>&1; then
    warn "Huion proprietary driver detected"
    info "this can block pen pressure in CSP under Wine"
    info "try uninstalling the Huion driver if pressure"
    info "doesn't work, your kernel likely supports it"
    gap
fi

info "pre-warming the wineserver at login"
info "reduces startup time by ~5-10s."
gap
if [[ $UPDATE_ONLY -eq 1 ]] && systemctl --user is-enabled csp-wineserver.service &>/dev/null; then
    _prewarm="y"
    info "updating existing wineserver service"
else
    printf "  ${TEAL}│${RESET}   "
    read -rp "enable wineserver pre-warm? [Y/n] " _prewarm </dev/tty
fi
if [[ "${_prewarm,,}" != "n" ]]; then
    if [[ $DRY_RUN -eq 1 ]]; then
        ok "wineserver service (dry run)"
    else
        mkdir -p "$HOME/.config/systemd/user"
        cat > "$HOME/.config/systemd/user/csp-wineserver.service" << EOF
[Unit]
Description=Wine server pre-warm for CSP
After=default.target

[Service]
Type=simple
Environment=PATH=$WINE_DIR/bin:/usr/bin
Environment=WINEPREFIX=$WINEPREFIX
Environment=WINESERVER=$WINESERVER_BIN
Environment=WINEDEBUG=-all
ExecStartPre=-$WINESERVER_BIN -k
ExecStart=$WINESERVER_BIN -f -p
Restart=always
RestartSec=5s

[Install]
WantedBy=default.target
EOF
        if systemctl --user daemon-reload 2>/dev/null && systemctl --user enable --now csp-wineserver.service 2>/dev/null; then
            ok "wineserver service enabled"
        else
            warn "could not enable wineserver service"
        fi
    fi
else
    ok "wineserver pre-warm skipped"
fi

_install_ok=1

_divider=$(printf '━%.0s' $(seq 1 46))
echo ""
echo -e "  ${TEAL}${_divider}${RESET}"
echo ""
echo -e "  ${AMBER}+${RESET} ${AMBER}${BOLD}all done!${RESET}"
echo ""
echo -e "  find ${BOLD}Clip Studio Paint${RESET} in your"
echo -e "  app menu, or launch via terminal:"
echo -e "  ${DIM}$LAUNCH_SCRIPT${RESET}"
echo ""
if [[ $_ESYNC_RESTART -eq 1 ]]; then
echo -e "  ${AMBER}note${RESET}"
echo -e "    log out and back in for esync to take effect"
echo ""
fi
echo -e "  ${AMBER}tips${RESET}"
echo -e "    ${DIM}pen pressure${RESET}  Preferences > Tablet > mouse mode"
echo -e "    ${DIM}hidpi${RESET}         winecfg > Graphics > DPI"
echo -e "    ${DIM}thumbnails${RESET}    enable in file manager preview settings"
echo -e "                   (Dolphin: Configure Dolphin > Interface > Previews"
echo -e "                    > tick \"Clip Studio Paint File\", then restart Dolphin)"
echo ""
echo -e "  ${DIM}something not working? open an issue at${RESET}"
echo -e "  ${DIM}https://github.com/parka6060/CSPenguin-Installer${RESET}"
echo ""
echo -e "  ${DIM}installer by https://eninabox.art${RESET}"
echo ""
echo -e "  ${TEAL}${_divider}${RESET}"
echo ""
