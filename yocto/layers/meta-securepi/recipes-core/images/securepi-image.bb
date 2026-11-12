# SecurePi image recipe: hardened Raspberry Pi 5 image.
#
# Usage: bitbake securepi-image

require recipes-core/images/core-image-minimal.bb

# Run setfiles at image creation time to label every file in the rootfs.
# Falls back to /.autorelabel (first-boot relabel) if setfiles fails.
inherit selinux-image

# Use our own wks file so we can set --no-fstab-update on the rootfs partition.
WKS_FILE = "securepi.wks"

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
# TPM operations
IMAGE_INSTALL:append = " tpm2-tools tpm2-abrmd libtss2-tcti-device kernel-modules"
# TPM-backed LUKS auto-unlock service
IMAGE_INSTALL:append = " tpm-luks-unlock"

# ── Planned: Secure Boot ──
# IMAGE_INSTALL:append = " optee-client optee-os"

# Planned: OTA updates + network hardening
# IMAGE_INSTALL:append = " rauc nftables auditd aide"

IMAGE_INSTALL:append = " securepi-banner"

# /etc/fstab ends up unlabeled after the image build: setfiles appears to run
# before some late step recreates the file. Use setfattr to stamp the xattr
# directly; this bypasses the setfiles policy chain entirely.
# attr-native provides setfattr; do_image dependency makes it available here.
do_image[depends] += "attr-native:do_populate_sysroot"

selinux_label_fstab() {
    if [ -f "${IMAGE_ROOTFS}/etc/fstab" ]; then
        setfattr -n security.selinux \
            -v "system_u:object_r:etc_t:s0" \
            "${IMAGE_ROOTFS}/etc/fstab" || \
            echo "WARNING: setfattr on fstab failed"
    fi
}
IMAGE_PREPROCESS_COMMAND:append = " selinux_label_fstab; "

# Append TPM2 TCTI to /etc/environment after pam-plugin-env installs it,
# so all login shells have it without manually exporting each session.
append_tpm_tcti() {
    echo 'TPM2TOOLS_TCTI=device:/dev/tpmrm0' >> ${IMAGE_ROOTFS}/etc/environment
}
ROOTFS_POSTPROCESS_COMMAND += "append_tpm_tcti; "
