################################################################################
#
# brcm-pm
#
################################################################################

BRCMROOT_VERSION = ade027685bb7957ce1c381cc53c0b7e23462c572

BRCM_PM_VERSION = master
BRCM_PM_SITE = git://stbgit.broadcom.com/mm940762/uclinux-rootfs.git
BRCM_PM_SOURCE = uclinux-rootfs-$(BRCMROOT_VERSION).tar.gz
BRCM_PM_DIR = uclinux-rootfs
BRCM_PM_LICENSE = GPL-2.0
BRCM_PM_LICENSE_FILES = COPYING

# Extract only what we need to save space.
define BRCM_PM_EXTRACT_CMDS
	$(call suitable-extractor,$(BRCM_PM_SOURCE)) \
		$(DL_DIR)/$(BRCM_PM_SOURCE) | \
		$(TAR) --strip-components=1 -C $(BRCM_PM_DIR) \
			--wildcards $(TAR_OPTIONS) - '*/user/brcm-pm'
endef

define BRCM_PM_BUILD_CMDS
	$(TARGET_MAKE_ENV) \
		$(MAKE) -C $(@D)/user/brcm-pm $(TARGET_CONFIGURE_OPTS)
endef

define BRCM_PM_INSTALL_TARGET_CMDS
	$(TARGET_MAKE_ENV) \
		$(MAKE) -C $(@D)/user/brcm-pm install DESTDIR=$(TARGET_DIR)
endef

$(eval $(generic-package))
