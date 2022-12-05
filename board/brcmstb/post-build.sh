#!/bin/sh

set -u
set -e

prg=`basename $0`
board_dir=`dirname $0`
custom_files="${BASE_DIR}/files"
custom_script="${BASE_DIR}/scripts/${prg}"

image_path="$1"
# The output directory is one level up from the image directory.
output_path=`dirname "$image_path"`
dot_config="${output_path}/.config"
local_config="${output_path}/local.mk"
mkpasswd="${output_path}/host/bin/mkpasswd"

# References a file used by systemd
serial_getty="${TARGET_DIR}/lib/systemd/system/serial-getty@.service"

# Default password for root
DEFAULT_PASSWD='bcm5F:4E:3D:2C:1B:0A'

# Clean up; some files we don't need are installed by default
rm -f ${TARGET_DIR}/etc/init.d/rcK \
	${TARGET_DIR}/etc/init.d/S[0-9]*

# Tweak some default settings
sed -i 's|$(cat $DT_DIR|$(tr -d "\\0" <$DT_DIR|' \
	${TARGET_DIR}/etc/config/ifup.default

if [ ! -e ${TARGET_DIR}/bin/sh ]; then
	echo "Symlinking /bin/bash -> /bin/sh..."
	ln -s bash ${TARGET_DIR}/bin/sh
fi

if ! grep /bin/sh ${TARGET_DIR}/etc/shells >/dev/null; then
	echo "Adding /bin/sh to /etc/shells..."
	echo "/bin/sh" >>${TARGET_DIR}/etc/shells
fi

# Set default password for root
encrypted_passwd="`echo $DEFAULT_PASSWD | $mkpasswd -s5`"
# Using '%' as separator as that doesn't seem to occur in the encoded strings
sed -i "s%^root::%root:$encrypted_passwd:%" ${TARGET_DIR}/etc/shadow

# Auto-login on serial console for classic sysvinit
if [ -e ${TARGET_DIR}/etc/inittab ]; then
	echo "Enabling auto-login on serial console..."
	sed -i 's|.* # GENERIC_SERIAL$|::respawn:/bin/cttyhack /bin/sh -l|' \
		${TARGET_DIR}/etc/inittab
fi

# Auto-login on serial console for systemd
if [ -e ${serial_getty} ]; then
	sed -i 's|^ExecStart=-/sbin/agetty|& --autologin root|' ${serial_getty}
fi

if ls ${board_dir}/dropbear_*_host_key >/dev/null 2>&1; then
	echo "Installing pre-generated SSH keys..."
	rm -rf ${TARGET_DIR}/etc/dropbear
	mkdir -p ${TARGET_DIR}/etc/dropbear
	for key in ${board_dir}/dropbear_*_host_key; do
		b=`basename "${key}"`
		echo "    ${b}"
		install -D -p -m 0600 -t ${TARGET_DIR}/etc/dropbear ${key}
	done
fi

# Add SSH key for root
sshdir="${TARGET_DIR}/root/.ssh"
if [ -r ${board_dir}/brcmstb_root ]; then
	echo "Installing SSH key for root..."
	rm -rf "${sshdir}"
	mkdir "${sshdir}"
	chmod go= "${sshdir}"
	cp ${board_dir}/brcmstb_root.pub "${sshdir}/authorized_keys"
fi

# Create mount points
echo "Creating mount points..."
rm -r ${TARGET_DIR}/mnt
mkdir ${TARGET_DIR}/mnt
for d in flash hd nfs usb; do
	mkdir ${TARGET_DIR}/mnt/${d}
done

# Fixing symlinks in /var
echo "Turning some /var symlinks into directories..."
for d in `find ${TARGET_DIR}/var -type l`; do
	l=`readlink "$d"`
	# We don't want any symlinks into /tmp. They break the ability to
	# install into a FAT-formatted USB stick.
	if echo "$l" | grep '/tmp' >/dev/null; then
		rm -f "$d"
		mkdir "$d"
	fi
done

# Create /data
rm -rf ${TARGET_DIR}/data
mkdir ${TARGET_DIR}/data

# We don't want /etc/resolv.conf to be a symlink into /tmp, either
resolvconf="${TARGET_DIR}/etc/resolv.conf"
if [ -h "${resolvconf}" ]; then
	echo "Creating empty /etc/resolv.conf..."
	rm "${resolvconf}"
	touch "${resolvconf}"
fi

# Set up ldd in the root file system
set +e
musl_ldso=`ls ${TARGET_DIR}/lib/ld-musl-*.so* 2>/dev/null`
set -e

if [ "$musl_ldso" != "" ]; then
	musl_ld_base=`basename "${musl_ldso}"`
	echo "Creating ldd symlink for musl..."
	ln -snf "../../lib/${musl_ld_base}" "${TARGET_DIR}/usr/bin/ldd"
else
	echo "Copying ldd..."
	cp -p ${HOST_DIR}/*gnu*/sysroot/usr/bin/ldd ${TARGET_DIR}/usr/bin
	if grep '^RTLDLIST=/lib/ld-linux-aarch64' "${TARGET_DIR}/usr/bin/ldd" >/dev/null; then
		set +e
		ld32=`ls "${TARGET_DIR}/lib/"ld-linux-arm* 2>/dev/null`
		ld64=`ls "${TARGET_DIR}/lib/"ld-linux-aarch* 2>/dev/null`
		set -e
		if [ "${ld32}" = "" -o "${ld64}" = "" ]; then
			echo "Couldn't find shared library loader(s), not updating ldd!"
		else
			echo "Adding Aarch32 capabilities to ldd..."
			ld32="/lib/`basename ${ld32}`"
			ld64="/lib/`basename ${ld64}`"
			sed -i "s|^RTLDLIST=.*|RTLDLIST=\"${ld64} ${ld32}\"|" \
				"${TARGET_DIR}/usr/bin/ldd"
		fi
	fi
fi

# Generate brcmstb.conf
echo "Generating /etc/brcmstb.conf..."
arch=`basename ${BASE_DIR}`
# The Linux directory can be "linux-custom" or "linux-$tag". We also must ensure
# we don't pick up directories like "linux-tools" or "linux-firmware".
linux_dir=`ls -drt ${BUILD_DIR}/linux-* | egrep 'linux-(stb|custom)' | head -1`
linux_ver=`./bin/linuxver.sh $linux_dir`
cat >${TARGET_DIR}/etc/brcmstb.conf <<EOF
TFTPHOST=${TFTPHOST:=`hostname -f`}
TFTPPATH=${TFTPPATH:=$linux_ver}
PLAT=$arch
VERSION=$linux_ver
EOF

if grep 'BR2_NEED_LD_SO_CONF=y' "${dot_config}" >/dev/null; then
	if [ "$musl_ldso" != "" ]; then
		musl_arch=`echo "$musl_ld_base" | sed -e 's/ld-musl-\(.*\)\.so.*/\1/'`
		ld_musl_path="/etc/ld-musl-$musl_arch.path"
		echo "Setting up ${ld_musl_path}..."
		cp -p "${board_dir}/ld.so.conf" "${TARGET_DIR}${ld_musl_path}"
	else
		echo "Copying ${board_dir}/ld.so.conf..."
		cp -p "${board_dir}/ld.so.conf" ${TARGET_DIR}/etc
		echo "Copying ldconfig..."
		cp -p ${HOST_DIR}/*gnu*/sysroot/sbin/ldconfig ${TARGET_DIR}/sbin
		echo "Running host-ldconfig..."
		./bin/ldconfig -r ${TARGET_DIR}
	fi
fi

# BR_SKIP_LEGAL_INFO permits a developer to skip the "make legal-info" stage to
# shorten build time. This option is for development only and must not be used
# for release builds.
set +u
test -z ${BR_SKIP_LEGAL_INFO} && BR_SKIP_LEGAL_INFO=""
set -u
if [ "${BR_SKIP_LEGAL_INFO}" != "" ]; then
	echo "Not generating GPL-3.0 packages list per user request."
	echo "See environment variable \$BR_SKIP_LEGAL_INFO."
else
	# Generate list of GPL-3.0 packages
	echo "Generating GPL-3.0 packages list"
	make -C ${BASE_DIR} legal-info
	rm -rf ${TARGET_DIR}/usr/share/legal-info/
	mkdir ${TARGET_DIR}/usr/share/legal-info/
	grep "GPL-3.0" ${BASE_DIR}/legal-info/manifest.csv | \
		cut -d, -f1 \
			> ${TARGET_DIR}/usr/share/legal-info/GPL-3.0-packages
fi

# Copy directory structure from ${BASE_DIR}/files to the target
echo "Copying supplemental files..."
if [ -d "${custom_files}" ]; then
	rsync -a "${custom_files}/" "${TARGET_DIR}"
fi

# Checking for custom post-build script
if [ -x "${custom_script}" ]; then
	echo "Executing ${custom_script}..."
	"${custom_script}" "$@"
fi

# The diff command below may return an error code. We don't want to abort the
# script if that happens. We want to handle the error case ourselves.
set +e

# Check if start-up files somehow got overwritten. It should never happen, but
# we want to know at build time if it ever does.
SKEL_VERSION=`grep default package/brcm-pm/Config.in | awk '{print $2}'`
SKEL_PATH=`dirname ${TARGET_DIR}`/build/brcm-skel-${SKEL_VERSION}

# Run this test only if no custom skeleton is configured.
if ! grep '^BRCM_SKEL_OVERRIDE_SRCDIR[[:space:]]*=' ${local_config} >/dev/null; then
	echo "Performing consistency check..."
	init_diff=`diff -u ${TARGET_DIR}/etc/inittab ${SKEL_PATH}/skel/etc/inittab`
	if [ $? != 0 ]; then
		echo "Detected a potential problem with the start-up files."
		echo "It is recommended to remove the output/<arch> directory and"
		echo "rebuild from scratch."
		echo "$init_diff"
		exit 1
	fi
fi
