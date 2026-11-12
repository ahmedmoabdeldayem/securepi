# Remove the default /etc/issue and /etc/issue.net. securepi-banner provides /etc/issue.
do_install:append() {
    rm -f ${D}${sysconfdir}/issue
    rm -f ${D}${sysconfdir}/issue.net

    # cryptsetup/veritysetup are compiled with udev sync support but mdev on this
    # minimal image doesn't post the dm uevent semaphore, causing all dm operations
    # to hang indefinitely. DM_DISABLE_UDEV=1 bypasses the semaphore wait.
    install -d ${D}${sysconfdir}/profile.d
    echo 'export DM_DISABLE_UDEV=1' > ${D}${sysconfdir}/profile.d/dm-no-udev.sh

}
