#!/bin/sh

# $1 is the images directory. This is automatically passed in by BR.
# $2 is the Linux version. This is explicitly passed in via the BR config
#    option BR2_ROOTFS_POST_SCRIPT_ARGS

prg=`basename $0`

LINUX_STAMPS=".stamp_kconfig_fixup_done .stamp_built .stamp_target_installed"
LINUX_STAMPS="$LINUX_STAMPS .stamp_images_installed .stamp_initramfs_rebuilt"

# $1 is the images directory, the output directory is one level up.
output_path=`dirname "$1"`
linux_dir="linux-$2"
rootfs_cpio="$1/rootfs.cpio"

if [ $# -lt 2 ]; then
	echo "usage: $prg <image-path> <linux-version>"
	exit 1
fi

for s in $LINUX_STAMPS; do
	stamp="$output_path/build/$linux_dir/$s"
	if [ -r "$stamp" ]; then
		echo "Removing $stamp..."
		rm "$stamp"
	fi
done

if [ -r "$rootfs_cpio" ]; then
	echo "Removing rootfs_cpio..."
	rm "$rootfs_cpio"
fi
