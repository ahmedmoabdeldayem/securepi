# Remove the default /etc/issue and /etc/issue.net. securepi-banner provides /etc/issue.
do_install:append() {
    rm -f ${D}${sysconfdir}/issue
    rm -f ${D}${sysconfdir}/issue.net

    # cryptsetup/veritysetup are compiled with udev sync support but mdev on this
    # minimal image doesn't post the dm uevent semaphore, causing all dm operations
    # to hang indefinitely. DM_DISABLE_UDEV=1 bypasses the semaphore wait.
    install -d ${D}${sysconfdir}/profile.d
    echo 'export DM_DISABLE_UDEV=1' > ${D}${sysconfdir}/profile.d/dm-no-udev.sh

    # tpm2-tools defaults to tpm2-abrmd over D-Bus; point every login shell at the
    # in-kernel resource manager instead. /etc/profile.d (sourced by /etc/profile)
    # is used because PAM's pam_env doesn't read /etc/environment on this image.
    echo 'export TPM2TOOLS_TCTI="device:/dev/tpmrm0"' > ${D}${sysconfdir}/profile.d/tpm2-tcti.sh

}
