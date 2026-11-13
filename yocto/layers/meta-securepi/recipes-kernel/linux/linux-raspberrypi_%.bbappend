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
