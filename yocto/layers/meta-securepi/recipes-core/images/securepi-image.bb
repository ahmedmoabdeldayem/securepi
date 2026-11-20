# SecurePi image recipe: hardened Raspberry Pi 5 image.
#
# Usage: bitbake securepi-image

require recipes-core/images/core-image-minimal.bb

# Run setfiles at image creation time to label every file in the rootfs.
# Falls back to /.autorelabel (first-boot relabel) if setfiles fails.
inherit selinux-image

# Our own layout: rootfs partition is the dm-verity image (data + hash tree).
# .wks.in so ${IMGDEPLOYDIR}/${IMAGE_LINK_NAME} are expanded by bitbake.
WKS_FILE = "securepi.wks.in"

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
# Custom policy module (securepi.te)
IMAGE_INSTALL:append = " securepi-selinux-policy"
# Example confined service
IMAGE_INSTALL:append = " securepi-logger"

# Load custom .pp modules into the policy store after packages are installed
# but BEFORE selinux-image.bbclass runs setfiles, so our file_contexts are
# included in the labeling pass.
#
# Why not semodule -p $D directly?
# semodule reads semanage.conf from $D/etc/selinux/ which points to the target's
# (ARM) HLL pp binary.  Running an ARM binary on the x86 build host fails.
# Instead we mirror what refpolicy_common.inc does: use the NATIVE pp binary to
# convert .pp → CIL ourselves, place CIL in the store, then call semodule -n -B
# with a temporary semanage.conf pointing to native tools for the final compile.
do_rootfs[depends] += "policycoreutils-native:do_populate_sysroot bzip2-replacement-native:do_populate_sysroot"

selinux_load_modules() {
    STORE=${IMAGE_ROOTFS}/var/lib/selinux/targeted/active/modules/100
    HLL_BIN=${STAGING_DIR_NATIVE}${prefix}/libexec/selinux/hll/pp
    SEMANAGE=${IMAGE_ROOTFS}/etc/selinux/semanage.conf

    if [ ! -d "$STORE" ]; then
        echo "WARNING: SELinux module store not found at $STORE. Skipping"
        return 0
    fi
    if [ ! -x "$HLL_BIN" ]; then
        echo "WARNING: native pp binary not found at $HLL_BIN. Skipping"
        return 0
    fi

    for pp in ${IMAGE_ROOTFS}/usr/share/selinux/targeted/securepi*.pp; do
        [ -f "$pp" ] || continue
        MOD_NAME=$(basename "$pp" .pp)
        MOD_DIR="$STORE/$MOD_NAME"
        mkdir -p "$MOD_DIR"
        printf '%s' 'cil' > "$MOD_DIR/lang_ext"
        "$HLL_BIN" "$pp" > "$MOD_DIR/cil" \
            || { echo "WARNING: HLL conversion failed for $pp"; continue; }
        cp "$pp" "$MOD_DIR/hll"
        echo "Added module to store: $MOD_NAME"
    done

    # Rebuild the compiled policy binary.  Temporarily replace semanage.conf so
    # libsemanage uses native setfiles / sefcontext_compile, not the ARM copies.
    cp "$SEMANAGE" "${SEMANAGE}.bak"
    {
        echo 'module-store = direct'
        echo '[setfiles]'
        echo "path = ${STAGING_DIR_NATIVE}${base_sbindir_native}/setfiles"
        echo 'args = -q -c $@ $<'
        echo '[end]'
        echo '[sefcontext_compile]'
        echo "path = ${STAGING_DIR_NATIVE}${sbindir_native}/sefcontext_compile"
        echo 'args = $@'
        echo '[end]'
        echo ''
        echo 'policy-version = 33'
        echo 'store-root = "/var/lib/selinux"'
    } > "$SEMANAGE"
    # Capture stderr: libsemanage emits "Error while fetching users" when the
    # rootfs has no home dirs, which is harmless but trips Yocto's log_check.
    SMOD_OUT=$(semodule -n -s targeted -B -p ${IMAGE_ROOTFS} 2>&1)
    SMOD_RC=$?
    if [ $SMOD_RC -ne 0 ]; then
        echo "WARNING: semodule policy rebuild failed"
        echo "$SMOD_OUT"
    fi
    mv "${SEMANAGE}.bak" "$SEMANAGE"
}
ROOTFS_POSTPROCESS_COMMAND += "selinux_load_modules; "

# ── Secure storage ──
# LUKS + dm-verity tooling
IMAGE_INSTALL:append = " cryptsetup e2fsprogs-mke2fs"
# TPM 2.0 tooling. No tpm2-abrmd: the in-kernel resource manager
# (/dev/tpmrm0) does the same job, so a root D-Bus daemon would only add attack
# surface. PACKAGE_EXCLUDE fails the build if anything ever pulls it back in.
IMAGE_INSTALL:append = " tpm2-tools libtss2-tcti-device kernel-modules"
PACKAGE_EXCLUDE += "tpm2-abrmd"
# TPM-backed LUKS auto-unlock service
IMAGE_INSTALL:append = " tpm-luks-unlock"

# ── Secure boot ──
# EEPROM signing + OTP provisioning tools
IMAGE_INSTALL:append = " rpi-eeprom raspi-utils flashrom"
# Planned: OP-TEE trusted execution environment (requires meta-arm in kas.yml)
# IMAGE_INSTALL:append = " optee-client optee-os"

# Planned: OTA updates + network hardening
# IMAGE_INSTALL:append = " rauc nftables auditd aide"

IMAGE_INSTALL:append = " securepi-banner"

# /etc/fstab ends up unlabeled after the image build: setfiles appears to run
# before some late step recreates the file. Use setfattr to stamp the xattr
# directly; this bypasses the setfiles policy chain entirely.
# attr-native provides setfattr; do_image dependency makes it available here.
do_image[depends] += "attr-native:do_populate_sysroot"
do_image_wic[depends] += "tpm-overlay:do_deploy"
do_image_wic[depends] += "securepi-bootimg:do_deploy"

selinux_label_fstab() {
    if [ -f "${IMAGE_ROOTFS}/etc/fstab" ]; then
        setfattr -n security.selinux \
            -v "system_u:object_r:etc_t:s0" \
            "${IMAGE_ROOTFS}/etc/fstab" || \
            echo "WARNING: setfattr on fstab failed"
    fi
}
IMAGE_PREPROCESS_COMMAND:append = " selinux_label_fstab; "

# Session-wide environment, set by pam_env (login: "session pam_env.so readenv=1")
# from /etc/environment, independent of the shell. /etc/profile.d does NOT work
# here: meta-selinux replaces busybox applet links with "#!/usr/bin/busybox"
# wrapper scripts, so login's "-sh" loses its dash and the shell is never a login
# shell (never reads /etc/profile). sudo keeps both via env_keep (securepi-sudo).
#   DM_DISABLE_UDEV: mdev never posts the dm udev semaphore, so cryptsetup and
#     veritysetup would hang forever waiting for it.
#   TPM2TOOLS_TCTI: tpm2-tools talk straight to the in-kernel resource manager.
# Appended after install because /etc/environment is owned by pam-plugin-env.
securepi_environment() {
    printf '%s\n' 'DM_DISABLE_UDEV=1' 'TPM2TOOLS_TCTI=device:/dev/tpmrm0' \
        >> ${IMAGE_ROOTFS}${sysconfdir}/environment
}
ROOTFS_POSTPROCESS_COMMAND += "securepi_environment; "
