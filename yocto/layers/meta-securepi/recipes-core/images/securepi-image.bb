# SecurePi image recipe: hardened Raspberry Pi 5 image.
#
# Usage: bitbake securepi-image

require recipes-core/images/core-image-minimal.bb

SUMMARY = "Hardened embedded Linux image for the Raspberry Pi 5"

# ── Baseline: drop everything we don't need ──
IMAGE_FEATURES:remove = "debug-tweaks allow-root-login post-install-logging"

# ── System hardening ──
IMAGE_INSTALL:append = " sysctl-hardened sudo"
IMAGE_FEATURES:append = " read-only-rootfs"

inherit extrausers
EXTRA_USERS_PARAMS = "useradd -M -d /home/securepi -s /bin/sh -u 1000 \
    -p '\$6\$uU2.uEWhNmTHC/LL\$DsFzAJ/oPkwV7whTYe5boD0544Nou32My8sBsWNEVylrF1prt9Xy5jkqgcBMCecI85mVm/c9WRbndPQ7rS1Np.' \
    securepi;"

# ── SELinux (mandatory access control) ──
# Base refpolicy + SELinux tooling
IMAGE_INSTALL:append = " packagegroup-core-selinux"
# custom policy module: uncomment after writing policy from audit log
# IMAGE_INSTALL:append = " securepi-selinux-policy"

# ── Planned: Secure Storage ──
# IMAGE_INSTALL:append = " cryptsetup tpm2-tools tpm2-abrmd"

# ── Planned: Secure Boot ──
# IMAGE_INSTALL:append = " optee-client optee-os"

# Planned: OTA updates + network hardening
# IMAGE_INSTALL:append = " rauc nftables auditd aide"

IMAGE_INSTALL:append = " securepi-banner"
