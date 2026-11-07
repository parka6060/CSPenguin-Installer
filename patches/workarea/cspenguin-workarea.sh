#!/usr/bin/env bash
# Publish the desktop work area (the screen minus panels/docks) to X11 for Wine.
#
# COSMIC doesn't set _NET_WORKAREA / _GTK_WORKAREAS_D0, so Wine assumes the whole
# monitor is usable. CSP draws its own frame and restores itself whenever the window
# manager maximizes it to a rect that doesn't match its own idea of the work area.
# This measures the work area with cspenguin-workarea.py and publishes it as
# _GTK_WORKAREAS_D0 on the root window, which winex11 reads.
#
# Expects WINEPREFIX and WINESERVER from the launcher. Never fails the launch.

[[ "${XDG_CURRENT_DESKTOP:-}" == *COSMIC* ]] || exit 0
[[ "${CSPENGUIN_WORKAREA:-1}" == 0 ]] && exit 0
command -v python3 >/dev/null 2>&1 || exit 0
command -v xprop >/dev/null 2>&1 || exit 0

# the window manager publishes it itself
xprop -root _NET_WORKAREA 2>/dev/null | grep -q '=' && exit 0

_probe="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/cspenguin-workarea.py"
[[ -f "$_probe" ]] || exit 0

_new=$(timeout 10 python3 -I "$_probe" 2>/dev/null) || exit 0
[[ "$_new" =~ ^[0-9]+(,\ [0-9]+)*$ ]] || exit 0
_old=$(xprop -root _GTK_WORKAREAS_D0 2>/dev/null | sed -n 's/^[^=]*= //p')
[[ "$_new" == "$_old" ]] && exit 0

xprop -root -f _GTK_WORKAREAS_D0 32c -set _GTK_WORKAREAS_D0 "$_new" || exit 0

# Wine caches the monitor layout. Restart the wineserver so it picks up the new
# work area, but never while CSP or CLIP STUDIO is running.
if pgrep -u "$(id -u)" -f 'CLIPStudio[A-Za-z]*\.exe' >/dev/null 2>&1; then
    exit 0
fi
if systemctl --user is-active --quiet csp-wineserver.service 2>/dev/null; then
    # The pre-warm service kills any running wineserver when it (re)starts, so restart
    # the service instead of killing the server underneath it. systemctl returns before
    # the server listens; wait for its socket, or the Wine process launched next starts
    # a second server, the service fails, and its restart kills CSP a few seconds later.
    systemctl --user restart csp-wineserver.service 2>/dev/null || true
    if [[ -n "${WINEPREFIX:-}" ]] && _ids=$(stat -c '%d %i' "$WINEPREFIX" 2>/dev/null); then
        # shellcheck disable=SC2086
        _socket="/tmp/.wine-$(id -u)/server-$(printf '%x-%x' $_ids)/socket"
        for _ in $(seq 100); do
            [[ -S "$_socket" ]] && systemctl --user is-active --quiet csp-wineserver.service && break
            sleep 0.1
        done
    fi
elif [[ -n "${WINESERVER:-}" ]]; then
    "$WINESERVER" -k 2>/dev/null || true
    "$WINESERVER" -w 2>/dev/null || true
fi
exit 0
