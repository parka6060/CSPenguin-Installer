![CSP running on Linux](assets/Screenshot_20260318_041049.png)

# video tutorial 👇

[![Watch the tutorial](https://img.youtube.com/vi/iYhEm32Lr4Y/maxresdefault.jpg)](https://www.youtube.com/watch?v=iYhEm32Lr4Y)

**CSPenguin-Installer** is an install script and patch set for CLIP STUDIO PAINT. It fixes the **asset store, login panels, file thumbnails, and timelapse/animation export** all while being very easy to install.

The current project is **functional**! Thank you for those who reported issues when testing the script. If you have any issues during install please submit a report under the issues tab of the project.

Supports CSP 4.x & 5.x at the moment.

## Requirements

- A **Vulkan-capable GPU**
- A little bit of patience

Everything else (Wine, Winetricks, GStreamer plugins) is detected and installed automatically by the script.

## Install

One-liner via curl:

```bash
curl -fsSL https://raw.githubusercontent.com/parka6060/CSPenguin-Installer/main/install.sh | bash
```

Or clone the repo via:

```bash
git clone https://github.com/parka6060/CSPenguin-Installer.git
cd CSPenguin-Installer
./install.sh
```

The script downloads CSP and WebView2, sets up a Wine prefix, installs dependencies, applies patches, and creates desktop entries. You'll walk through the CSP installer when it pops up and pick a version (5.0.4 or 4.1.0) You can also bring your own installer via link or file.

## Updating

To refresh your existing installation (reapplies config, patches, and fonts without re-downloading Wine or CSP):

```bash
./install.sh --update
```

Or via curl:

```bash
curl -fsSL https://raw.githubusercontent.com/parka6060/CSPenguin-Installer/main/install.sh | bash -s -- --update
```

This requires Wine and CSP to already be installed.

## Updating Wine

To install or repair the supported bundled Wine runtime without reinstalling CSP:

```bash
./install.sh --update-wine
```

_Note: this installs the exact Wine version tested together with its matching patches. It does not automatically select the latest upstream Wine release._

or

```bash
curl -fsSL https://raw.githubusercontent.com/parka6060/CSPenguin-Installer/main/install.sh | bash -s -- --update-wine
```


## Updating KWin Rules

If you're on KDE and the window rules aren't working properly (subwindows/menus appearing behind CSP), or you're not a fan of the main CSP window being forced underneath everything, you can update the KDE Window rules:

```bash
./kwin-rules.sh
```

This will migrate any old rules previous versions created and apply the current configuration.

## What gets installed

1. Wine (bundled, portable) at `~/.local/share/cspenguin/wine-<VERSION>/`
2. Wine prefix at `~/.wine-csp`
3. Corefonts, vcrun2022, and dotnet48 as runtime dependencies, plus a lightweight CJK font (WenQuanYi Micro Hei) for the asset store and brushes.
4. DXVK + VKD3D
5. WebView2 Runtime (standalone installer)
6. Wine Gecko (the MSHTML/IE engine) installed into the prefix, so any IE-based UI renders instead of showing a blank/grey page
7. dcomp.dll + libwinpthread-1.dll, a DirectComposition shim + dependency so WebView2 panels render correctly
8. mfplat/mfreadwrite/winegstreamer patches for timelapse/video export
9. `.clip` file thumbnails via a native thumbnailer binary (must be enabled in your file manager — on Dolphin/KDE: _Configure Dolphin → Interface → Previews_ → tick "Clip Studio Paint File", then restart Dolphin)
10. `.clip` file association so double-clicking opens CSP
11. KDE window rules (KDE only) so ribbon bar dropdowns appear on top of CSP instead of behind it. If this doesn't apply properly you can right click your CSP icon in your taskbar or set up window rules yourself!
12. A wineserver pre-warm service so CSP launches a bit faster
13. Patched `winex11.so` / `win32u.so` so menus open right under the menu bar and maximize works on window managers such as COSMIC (see below)

> **Note:** `.clip` file thumbnails need to be **enabled in your file manager's preview settings** — on Dolphin/KDE, open _Configure Dolphin → Interface → Previews_ and tick the "Clip Studio Paint File" entry (after running the installer, restart your file manager).

## Running wine/winetricks manually

The bundled Wine is not in your system PATH. To run wine or winetricks against the CSP prefix:

```bash
export PATH="$HOME/.local/share/cspenguin/wine-<VERSION>/bin:$PATH"
export WINEPREFIX="$HOME/.wine-csp"
wine --version
winetricks <package>
```

Find the installed version with `ls ~/.local/share/cspenguin/wine-*/`.

## Window placement patches (winex11, win32u)

On some window managers, notably COSMIC, stock Wine misplaces CSP's windows:

- **Menus and tooltips** pop up far from the menu bar or the hovered button, even on another monitor.
  CSP draws its menus as borderless popups owned by small helper windows; stock Wine hands them to
  the window manager as transient dialogs, which it then places on its own. Tooltips end up the same
  way because they are created with a caption and only become borderless popups before being shown.
- **Maximize** snaps back right away. CSP draws its own frame and expects a maximized window to
  cover the work area plus a frame that lies off screen, like on Windows. The window manager
  maximizes the host window to the work area instead, the size change is reported back, and CSP
  restores itself.

The installer replaces the bundled `winex11.so` and `win32u.so` (always together) with versions
that:

- keep owned borderless popups (menus, tooltips, dropdowns) unmanaged, so Wine positions them itself,
  and decide whether a window is managed only once it is shown (a window can't be made unmanaged
  again). The main window stays managed, so focus, keyboard shortcuts and Alt+Tab keep working.
- keep the off screen frame of a maximized window that draws its own frame out of the host window,
  so the host window matches the rect the window manager maximizes it to.
- don't send position requests or ask for window manager decorations while such a window is maximized.

COSMIC also doesn't publish its work area (the screen minus panels) to X11, so Wine would assume the
whole monitor is usable. On COSMIC the launchers run `cspenguin-workarea.sh`, which maximizes an
invisible dummy window once to measure the panels and publishes the result as `_GTK_WORKAREAS_D0`
(needs `python3`; it does nothing when the window manager publishes `_NET_WORKAREA` itself).

- Sources: [`patches/winex11-unmanaged-owned-popups.patch`](patches/winex11-unmanaged-owned-popups.patch), [`patches/winex11-maximize-own-frame.patch`](patches/winex11-maximize-own-frame.patch) and [`patches/win32u-clip-maximized-frame.patch`](patches/win32u-clip-maximized-frame.patch) against the official Wine source; work area helper in [`patches/workarea/`](patches/workarea/)
- Build: `patches/build-wine-unix-patches.sh [WINE_VERSION]` rebuilds both libraries reproducibly in an AlmaLinux 8 container (podman or docker, glibc 2.28)
- To fall back to stock behaviour for one run: `CSPENGUIN_MANAGED_POPUPS=1` (menus), `CSPENGUIN_CLIP_MAXIMIZED=0` (maximize), `CSPENGUIN_WORKAREA=0` (skip the work area helper)
- To revert completely, copy `winex11.so.orig` and `win32u.so.orig` back over `winex11.so` and `win32u.so` in `~/.local/share/cspenguin/wine-<VERSION>/lib/wine/x86_64-unix/`
- License: the shipped `winex11.so` and `win32u.so` are modified parts of Wine, licensed under the LGPL-2.1-or-later. Their corresponding source is the official `wine-<VERSION>` tarball from dl.winehq.org plus the patches above, and `build-wine-unix-patches.sh` reproduces the binaries.

## Known issues

- Timelapse should work 100%, but animation export at non-default framerates could break encoding; not thoroughly tested.
- Wine updates require an exact matching timelapse patch set; newer upstream Wine releases are not selected automatically.
- The installer can take a while, especially if downloading dotnet files.
- On COSMIC, maximizing CSP with the window manager's keyboard shortcut (instead of CSP's maximize button) can leave a thin white border along the top and left edges.

## Support

Before opening an issue, please search the existing issues and run debug.sh. Include its output along with your distribution, desktop environment, GPU, and what you were doing when the problem occurred.

I (eninabox) maintain this project on a best-effort basis. I'm not actively developing new features or able to investigate every system specific problem, but I'll still help when the answer is clear, review contributions, and update the supported Wine ver when it brings significant improvements to CSP.

There are also some lovely people who have contributed to answering questions and may be able to help when I can't. Pull requests, community-tested fixes, and people helping each other in the issues are always very welcome!

## Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/parka6060/CSPenguin-Installer/main/uninstall.sh | bash
```

Or if you cloned the repo:

```bash
./uninstall.sh
```

---

Brought to you by <https://eninabox.art/>

Maybe I'll go use krita instead...
