################################################################################
#
# linux-tools
#
################################################################################

# Vampirising sources from the kernel tree, so no source nor site specified.
# Instead, we directly build in the sources of the linux package. We can do
# that, because we're not building in the same location and the same files.
#
# So, all tools refer to $(LINUX_DIR) instead of $(@D).

# Note: we need individual tools .mk files to be included *before* this one
# to guarantee that each tool has a chance to register itself before we build
# the list of build and install hooks, below.
#
# This is ensured by the main buildroot makefile, which explicitly includes
# linux-tools.mk after all linux-tool*.mk makefiles. Look for LINUX_TOOLS_MK
# in the top-level makefile to see where this is happening.

# We only need the kernel to be extracted, not actually built
LINUX_TOOLS_PATCH_DEPENDENCIES = linux

# Install Linux kernel tools in the staging directory since some tools
# may install shared libraries and headers (e.g. cpupower).
LINUX_TOOLS_INSTALL_STAGING = YES

LINUX_TOOLS_DEPENDENCIES += $(foreach tool,$(LINUX_TOOLS),\
	$(if $(BR2_PACKAGE_LINUX_TOOLS_$(call UPPERCASE,$(tool))),\
		$($(call UPPERCASE,$(tool))_DEPENDENCIES)))

LINUX_TOOLS_POST_BUILD_HOOKS += $(foreach tool,$(LINUX_TOOLS),\
	$(if $(BR2_PACKAGE_LINUX_TOOLS_$(call UPPERCASE,$(tool))),\
		$(call UPPERCASE,$(tool))_BUILD_CMDS))

LINUX_TOOLS_POST_INSTALL_STAGING_HOOKS += $(foreach tool,$(LINUX_TOOLS),\
	$(if $(BR2_PACKAGE_LINUX_TOOLS_$(call UPPERCASE,$(tool))),\
		$(call UPPERCASE,$(tool))_INSTALL_STAGING_CMDS))

LINUX_TOOLS_POST_INSTALL_TARGET_HOOKS += $(foreach tool,$(LINUX_TOOLS),\
	$(if $(BR2_PACKAGE_LINUX_TOOLS_$(call UPPERCASE,$(tool))),\
		$(call UPPERCASE,$(tool))_INSTALL_TARGET_CMDS))

$(eval $(generic-package))
