#!/bin/sh

set -u
set -e

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
