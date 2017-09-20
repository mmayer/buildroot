#!/bin/sh

set -u
set -e

# Auto-login on serial console
if [ -e ${TARGET_DIR}/etc/inittab ]; then
	echo "Enabling auto-login on serial console..."
	sed -i 's|.* # GENERIC_SERIAL$|::respawn:/bin/cttyhack /bin/sh -l|' \
		${TARGET_DIR}/etc/inittab
fi
