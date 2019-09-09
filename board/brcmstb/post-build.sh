#!/bin/sh

set -u
set -e

prg=`basename $0`

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

# Auto-login on serial console
if [ -e ${TARGET_DIR}/etc/inittab ]; then
	echo "Enabling auto-login on serial console..."
	sed -i 's|.* # GENERIC_SERIAL$|::respawn:/bin/cttyhack /bin/sh -l|' \
		${TARGET_DIR}/etc/inittab
fi

if ls board/brcmstb/dropbear_*_host_key >/dev/null 2>&1; then
	echo "Installing pre-generated SSH keys..."
	rm -rf ${TARGET_DIR}/etc/dropbear
	mkdir -p ${TARGET_DIR}/etc/dropbear
	for key in board/brcmstb/dropbear_*_host_key; do
		b=`basename "${key}"`
		echo "    ${b}"
		install -D -p -m 0600 -t ${TARGET_DIR}/etc/dropbear ${key}
	done
fi

# Enabling dropbear (rcS file inherited from the classic rootfs for now)
rcS="${TARGET_DIR}/etc/init.d/rcS"
if grep 'if [ -e /sbin/dropbear ]' "$rcS" >/dev/null; then
	echo "Enabling dropbear rcS..."
	sed -i 's| -e /sbin/dropbear | -e /usr/sbin/dropbear |' ${rcS}
fi

# Add SSH key for root
sshdir="${TARGET_DIR}/root/.ssh"
if [ -r board/brcmstb/brcmstb_root ]; then
	echo "Installing SSH key for root..."
	rm -rf "${sshdir}"
	mkdir "${sshdir}"
	chmod go= "${sshdir}"
	cp board/brcmstb/brcmstb_root.pub "${sshdir}/authorized_keys"
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

# Add ldd from the host's sysroot
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

# Check that shared libraries were installed properly
if [ -x bin/find_64bit_libs.sh ]; then
	echo "Checking that shared libraries were installed properly..."
	bin/find_64bit_libs.sh "${TARGET_DIR}"
fi

# Generate list of GPL-3.0 packages
echo "Generating GPL-3.0 packages list"
make -C ${BASE_DIR} legal-info
rm -rf ${TARGET_DIR}/usr/share/legal-info/
mkdir ${TARGET_DIR}/usr/share/legal-info/
grep "GPL-3.0" ${BASE_DIR}/legal-info/manifest.csv  | cut -d, -f1 > ${TARGET_DIR}/usr/share/legal-info/GPL-3.0-packages
sed -i 's| -e /bin/gdbserver -o -e /bin/gdb | -s /usr/share/legal-info/GPL-3.0-packages |' ${rcS}

# Copy directory structure from ${BASE_DIR}/files to the target
echo "Copying supplemental files"
if [ -d "${BASE_DIR}/files" ]; then
	cp -fpR ${BASE_DIR}/files/* ${TARGET_DIR}
fi
