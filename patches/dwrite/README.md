# dwrite: keep the system font collection in memory

`dwrite-keep-system-collection.patch` applies to Wine 11.4 (`dlls/dwrite/main.c`, 54 added lines).
The built file is `patches/x86_64-windows-wine11.4/dwrite.dll`.

## What it fixes

While CSP starts it calls `IDWriteGdiInterop::CreateFontFromLOGFONT` about 354 times before its first window shows.
Each call gets the system font collection, uses it and releases it. Wine's factory only holds a weak pointer to that
collection, so every call builds it again from every installed font. With about 1,100 fonts one build takes about 85 ms,
which adds up to about 30 seconds.

With the patch the shared factory keeps a reference to the collection and hands the same one out again until the
system Fonts registry key changes. That is the same check Wine's system font set already uses, so installing or
removing a font still gives a new collection.

## Build

Only the PE side is needed. The runner's own `dwrite.so` stays as it is.

```
tar xf wine-11.4.tar.xz
cd wine-11.4 && patch -p1 < ../dwrite-keep-system-collection.patch && cd ..
mkdir build64 && cd build64
../wine-11.4/configure --enable-win64 --without-x --without-freetype --disable-tests
make -j"$(nproc)" dlls/dwrite/x86_64-windows/dwrite.dll
x86_64-w64-mingw32-strip -s dlls/dwrite/x86_64-windows/dwrite.dll -o dwrite.dll
```

The shipped file was built this way with mingw-w64 gcc 16.2.
sha256: `c2968a555b2d2d4b73241302df2c362d3561ce0fa04a684e24d2094535832f0b`

## Install

Wine loads `dwrite.dll` from its own `lib/wine/x86_64-windows` directory. A copy in `WINEDLLPATH` or in the prefix is
not picked up. `install.sh` copies the file there and keeps the original next to it as `dwrite.dll.orig`.

To undo by hand, with CSP closed: move `dwrite.dll.orig` back over `dwrite.dll`.
