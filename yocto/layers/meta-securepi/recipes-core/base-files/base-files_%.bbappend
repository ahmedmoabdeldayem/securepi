# Remove the default /etc/issue and /etc/issue.net. securepi-banner provides /etc/issue.
do_install:append() {
    rm -f ${D}${sysconfdir}/issue
    rm -f ${D}${sysconfdir}/issue.net
}
