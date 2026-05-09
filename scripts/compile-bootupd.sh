#!/usr/bin/env bash

set -xeuo pipefail

git clone https://github.com/coreos/bootupd.git .
wget https://raw.githubusercontent.com/PhantomOS-Linux/bootupd-archlinux-patch/refs/heads/main/0001-archlinux.patch

patch -Np1 -i ../0001-archlinux.patch
export RUSTUP_TOOLCHAIN=stable
export CARGO_TARGET_DIR=target
make

RUST_BACKTRACE=1 cargo test
make DESTDIR=/output install
make DESTDIR=/output install-grub-static
make DESTDIR=/output install-systemd-unit
