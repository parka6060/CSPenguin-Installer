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

To upgrade the bundled Wine without reinstalling CSP:

```bash
./install.sh --update-wine
```

_Note: this will only update wine to newer versions that have already been tested for compatibility by the maintainers of this install script. If you wish to install an newer, unverified wine version, please do so manually._

or

```bash
curl -fsSL https://raw.githubusercontent.com/parka6060/CSPenguin-Installer/main/install.sh | bash -s -- --update-wine
```

This downloads the new Wine, applies the available patches, and updates the launcher scripts — your Wine prefix, CSP install, and settings are preserved.

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
6. dcomp.dll + libwinpthread-1.dll, a DirectComposition shim + dependency so WebView2 panels render correctly
7. mfplat/mfreadwrite/winegstreamer patches for timelapse/video export
8. `.clip` file thumbnails via a native thumbnailer binary
9. `.clip` file association so double-clicking opens CSP
10. KDE window rules (KDE only) so ribbon bar dropdowns appear on top of CSP instead of behind it. If this doesn't apply properly you can right click your CSP icon in your taskbar or set up window rules yourself!
11. A wineserver pre-warm service so CSP launches a bit faster

## Running wine/winetricks manually

The bundled Wine is not in your system PATH. To run wine or winetricks against the CSP prefix:

```bash
export PATH="$HOME/.local/share/cspenguin/wine-<VERSION>/bin:$PATH"
export WINEPREFIX="$HOME/.wine-csp"
wine --version
winetricks <package>
```

Find the installed version with `ls ~/.local/share/cspenguin/wine-*/`.

## Known issues

- Timelapse should work 100%, but animation export at non-default framerates could break encoding; not thoroughly tested.
- The timelapse patch DLLs may not be available for every Wine version. If they're missing, `--update-wine` will select the closest available version.
- The installer can take a while, especially if downloading dotnet files.

## Support

If you have problems please first check the issues tab and see if there's an existing solution, if not, then please submit an issue with all the information you have so it can be investigated.

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
