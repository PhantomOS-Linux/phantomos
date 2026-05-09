# Scripts are copied in a separate stage to avoid installing dependencies in the final image
FROM scratch AS ctx
COPY scripts/ /scripts

FROM scratch AS rootfs
COPY rootfs/ /

# Base image
FROM docker.io/archlinux/archlinux:latest AS base

# Install dependencies for building bootc
FROM base AS builder-bootc
RUN pacman -Syu --noconfirm make git rust go-md2man ostree glibc pkgconf grub gcc-libs efibootmgr wget patch

WORKDIR /home/build
RUN --mount=type=bind,from=ctx,source=/scripts,target=/scripts \
    /scripts/compile-bootc.sh

FROM base AS builder-bootupd
RUN pacman -Syu --noconfirm make git rust go-md2man ostree glibc pkgconf grub gcc-libs efibootmgr wget patch
WORKDIR /home/build
RUN --mount=type=bind,from=ctx,source=/scripts,target=/scripts \
    /scripts/compile-bootupd.sh

# Right System
FROM base AS system
# Copy bootc
COPY --from=builder-bootc /output /
# Copy bootupd
COPY --from=builder-bootupd /output /

RUN grep "= */var" /etc/pacman.conf | sed "/= *\/var/s/.*=// ; s/ //" | xargs -n1 sh -c 'mkdir -p "/usr/lib/sysimage/$(dirname $(echo $1 | sed "s@/var/@@"))" && mv -v "$1" "/usr/lib/sysimage/$(echo "$1" | sed "s@/var/@@")"' '' && \
    sed -i -e "/= *\/var/ s/^#//" -e "s@= */var@= /usr/lib/sysimage@g" -e "/DownloadUser/d" /etc/pacman.conf

# Update system
RUN pacman -Syu --noconfirm

# Install pacman packages to system
COPY packages /tmp/packages
RUN pacman -Syu --noconfirm \
    $(tr '\n' ' ' < /tmp/packages)

# Copy the rootfs
COPY --from=rootfs / /

# Generate initramfs
RUN --mount=type=bind,from=ctx,source=/scripts,target=/scripts \
    /scripts/initramfs.sh

# Prepare filesystem for bootc
RUN --mount=type=bind,from=ctx,source=/scripts,target=/scripts \
    sed -i 's|^HOME=.*|HOME=/var/home|' "/etc/default/useradd" && \
    /scripts/bootc-rootfs.sh


# Set label to identify the image as bootc
LABEL containers.bootc 1

# Check that the image is valid for bootc
RUN bootc container lint


