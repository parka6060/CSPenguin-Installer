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

Update your prefix with:

```bash
curl -fsSL https://raw.githubusercontent.com/parka6060/CSPenguin-Installer/main/install.sh | bash -s -- --update
```

Or if you cloned the repo:

```bash
./install.sh --update
```

This skips the CSP/Wine download and reinstall, and just reapplies the latest config, patches, and fonts to your existing prefix. Requires Wine and CSP to already be installed.

The script downloads CSP and WebView2, sets up a Wine prefix, installs dependencies, applies patches, and creates desktop entries. You'll walk through the CSP installer when it pops up and pick a version (5.0.1 or 4.1.0) You can also bring your own installer via link or file.

## What gets installed

1. Wine 11.4 (bundled, portable) at `~/.local/share/cspenguin/wine-11.4/`
2. Wine prefix at `~/.wine-csp`
3. Corefonts, vcrun2022, and dotnet48 as runtime dependencies, plus a lightweight CJK font (WenQuanYi Micro Hei) for the asset store and brushes.
4. DXVK + VKD3D
5. WebView2 Runtime (standalone installer)
6. dcomp.dll + libwinpthread-1.dll, a DirectComposition shim + dependency so WebView2 panels render correctly
7. mfplat/mfreadwrite/winegstreamer patches for timelapse/video export
8. `.clip` file thumbnails via a native thumbnailer binary
9. `.clip` file association so double-clicking opens CSP
10. KDE window rules (KDE only) so ribbon bar dropdowns appear on top of CSP instead of behind it. If this doesn't apply properly you can right click your CSP icon in your taskbar or set up window rules yourself!
11. A wineserver pre-warm service so CSP launches a bit faster

## Running wine/winetricks manually

The bundled Wine is not in your system PATH. To run wine or winetricks against the CSP prefix:

```bash
export PATH="$HOME/.local/share/cspenguin/wine-11.4/bin:$PATH"
export WINEPREFIX="$HOME/.wine-csp"
wine --version
winetricks <package>
```

## Known issues!!
- Timelapse should work 100%, but animation export at non-default framerates could break encoding; not thoroughly tested.
- The timelapse patch DLLs are built against the bundled Wine version 11.4. Trying to use them elsewhere is not recommended.
- The installer can take a while, especially if downloading dotnet files.

## Support
If you have problems please first check the issues tab and see if there's an existing solution, if not submit an issue. 

## Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/parka6060/CSPenguin-Installer/main/uninstall.sh | bash
```

Or if you cloned the repo:

```bash
./uninstall.sh
```
___

Brought to you by https://eninabox.art/

Maybe I'll go use krita instead...
