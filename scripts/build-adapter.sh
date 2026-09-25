#!/bin/zsh
# Builds MediaRemoteAdapter.framework (ungive/mediaremote-adapter, BSD-3) with CMake.
set -e
cd "$(dirname "$0")/../Vendor/mediaremote-adapter"
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release >/dev/null
cmake --build build --target MediaRemoteAdapter
