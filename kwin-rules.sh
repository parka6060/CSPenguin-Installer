#!/usr/bin/env bash
set -euo pipefail

_kwinrc="$HOME/.config/kwinrulesrc"
_kwc="" _krc=""

if command -v kwriteconfig6 >/dev/null 2>&1; then
    _kwc=kwriteconfig6; _krc=kreadconfig6
elif command -v kwriteconfig5 >/dev/null 2>&1; then
    _kwc=kwriteconfig5; _krc=kreadconfig5
else
    echo "error: kwriteconfig not found (requires KDE)"
    exit 1
fi

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
    local uuid="$1"
    local rules=$($_krc --file kwinrulesrc --group General --key rules 2>/dev/null || true)
    local count=$($_krc --file kwinrulesrc --group General --key count 2>/dev/null || echo 0)
    if [[ "$rules" != *"$uuid"* ]]; then
        local new_count=$((count + 1))
        local new_rules="${rules:+$rules,}$uuid"
        $_kwc --file kwinrulesrc --group General --key count "$new_count"
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
        echo "migrating old CSPenguin window rule..."
        _write_kwin_subwindow_rule "$_csp_uuid"
        _reload_kwin
        echo "KDE window rules updated (migrated from old rule)"
    else
        _write_kwin_subwindow_rule "$_csp_uuid"
        _reload_kwin
        echo "KDE window rules updated"
    fi
else
    _uuid_above="cspenguin-$(uuidgen 2>/dev/null || echo above-rule)"
    _write_kwin_subwindow_rule "$_uuid_above"
    _register_kwin_rule "$_uuid_above"
    _reload_kwin
    echo "KDE window rules installed"
fi
