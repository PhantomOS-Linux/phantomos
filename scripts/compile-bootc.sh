#!/usr/bin/env bash

set -xeuo pipefail

git clone "https://github.com/bootc-dev/bootc.git" .
 
make bin install-all DESTDIR=/output

mkdir -p /output/usr/lib/libostree
cp -rv /output/usr/libexec/libostree/* /output/usr/lib/libostree
