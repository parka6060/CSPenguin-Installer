#!/usr/bin/env bash
set -euo pipefail

VERBOSE=0
SKIP_WINETRICKS=0
DRY_RUN=0
_ESYNC_RESTART=0
for arg in "$@"; do
    [[ "$arg" == "--verbose"         || "$arg" == "-v" ]] && VERBOSE=1
    [[ "$arg" == "--skip-winetricks" || "$arg" == "-s" ]] && SKIP_WINETRICKS=1
    [[ "$arg" == "--dry-run"         || "$arg" == "-n" ]] && DRY_RUN=1
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

step() {
    STEP=$((STEP + 1))
    echo ""
    echo -e "  ${TEAL}│${RESET} ${TEAL}${BOLD}[${STEP}/${TOTAL_STEPS}] $1${RESET}"
}

ok()   { echo -e "  ${TEAL}│${RESET} ${AMBER}+${RESET} $1"; }
warn() { echo -e "  ${TEAL}│${RESET} ${YELLOW}!${RESET} ${YELLOW}$1${RESET}"; }
info() { echo -e "  ${TEAL}│${RESET} ${DIM}- $1${RESET}"; }
gap()  { echo -e "  ${TEAL}│${RESET}"; }
msg()  { echo -e "  ${TEAL}│${RESET} $1"; }

die() {
    echo ""
    echo -e "  ${RED}✗ ERROR:${RESET} $1"
    [[ -n "${LOG_FILE:-}" ]] && echo -e "  ${DIM}log: $LOG_FILE${RESET}"
    echo -e "  ${DIM}https://github.com/parka6060/CSPenguin-Installer/issues${RESET}"
    exit 1
}

# cleanup
_install_ok=0
cleanup() {
    [[ $DRY_RUN -eq 1 ]] && return
    rm -f "$DOWNLOAD_DIR"/*.part 2>/dev/null
    [[ $_install_ok -0 ]] && wineserver -k 2>/dev/null || true
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

WINE_VERSION="11.4"
WINE_URL="https://github.com/Kron4ek/Wine-Builds/releases/download/${WINE_VERSION}/wine-${WINE_VERSION}-amd64.tar.xz"
WEBVIEW2_URL="https://msedge.sf.dl.delivery.mp.microsoft.com/filestreamingservice/files/76eb3dc4-7851-45b7-a392-460523b0e2bb/MicrosoftEdgeWebView2RuntimeInstallerX64.exe"
WINETRICKS_URL="https://raw.githubusercontent.com/Winetricks/winetricks/master/src/winetricks"
LAUNCHER_DIR="$HOME/.local/share/cspenguin"
WINE_DIR="$LAUNCHER_DIR/wine-${WINE_VERSION}"
WINE_BIN="$WINE_DIR/bin/wine"
WINESERVER_BIN="$WINE_DIR/bin/wineserver"
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
    total=$(wget --spider --server-response "$url" 2>&1 \
        | grep -i content-length | tail -1 | awk '{print $2}' | tr -d '\r')
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

_gst_ok() { command -v gst-inspect-1.0 >/dev/null 2>&1 && gst-inspect-1.0 h264parse >/dev/null 2>&1; }

_install_deps_pacman() {
    local pkgs=()
    command -v wget   >/dev/null 2>&1 || pkgs+=(wget)
    command -v wmctrl >/dev/null 2>&1 || pkgs+=(wmctrl)
    command -v xprop  >/dev/null 2>&1 || pkgs+=(xorg-xprop)
    _gst_ok         || pkgs+=(gst-plugins-bad gst-plugins-good)
    [[ ${#pkgs[@]} -gt 0 ]] && sudo pacman -S --needed --noconfirm "${pkgs[@]}"
}

_install_deps_dnf() {
    local pkgs=()
    command -v wget   >/dev/null 2>&1 || pkgs+=(wget)
    command -v wmctrl >/dev/null 2>&1 || pkgs+=(wmctrl)
    command -v xprop  >/dev/null 2>&1 || pkgs+=(xprop)
    _gst_ok         || pkgs+=(gstreamer1-plugins-bad-free gstreamer1-plugins-good)
    [[ ${#pkgs[@]} -gt 0 ]] && sudo dnf install -y "${pkgs[@]}"
}

_install_deps_apt() {
    local pkgs=(dirmngr ca-certificates)
    command -v wget   >/dev/null 2>&1 || pkgs+=(wget)
    command -v wmctrl >/dev/null 2>&1 || pkgs+=(wmctrl)
    command -v xprop  >/dev/null 2>&1 || pkgs+=(x11-utils)
    _gst_ok         || pkgs+=(gstreamer1.0-plugins-bad gstreamer1.0-plugins-good)
    sudo apt install -y "${pkgs[@]}"
}

# log file
if [[ $DRY_RUN -eq 1 ]]; then
    LOG_FILE="/dev/null"
else
    mkdir -p "$DOWNLOAD_DIR"
    : > "$LOG_FILE"
    echo "CSPenguin-Installer > $(date)" >> "$LOG_FILE"
fi

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
echo "    1) 5.0.1 (latest)"
echo "    2) 4.1.0 (previous stable)"
echo "    3) custom installer path or URL"
echo ""

CSP_VERSION="" CSP_URL="" CSP_EXE_NAME=""
while true; do
    read -rp "  choice [1]: " choice </dev/tty
    choice="${choice:-1}"
    case "$choice" in
        1) CSP_VERSION="501"; break ;;
        2) CSP_VERSION="410"; break ;;
        3)
            read -rp "  path or URL: " custom </dev/tty
            if [[ "$custom" == http* ]]; then
                CSP_URL="$custom"
                CSP_EXE_NAME="$(basename "$custom")"
                CSP_VERSION="custom"
            elif [[ -f "$custom" ]]; then
                CSP_EXE_NAME="$(basename "$custom")"
                if [[ $DRY_RUN -eq 0 ]]; then
                    mkdir -p "$DOWNLOAD_DIR"
                    # Fix: use full path for copy
                    cp "$(realpath "$custom")" "$DOWNLOAD_DIR/$CSP_EXE_NAME"
                fi
                CSP_URL=""
                CSP_VERSION="custom"
            else
                echo "  file not found: $custom"; continue
            fi
            break ;;
        *) echo "  pick 1, 2, or 3" ;;
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
_gst_ok         || _missing+=("gstreamer plugins")

if [[ ${#_missing[@]} -gt 0 ]]; then
    warn "missing: ${_missing[*]}"
    _pm="$(_detect_pm)"
    if [[ "$_pm" == "unknown" ]]; then
        die "unsupported distro, install wget and gstreamer plugins manually"
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

# CSP gets its own progress bar (it's the big one)
if [[ -n "${CSP_URL:-}" ]]; then
    download_progress "Clip Studio Paint" "$CSP_URL" "$DOWNLOAD_DIR/$CSP_EXE_NAME"
else
    ok "Clip Studio Paint (local file)"
fi

# rest in parallel
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

# extract wine
if [[ $_need_wine -eq 1 ]] && [[ $DRY_RUN -eq 0 ]]; then
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

# esync
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
    for pkg in corefonts cjkfonts vcrun2022 dotnet48 dxvk vkd3d; do
        grep -qx "$pkg" "$_wt_log" 2>/dev/null || _wt_needed+=("$pkg")
    done
    if [[ ${#_wt_needed[@]} -eq 0 ]]; then
        ok "winetricks packages (already installed)"
    else
        [[ " ${_wt_needed[*]} " == *" dotnet48 "* ]] && warn "this can take 10-30 min, go pet a cat!"
        wait_for "${_wt_needed[*]}" env WINEDEBUG=-all "$WINETRICKS_BIN" -q "${_wt_needed[@]}"
    fi
fi

# compatibility settings (must be after winetricks — dotnet48 resets the version)
if [[ $DRY_RUN -eq 0 ]]; then
    run wine reg add "HKCU\\Software\\Wine" /v Version /t REG_SZ /d "win10" /f || warn "failed to set windows version"
    run wine reg add "HKCU\\Software\\Wine\\DllOverrides" /v "concrt140" /t REG_SZ /d "native,builtin" /f || warn "failed to set concrt140 override"
    run wine reg add "HKCU\\Software\\Wine\\WineDbg" /v ShowCrashDialog /t REG_DWORD /d 0 /f || warn "failed to suppress crash dialog"
    cat > "$WINEPREFIX/dxvk.conf" << 'EOF'
dxgi.deferSurfaceCreation = True
EOF
fi
ok "windows version: win10"
ok "dll overrides + dxvk.conf"

if [[ $DRY_RUN -eq 1 ]]; then
    ok "dcomp.dll (login/store panels)"
    ok "mfplat + winegstreamer (video export)"
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

    PATCHES_WIN="$SCRIPT_DIR/patches/x86_64-windows-wine11.4"
    PATCHES_UNIX="$SCRIPT_DIR/patches/x86_64-unix-wine11.4"
    ensure_asset "patches/x86_64-windows-wine11.4/mfplat.dll" "$PATCHES_WIN/mfplat.dll"
    ensure_asset "patches/x86_64-windows-wine11.4/mfreadwrite.dll" "$PATCHES_WIN/mfreadwrite.dll"
    ensure_asset "patches/x86_64-windows-wine11.4/winegstreamer.dll" "$PATCHES_WIN/winegstreamer.dll"
    ensure_asset "patches/x86_64-unix-wine11.4/winegstreamer.so" "$PATCHES_UNIX/winegstreamer.so"

    WINE_WIN="$WINE_DIR/lib/wine/x86_64-windows"
    [[ -d "$WINE_WIN" ]] || WINE_WIN="$WINE_DIR/lib64/wine/x86_64-windows"
    WINE_UNIX="$WINE_DIR/lib/wine/x86_64-unix"
    [[ -d "$WINE_UNIX" ]] || WINE_UNIX="$WINE_DIR/lib64/wine/x86_64-unix"

    if [[ -d "$PATCHES_WIN" ]] && [[ -d "$WINE_WIN" ]]; then
        for dll in mfplat.dll mfreadwrite.dll winegstreamer.dll; do
            [[ -f "$PATCHES_WIN/$dll" ]] && cp "$PATCHES_WIN/$dll" "$WINE_WIN/$dll" && cp "$PATCHES_WIN/$dll" "$SYS32/$dll"
        done
    fi
    if [[ -d "$PATCHES_UNIX" ]] && [[ -d "$WINE_UNIX" ]] && [[ -f "$PATCHES_UNIX/winegstreamer.so" ]]; then
        cp "$PATCHES_UNIX/winegstreamer.so" "$WINE_UNIX/winegstreamer.so"
    fi

    run wine reg add "HKCU\\Software\\Wine\\DllOverrides" /v "mfplat" /t REG_SZ /d "native,builtin" /f || warn "failed to set mfplat override"
    run wine reg add "HKCU\\Software\\Wine\\DllOverrides" /v "mfreadwrite" /t REG_SZ /d "native,builtin" /f || warn "failed to set mfreadwrite override"
    ok "mfplat + winegstreamer (video export)"
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
    
    # 1: Fix - Delete the launcher created by the installer
    find "$HOME/.local/share/applications" -name "*CLIP STUDIO PAINT*.desktop" -delete 2>/dev/null || true
    find "$HOME/Desktop" -name "*CLIP STUDIO PAINT*.desktop" -delete 2>/dev/null || true
    ok "Removed installer-generated launchers"
    
    ok "Clip Studio Paint"

    run wine reg add "HKCU\\Software\\Wine\\AppDefaults\\msedgewebview2.exe" /v Version /t REG_SZ /d "win7" /f || warn "failed to set webview2 version"
    run wine reg add "HKCU\\Software\\Wine\\AppDefaults\\CLIPStudioPaint.exe" /v Version /t REG_SZ /d "win81" /f || warn "failed to set CSP version"
    run wine reg add "HKCU\\Software\\Wine\\AppDefaults\\CLIPStudio.exe" /v Version /t REG_SZ /d "win81" /f || warn "failed to set CLIP STUDIO version"
fi

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

# 2: Fix - Pull in the app icon
ICON_PATH="$HOME/.local/share/icons/clipstudiopaint.png"
ICON_STUDIO_PATH="$HOME/.local/share/icons/clipstudio.png"
mkdir -p "$HOME/.local/share/icons"
ensure_asset "assets/clipstudiopaint.png" "$ICON_PATH"
ensure_asset "assets/clipstudio.png" "$ICON_STUDIO_PATH"

cat > "$LAUNCH_SCRIPT" << LAUNCHEOF
#!/usr/bin/env bash
export PATH="$WINE_DIR/bin:\$PATH"
export WINESERVER="$WINESERVER_BIN"
export WINEPREFIX="$WINEPREFIX"
export WINEDEBUG=-all
export WINEESYNC=1
export WINEFSYNC=1
export WINEDLLPATH="$LAUNCHER_DIR:\${WINEDLLPATH:-}"
export DXVK_ASYNC=1
export DXVK_CONFIG_FILE="$WINEPREFIX/dxvk.conf"
export WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS="--no-sandbox"
CSP_EXE="$CSP_INSTALL_PATH"
if [[ -n "\$1" ]] && command -v winepath &>/dev/null; then
    WIN_PATH="\$(WINEPREFIX="$WINEPREFIX" winepath --windows "\$1")"
    wine "\$CSP_EXE" "\$WIN_PATH" &
else
    wine "\$CSP_EXE" &
fi
WINE_PID=\$!

# Strip fullscreen state whenever CSP sets it (Wine maps borderless-maximized to fullscreen).
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
export PATH="$WINE_DIR/bin:\$PATH"
export WINESERVER="$WINESERVER_BIN"
export WINEPREFIX="$WINEPREFIX"
export WINEDEBUG=-all
export WINEESYNC=1
export WINEFSYNC=1
export WINEDLLPATH="$LAUNCHER_DIR:\${WINEDLLPATH:-}"
export DXVK_ASYNC=1
export DXVK_CONFIG_FILE="$WINEPREFIX/dxvk.conf"
export WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS="--no-sandbox --disable-gpu-compositing --disable-gpu-vsync --in-process-gpu"
exec wine "$STUDIO_EXE"
LAUNCHEOF
chmod +x "$LAUNCHER_STUDIO"
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
Icon=$ICON_PATH
EOF

cat > "$DESKTOP_STUDIO" << EOF
[Desktop Entry]
Name=CLIP STUDIO
Exec=$LAUNCHER_STUDIO
Terminal=false
Type=Application
Categories=Graphics;
StartupWMClass=clipstudio.exe
Icon=$ICON_STUDIO_PATH
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
        if ! grep -q "CSPenguin:" "$_kwinrc" 2>/dev/null; then
            _uuid_below="cspenguin-$(uuidgen 2>/dev/null || echo below-rule)"

            $_kwc --file kwinrulesrc --group "$_uuid_below" --key Description "CSPenguin: CSP below for popups"
            $_kwc --file kwinrulesrc --group "$_uuid_below" --key below true
            $_kwc --file kwinrulesrc --group "$_uuid_below" --key belowrule 3
            $_kwc --file kwinrulesrc --group "$_uuid_below" --key fullscreen false
            $_kwc --file kwinrulesrc --group "$_uuid_below" --key fullscreenrule 3
            $_kwc --file kwinrulesrc --group "$_uuid_below" --key wmclass "clipstudiopaint.exe"
            $_kwc --file kwinrulesrc --group "$_uuid_below" --key wmclassmatch 2

            _existing_rules=$($_krc --file kwinrulesrc --group General --key rules 2>/dev/null || true)
            _existing_count=$($_krc --file kwinrulesrc --group General --key count 2>/dev/null || echo 0)
            _new_count=$((_existing_count + 1))
            if [[ -n "$_existing_rules" ]]; then
                _new_rules="${_existing_rules},${_uuid_below}"
            else
                _new_rules="${_uuid_below}"
            fi
            $_kwc --file kwinrulesrc --group General --key count "$_new_count"
            $_kwc --file kwinrulesrc --group General --key rules "$_new_rules"

            qdbus org.kde.KWin /KWin reconfigure 2>/dev/null || \
                dbus-send --type=method_call --dest=org.kde.KWin /KWin org.kde.KWin.reconfigure 2>/dev/null || true
            ok "KDE window rules"
        else
            _csp_uuid=$(awk -F'[][]' '/^\[/{grp=$2} /CSPenguin:/{print grp; exit}' "$_kwinrc" 2>/dev/null || true)
            if [[ -n "$_csp_uuid" ]]; then
                _fs_val=$($_krc --file kwinrulesrc --group "$_csp_uuid" --key fullscreen 2>/dev/null || true)
                if [[ "$_fs_val" != "false" ]]; then
                    $_kwc --file kwinrulesrc --group "$_csp_uuid" --key fullscreen false
                    $_kwc --file kwinrulesrc --group "$_csp_uuid" --key fullscreenrule 3
                    qdbus org.kde.KWin /KWin reconfigure 2>/dev/null || \
                        dbus-send --type=method_call --dest=org.kde.KWin /KWin org.kde.KWin.reconfigure 2>/dev/null || true
                    ok "KDE window rules (updated)"
                else
                    ok "KDE window rules (already set)"
                fi
            else
                ok "KDE window rules (already set)"
            fi
        fi
    else
        warn "kwriteconfig not found, set window rules manually"
    fi
fi

update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true

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

fi  # end dry-run guard for desktop integration

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
printf "  ${TEAL}│${RESET}   "
read -rp "enable wineserver pre-warm? [Y/n] " _prewarm </dev/tty
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
Environment=WINEPREFIX=$WINEPREFIX
Environment=WINESERVER=$WINESERVER_BIN
Environment=WINEDEBUG=-all
ExecStartPre=-$WINESERVER_BIN -k
ExecStart=$WINESERVER_BIN -f
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

# done

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
echo ""
echo -e "  ${DIM}something not working? open an issue at${RESET}"
echo -e "  ${DIM}https://github.com/parka6060/CSPenguin-Installer${RESET}"
echo ""
echo -e "  ${DIM}installer by https://eninabox.art${RESET}"
echo ""
echo -e "  ${TEAL}${_divider}${RESET}"
echo ""
