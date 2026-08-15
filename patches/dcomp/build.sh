#!/bin/bash
set -e
cd "$(dirname "$0")"
x86_64-w64-mingw32-g++ -shared -static -O2 -std=c++17 \
  -o dcomp.dll dcomp_csp.cpp dcomp.def \
  -lole32 -lgdi32 -ldxgi -ld3d11 -luuid
echo "dcomp.dll rebuilt successfully"
