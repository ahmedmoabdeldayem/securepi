# Kernel hardening fragment (hardening, SELinux, dm-crypt/dm-verity, TPM).
# Without these two lines the kernel falls back to the stock defconfig (no SELinux,
# no DM_INIT). The check in do_configure below fails the build in that case.
FILESEXTRAPATHS:prepend := "${THISDIR}/files:"
SRC_URI:append = " file://securepi-hardening.cfg"

# linux-raspberrypi.inc hardcodes UBOOT_LOADADDRESS = 0x8000 (kernel TEXT_OFFSET).
# With the FIT image loaded at kernel_addr_r = 0x80000 (U-Boot default for RPi),
# the uncompressed kernel copy to 0x8000 triggers U-Boot's overlap safety check:
# "new format image overwritten" because [0x8000, 29.4MB] overlaps [0x80000, 30.5MB].
#
# Fix: set load/entry to 0x02000000 (32MB). FIT ends at ~30.5MB < 32MB, so the
# kernel destination [32MB, 62MB] does not overlap the FIT range [0.5MB, 30.5MB].
# 32MB is 2MB-aligned as required by the ARM64 boot protocol.
UBOOT_LOADADDRESS = "0x02000000"
UBOOT_ENTRYPOINT = "0x02000000"

# Fail the build if any option requested by the fragment did not make it into the
# final .config: Kconfig silently drops options with unmet dependencies, renamed
# symbols, or values overridden later. Every security option must be provably on.
do_configure:append() {
    FRAG="${WORKDIR}/securepi-hardening.cfg"
    [ -f "$FRAG" ] || bbfatal "securepi-hardening.cfg not in WORKDIR: fragment not in SRC_URI?"
    MISSING=""
    while read -r LINE; do
        case "$LINE" in
            CONFIG_*=n)
                SYM=${LINE%%=*}
                grep -q "^${SYM}=" "${B}/.config" && MISSING="$MISSING $LINE"
                ;;
            CONFIG_*=*)
                grep -qxF "$LINE" "${B}/.config" || MISSING="$MISSING $LINE"
                ;;
        esac
    done < "$FRAG"
    if [ -n "$MISSING" ]; then
        for M in $MISSING; do
            SYM=${M%%=*}
            bberror "fragment wants $M, .config has: $(grep -E "^${SYM}=|^# ${SYM} is not set" ${B}/.config || echo '(absent)')"
        done
        bbfatal "securepi-hardening.cfg options not applied: see errors above"
    fi
    bbnote "securepi-hardening.cfg: all options verified in .config"
}
