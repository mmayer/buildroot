################################################################################
#
# lxc
#
################################################################################

LXC_VERSION = 5.0.1
LXC_SITE = https://linuxcontainers.org/downloads/lxc
LXC_LICENSE = GPL-2.0 (some tools), LGPL-2.1+
LXC_LICENSE_FILES = LICENSE.GPL2 LICENSE.LGPL2.1
LXC_CPE_ID_VENDOR = linuxcontainers
LXC_DEPENDENCIES = host-pkgconf
LXC_INSTALL_STAGING = YES

LXC_CONF_OPTS = \
	-Dapparmor=false \
	-Dexamples=false \
	-Dman=false

# Only apply patches to LXC >= 5
LXC_MAJOR_VER := $(word 1,$(subst ., ,$(LXC_VERSION)))
ifeq ($(shell test $(LXC_MAJOR_VER) -ge 5; echo $$?),0)
define LXC_BRCMSTB_PATCHES
	$(Q)PKGDIR=$(PKGDIR) \
		SOFTWARE_VERSION=$(LXC_VERSION) \
		SRCDIR=$(@D) \
		bin/apply_brcm_patches.sh
endef
LXC_PRE_PATCH_HOOKS += LXC_BRCMSTB_PATCHES
endif

ifeq ($(BR2_PACKAGE_BASH_COMPLETION),y)
LXC_DEPENDENCIES += bash-completion
endif

ifeq ($(BR2_PACKAGE_LIBCAP),y)
LXC_CONF_OPTS += -Dcapabilities=true
LXC_DEPENDENCIES += libcap
else
LXC_CONF_OPTS += -Dcapabilities=false
endif

ifeq ($(BR2_PACKAGE_LIBSECCOMP),y)
LXC_CONF_OPTS += -Dseccomp=true
LXC_DEPENDENCIES += libseccomp
else
LXC_CONF_OPTS += -Dseccomp=false
endif

ifeq ($(BR2_PACKAGE_LIBSELINUX),y)
LXC_CONF_OPTS += -Dselinux=true
LXC_DEPENDENCIES += libselinux
else
LXC_CONF_OPTS += -Dselinux=false
endif

ifeq ($(BR2_PACKAGE_LIBURING),y)
LXC_CONF_OPTS += -Dio-uring-event-loop=true
LXC_DEPENDENCIES += liburing
else
LXC_CONF_OPTS += -Dio-uring-event-loop=false
endif

ifeq ($(BR2_PACKAGE_LINUX_PAM),y)
LXC_CONF_OPTS += -Dpam-cgroup=true
LXC_DEPENDENCIES += linux-pam
else
LXC_CONF_OPTS += -Dpam-cgroup=false
endif

ifeq ($(BR2_PACKAGE_OPENSSL),y)
LXC_CONF_OPTS += -Dopenssl=true
LXC_DEPENDENCIES += openssl
else
LXC_CONF_OPTS += -Dopenssl=false
endif

ifeq ($(BR2_PACKAGE_SYSTEMD),y)
LXC_CONF_OPTS += -Dsd-bus=enabled
LXC_DEPENDENCIES += systemd
else
LXC_CONF_OPTS += -Dsd-bus=disabled
endif

ifeq ($(BR2_INIT_SYSTEMD),y)
LXC_CONF_OPTS += -Dinit-script=systemd
else ifeq ($(BR2_INIT_SYSV),y)
LXC_CONF_OPTS += -Dinit-script=sysvinit
else
LXC_CONF_OPTS += -Dinit-script=
endif

$(eval $(meson-package))
