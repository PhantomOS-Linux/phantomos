#!/usr/bin/env bash

set -xeuo pipefail

git clone https://github.com/coreos/bootupd.git .
wget https://raw.githubusercontent.com/PhantomOS-Linux/bootupd-archlinux-patch/refs/heads/main/0001-archlinux.patch

patch -Np1 -i 0001-archlinux.patch
export RUSTUP_TOOLCHAIN=stable
export CARGO_TARGET_DIR=target
make

RUST_BACKTRACE=1 cargo test
make DESTDIR=/output LIBEXECDIR=/usr/lib install
mv /output/usr/lib/bootupd /output/usr/bin/bootupctl
make DESTDIR=/output LIBEXECDIR=/usr/lib install-grub-static
make DESTDIR=/output LIBEXECDIR=/usr/lib install-systemd-unit
