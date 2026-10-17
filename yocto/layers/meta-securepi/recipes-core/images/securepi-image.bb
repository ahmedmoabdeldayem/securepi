# SecurePi image recipe: hardened Raspberry Pi 5 image.
#
# Usage: bitbake securepi-image

require recipes-core/images/core-image-minimal.bb

SUMMARY = "Hardened embedded Linux image for the Raspberry Pi 5"

# ── Baseline: drop everything we don't need ──
IMAGE_FEATURES:remove = "debug-tweaks allow-root-login post-install-logging"

# ── Planned: Kernel & System Hardening ──
# IMAGE_INSTALL:append = " kernel-module-configs sysctl-hardened"

# ── Planned: MAC Policies ──
# IMAGE_INSTALL:append = " packagegroup-core-selinux securepi-selinux-policy"
# IMAGE_FEATURES:append = " selinux"

# ── Planned: Secure Storage ──
# IMAGE_INSTALL:append = " cryptsetup tpm2-tools tpm2-abrmd"

# ── Planned: Secure Boot ──
# IMAGE_INSTALL:append = " optee-client optee-os"

# Planned: OTA updates + network hardening
# IMAGE_INSTALL:append = " rauc nftables auditd aide"

# Always include these minimal security tools
IMAGE_INSTALL:append = " \
    openssh \
    openssh-sftp-server \
"

# Disable root SSH login: use a dedicated user
# (configured via recipes-core/base-files bbappend)
