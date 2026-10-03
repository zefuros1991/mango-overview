#!/bin/sh
# Build mango-overview and pack the installed files into the tarball that
# the mango-overview-bin package downloads.
#   scripts/make-release.sh        -> dist/mango-overview-<version>-x86_64.tar.zst
set -eu
cd "$(dirname "$(readlink -f "$0")")/.."
version=$(sed -n 's/^project(mango-overview VERSION \([0-9.]*\).*/\1/p' CMakeLists.txt)
rm -rf build-release dist/stage
cmake -S . -B build-release -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr -Wno-dev
cmake --build build-release
DESTDIR="$PWD/dist/stage" cmake --install build-release
tar --zstd -C dist/stage -cf "dist/mango-overview-$version-x86_64.tar.zst" usr
rm -rf dist/stage build-release
echo "dist/mango-overview-$version-x86_64.tar.zst"
