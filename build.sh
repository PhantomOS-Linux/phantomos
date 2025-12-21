#! /bin/bash

set -e
set -x

if [ $EUID -ne 0 ]; then
    echo "This script must be run as root"
    exit 1
fi

BUILD_USER=${BUILD_USER:-}
OUTPUT_DIR=${OUTPUT_DIR:-}

source config

if [ -z "${SYSTEM_NAME}" ]; then
  echo "SYSTEM_NAME must be specified"
  exit
fi

if [ -z "${VERSION}" ]; then
  echo "VERSION must be specified"
  exit
fi

DISPLAY_VERSION=${VERSION}
LSB_VERSION=${VERSION}
VERSION_NUMBER=${VERSION}

if [ -n "$1" ]; then
	DISPLAY_VERSION="${VERSION} (${1})"
	VERSION="${VERSION}_${1}"
	LSB_VERSION="${LSB_VERSION}　(${1})"
	BUILD_ID="${1}"
fi

MOUNT_PATH=/tmp/${SYSTEM_NAME}-build
BUILD_PATH=${MOUNT_PATH}/subvolume
SNAP_PATH=${MOUNT_PATH}/${SYSTEM_NAME}-${VERSION}
BUILD_IMG=/output/${SYSTEM_NAME}-build.img
MAX_SIZE_MB=1800

mkdir -p ${MOUNT_PATH}

fallocate -l ${SIZE} ${BUILD_IMG}
mkfs.btrfs -f ${BUILD_IMG}
mount -t btrfs -o loop,compress-force=zstd:15 ${BUILD_IMG} ${MOUNT_PATH}
btrfs subvolume create ${BUILD_PATH}

echo "Starting build of ${SYSTEM_DESC} ${DISPLAY_VERSION}"

cp /etc/makepkg.conf rootfs/etc/makepkg.conf
pacstrap -K -C rootfs/etc/pacman.conf ${BUILD_PATH}

mkdir -p ${BUILD_PATH}/etc/pacman.d
cp /etc/pacman.d/mirrorlist rootfs/etc/pacman.d/mirrorlist
cp -R config rootfs/. ${BUILD_PATH}/

mount --bind ${BUILD_PATH} ${BUILD_PATH}
arch-chroot ${BUILD_PATH} /bin/bash << EOF
   set -e
   set -x
   source /config

   pacman-key --populate
   sed -i '/ParallelDownloads/s/^/#/g' /etc/pacman.conf
   sed -i '/CheckSpace/s/^/#/g' /etc/pacman.conf

   pacman -Syy --noconfirm
   sed -i '/BUILDENV/s/ check/ !check/g' /etc/makepkg.conf
   sed -i '/OPTIONS/s/ debug/ !debug/g' /etc/makepkg.conf
   
   pacman -S --noconfirm ${KERNEL_PACKAGE} ${KERNEL_PACKAGE}-headers
   pacman --noconfirm -Rdd jack2 || true

   pacman --noconfirm -S --overwrite '*' --disable-download-timeout ${PACKAGES}
   rm -rf /var/cache/pacman/pkg

   yes | pacman -S iptables-nft

   systemctl enable ${SERVICES}
   systemctl --global enable ${USER_SERVICES}
   passwd --lock root

   echo "export EDITOR=/usr/bin/nano" >> /etc/bash.bashrc

   echo "
    AuthorizedKeysFile	.ssh/authorized_keys
    PasswordAuthentication no
    ChallengeResponseAuthentication no
    UsePAM yes
    PrintMotd no # pam does that
    Subsystem	sftp	/usr/lib/ssh/sftp-server
    " > /etc/ssh/sshd_config

   echo "
    UUID=xxx-xxx /var       btrfs     defaults,subvolid=256,rw,noatime,nodatacow,nofail                                                                                                                                                                                                                      0   0
    UUID=xxx-xxx /home      btrfs     defaults,subvolid=257,rw,noatime,nodatacow,nofail                                                                                                                                                                                                                      0   0
    UUID=xxx-xxx /phantomos_root btrfs     defaults,subvolid=5,rw,noatime,nodatacow,x-initrd.mount                                                                                                                                                                                                                0   2
    overlay         /etc       overlay   defaults,x-systemd.requires-mounts-for=/phantomos_root,x-systemd.requires-mounts-for=/sysroot/phantomos_root,x-systemd.rw-only,lowerdir=/sysroot/etc,upperdir=/sysroot/phantomos_root/etc,workdir=/sysroot/phantomos_root/.etc,index=off,metacopy=off,comment=etcoverlay,x-initrd.mount    0   0
    " > /etc/fstab

    echo "
    LSB_VERSION=1.4
    DISTRIB_ID=${SYSTEM_NAME}
    DISTRIB_RELEASE=\"${LSB_VERSION}\"
    DISTRIB_DESCRIPTION=${SYSTEM_DESC}
    " > /etc/lsb-release

    echo 'NAME="${SYSTEM_DESC}"
    VERSION="${DISPLAY_VERSION}"
    VERSION_ID="${VERSION_NUMBER}"
    BUILD_ID="${BUILD_ID}"
    PRETTY_NAME="${SYSTEM_DESC} ${DISPLAY_VERSION}"
    ID=${SYSTEM_NAME}
    ID_LIKE=arch
    ANSI_COLOR="1;31"
    HOME_URL="${WEBSITE}"
    DOCUMENTATION_URL="${DOCUMENTATION_URL}"
    BUG_REPORT_URL="${BUG_REPORT_URL}"' > /usr/lib/os-release

    postinstallhook

    pacman -Q > /manifest

    mkdir -p /usr/var/lib/pacman
    cp -r /var/lib/pacman/local /usr/var/lib/pacman/

    if [ ${KERNEL_PACKAGE} != 'linux' ] ; then
	    mv /boot/vmlinuz-${KERNEL_PACKAGE} /boot/vmlinuz-linux
	    mv /boot/initramfs-${KERNEL_PACKAGE}.img /boot/initramfs-linux.img
	    mv /boot/initramfs-${KERNEL_PACKAGE}-fallback.img /boot/initramfs-linux-fallback.img
    fi

    rm -rf \
    /home \
    /var \

    rm -rf ${FILES_TO_DELETE}

    touch /boot/initramfs-linux.img

    mkdir -p /home
    mkdir -p /var
    mkdir -p /phantomos_root
    mkdir -p /efi
EOF

btrfs filesystem defragment -r ${BUILD_PATH}

cp -R rootfs/. ${BUILD_PATH}/

echo "${SYSTEM_NAME}-${VERSION}" > ${BUILD_PATH}/build_info
echo "" >> ${BUILD_PATH}/build_info
cat ${BUILD_PATH}/config >> ${BUILD_PATH}/build_info
rm ${BUILD_PATH}/config

if [ -z "${ARCHIVE_DATE}" ]; then
	export TODAY_DATE=$(date +%Y/%m/%d)
	echo "Server=https://archive.archlinux.org/repos/${TODAY_DATE}/\$repo/os/\$arch" > \
	${BUILD_PATH}/etc/pacman.d/mirrorlist
fi

btrfs subvolume snapshot -r ${BUILD_PATH} ${SNAP_PATH}
btrfs send -f ${SYSTEM_NAME}-${VERSION}.img ${SNAP_PATH}

cp ${BUILD_PATH}/build_info build_info.txt

umount -l ${BUILD_PATH}
umount -l ${MOUNT_PATH}
rm -rf ${MOUNT_PATH}
rm -rf ${BUILD_IMG}

IMG_FILENAME="${SYSTEM_NAME}-${VERSION}.img.tar.xz"
if [ -z "${NO_COMPRESS}" ]; then
	tar -c -I'xz -8 -T4' -f ${IMG_FILENAME} ${SYSTEM_NAME}-${VERSION}.img
    rm ${SYSTEM_NAME}-${VERSION}.img

    ARCHIVE_SIZE_MB=$(du -m "${IMG_FILENAME}" | cut -f1)

    if [ "${ARCHIVE_SIZE_MB}" -gt "${MAX_SIZE_MB}" ]; then
        echo "Archive is ${ARCHIVE_SIZE_MB} MB, splitting into parts..."
        split -d -b ${MAX_SIZE_MB}M "${IMG_FILENAME}" "${IMG_FILENAME}.part-"
        rm "${IMG_FILENAME}"
        sha256sum "${IMG_FILENAME}.part-"* > sha256sum.txt
    else
        sha256sum "${IMG_FILENAME}" > sha256sum.txt
    fi

    cat sha256sum.txt


	# Move the image to the output directory, if one was specified.
	if [ -n "${OUTPUT_DIR}" ]; then
		mkdir -p "${OUTPUT_DIR}"
		mv ${IMG_FILENAME} ${OUTPUT_DIR}
		mv build_info.txt ${OUTPUT_DIR}
		mv sha256sum.txt ${OUTPUT_DIR}
	fi

	# set outputs for github actions
	if [ -f "${GITHUB_OUTPUT}" ]; then
		echo "version=${VERSION}" >> "${GITHUB_OUTPUT}"
		echo "display_version=${DISPLAY_VERSION}" >> "${GITHUB_OUTPUT}"
		echo "display_name=${SYSTEM_DESC}" >> "${GITHUB_OUTPUT}"
		echo "image_filename=${IMG_FILENAME}" >> "${GITHUB_OUTPUT}"
	else
		echo "No github output file set"
	fi
else
	echo "Local build, output IMG directly"
	if [ -n "${OUTPUT_DIR}" ]; then
		mkdir -p "${OUTPUT_DIR}"
		mv ${SYSTEM_NAME}-${VERSION}.img ${OUTPUT_DIR}
	fi
fi