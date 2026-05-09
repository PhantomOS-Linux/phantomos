#!/usr/bin/env bash

set -xeuo pipefail
# Get grub version from pacman
GRUB_VERSION=$(pacman -Q grub | awk '{print $2}')

# Create base directory for bootupd
mkdir -p /usr/lib/efi/grub/$GRUB_VERSION/EFI/arch

build_grub() {
    local target=$1
    local out=$2
    local moddir="/usr/lib/grub/$target"

    # Copy unifont and build memdisk.squashfs
    mkdir -p memdisk/fonts
    cp /usr/share/grub/unicode.pf2 memdisk/fonts
    mksquashfs memdisk memdisk.squashfs -comp lzo

    mapfile -t modules < <(
        find "$moddir" -maxdepth 1 -type f -name '*.mod' \
        | sed 's#.*/##' | sed 's/\.mod$//' | sort -u
    )

    echo "Building GRUB for target: $target with modules: ${modules[*]}"
    grub-mkimage -O "$target" \
        -o "$out" \
        -m memdisk.squashfs \
        -p "/EFI/arch" \
        "${modules[@]}"

    rm -rf memdisk
    rm memdisk.squashfs

}


build_grub "x86_64-efi" "/usr/lib/efi/grub/$GRUB_VERSION/EFI/arch/grubx64.efi"
build_grub "i386-efi" "/usr/lib/efi/grub/$GRUB_VERSION/EFI/arch/grubia32.efi"

# Generate update metadata
bootupctl backend generate-update-metadata

install -dm0755 /usr/lib/systemd/system/bootloader-update.service.d
cat > /usr/lib/systemd/system/bootloader-update.service.d/migrate-static-grub-config.conf << 'EOF'
[Service]
ExecStart=/usr/bin/bootupctl migrate-static-grub-config
EOF

