################################################################################
#
# tmon
#
################################################################################

LINUX_TOOLS += tmon

TMON_DEPENDENCIES = ncurses
TMON_MAKE_OPTS = $(LINUX_MAKE_FLAGS) \
	CC=$(TARGET_CC) \
	PKG_CONFIG_PATH=$(STAGING_DIR)/usr/lib/pkgconfig

define TMON_BUILD_CMDS
	$(Q)if ! grep install $(LINUX_DIR)/tools/thermal/tmon/Makefile >/dev/null 2>&1 ; then \
		echo "Your kernel version is too old and does not have the tmon tool." ; \
		echo "At least kernel 3.13 must be used." ; \
		exit 1 ; \
	fi
	$(TARGET_MAKE_ENV) $(MAKE) -C $(LINUX_DIR)/tools \
		$(TMON_MAKE_OPTS) \
		tmon
endef

define TMON_INSTALL_TARGET_CMDS
	$(TARGET_MAKE_ENV) $(MAKE) -C $(LINUX_DIR)/tools \
		$(TMON_MAKE_OPTS) \
		INSTALL_ROOT=$(TARGET_DIR) \
		tmon_install
endef
