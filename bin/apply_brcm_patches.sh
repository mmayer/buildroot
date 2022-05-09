#!/bin/sh
prg=`basename $0`

# This is a custom script to apply a series of patches. The script script will
# look for a patch directory that matches the full version number first. If it
# can't find such a directory, it will decrement the patch level version number
# (the 3rd number in the version string) and look for patch directories for
# preceeding sub-versions of the software. The assumption is that older patches
# will likely still apply between sub-versions.
#
# If it finds that patches exist for previous releases of the software, but not
# the current one, it returns with an error code. The intention is to abort the
# build, since the assumption must be that the patches haven't been ported yet
# (but need to be), and the user needs to alerted to that fact.
#
# The caller needs to set the environment variables:
#     * PKGDIR:           the location of the package directory
#                         (e.g. package/busybox)
#     * SOFTWARE_VERSION: the version of the software package
#                         (e.g. 1.35.0)
#     * SRCDIR:           the source directory where the patches need to be
#                         applied (e.g. output/arm64/build/busybox-1.35.0)
#
# The caller *may* set the environment variable:
#     * APPLY_PATCHES: path to Buildroot's apply-patches.sh; defaults to
#                     "support/scripts/apply-patches.sh"

die()
{
	echo "${prg}: $@" 1>&2
	exit 1
}

########################################
# MAIN
########################################

APPLY_PATCHES=${APPLY_PATCHES:-./support/scripts/apply-patches.sh}

test -z ${PKGDIR} && die '$PKGDIR is not set'
test -z ${SOFTWARE_VERSION} && die '$SOFTWARE_VERSION is not set'
test -z ${SRCDIR} && die '$SRCDIR is not set'

# Ensure PKGDIR ends with a slash. BR defines it this way, but if somebody calls
# this script manually...
if ! echo "${PKGDIR}" | grep '/$' >/dev/null; then
	PKGDIR="${PKGDIR}/"
fi

patch_dir="${PKGDIR}brcmstb-patches"
patch_prefix="${patch_dir}/v"
brcm_patches="${patch_prefix}${SOFTWARE_VERSION}"

if [ ! -d "${brcm_patches}" ]; then
	maj_ver=`echo "${SOFTWARE_VERSION}" | cut -d. -f1-2`
	patch_ver=`echo "${SOFTWARE_VERSION}" | cut -d. -f3`
	if [ "${patch_ver}" = "" ]; then
		# Hack, so that software packages that don't have 3-part version
		# numbers also work (e.g. util-linux-2.38 -> patch dir v2.38.0).
		patch_ver=0
		test -d "${brcm_patches}.0" && brcm_patches="${brcm_patches}.0"
	fi
	while [ ${patch_ver} -gt 0 ]; do
		patch_ver=`expr ${patch_ver} - 1`
		prev_ver=${maj_ver}.${patch_ver}
		brcm_patches="${patch_prefix}${prev_ver}"
		if [ -d "${brcm_patches}" ]; then
			break
		fi
	done
fi
if [ -d "${brcm_patches}" ]; then
	echo "Found patch dir ${brcm_patches}."
	echo "Calling ${APPLY_PATCHES} ${SRCDIR} \"${brcm_patches}\"..."
	${APPLY_PATCHES} ${SRCDIR} "${brcm_patches}" || exit $?
elif [ -d ${patch_dir} ]; then
	die "ERROR: couldn't find STB patches for release ${SOFTWARE_VERSION}!" 1>&2
fi

exit 0
