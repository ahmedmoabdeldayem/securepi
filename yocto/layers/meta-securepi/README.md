# meta-securepi

Yocto layer and `securepi` distro for a hardened Raspberry Pi 5 image. See the
[top-level README](../../../README.md) for the security design and what each part
protects against.

## Dependencies

| Layer | URI | Branch |
|---|---|---|
| meta, meta-poky | https://git.yoctoproject.org/poky | scarthgap |
| meta-raspberrypi | https://github.com/agherzan/meta-raspberrypi | scarthgap |
| meta-lts-mixins | https://git.yoctoproject.org/meta-lts-mixins | scarthgap/u-boot |
| meta-oe, meta-python, meta-networking, meta-filesystems | https://github.com/openembedded/meta-openembedded | scarthgap |
| meta-selinux | https://git.yoctoproject.org/meta-selinux | scarthgap |
| meta-security, meta-tpm | https://git.yoctoproject.org/meta-security | scarthgap |

The build also clones https://github.com/raspberrypi/usbboot (branch `master`).
It is not a layer; the EEPROM recipe uses it to produce the rpiboot recovery and
test sets.

meta-lts-mixins is needed because the U-Boot in Scarthgap cannot read the DRAM
size on the BCM2712.

## Adding the layer

The supported way to build is with kas from the repository root:

```
kas build kas.yml
```

To use the layer in another build, add it and its dependencies to
`bblayers.conf` and set:

```
MACHINE = "raspberrypi5"
DISTRO = "securepi"
```

The secure boot parts expect signing keys under `keys/` at the repository root
(`UBOOT_SIGN_KEYDIR`, `EEPROM_SIGN_KEYDIR` and `BOOT_IMG_SIGN_KEYDIR` in
`securepi.conf`). Only public certificates are committed. See Getting
started in the [top-level README](../../../README.md) for how to create your own keys.

## Contents

```
conf/
  layer.conf
  distro/securepi.conf            Distro policy: secure boot, dm-verity, SELinux, TPM, compiler flags
recipes-bsp/
  bootfiles/                      Signed bootcode for the BCM2712 boot ROM
  rpi-eeprom/                     Signed EEPROM firmware and rpiboot sets
  securepi-bootimg/               Signed boot.img with the dm-verity table in cmdline.txt
  tpm-overlay/                    Device tree overlay for the SPI TPM
  u-boot/                         FIT signature enforcement
  u-boot-default-script/          boot.scr that loads the key-bearing control DTB
recipes-core/
  images/securepi-image.bb        The image
  base-files/                     Removes /etc/issue and /etc/issue.net (the banner recipe provides /etc/issue)
  busybox/                        No SUID binary, sandboxed syslog
  securepi-tools/                 Login banner
  sysctl-hardened/                Runtime kernel and network settings
  systemd/, volatile-binds/       Read-only rootfs support
recipes-devtools/python/          python3-pycryptodomex, used to sign the EEPROM
recipes-extended/sudo/            sudoers policy
recipes-kernel/linux/             Kernel hardening fragment
recipes-security/
  selinux-policy/                 SELinux module (securepi.te)
  tpm-measure/                    TPM reset and measured boot into PCR 8
  tpm-luks/                       TPM-sealed LUKS2 provisioning and unlock
recipes-securepi/securepi-logger/ Example service confined to its own SELinux domain
wic/securepi.wks.in               Partitions: boot, dm-verity root, LUKS data
```

## Contributing and license

See the [top-level README](../../../README.md#contributing-and-license). The layer is MIT licensed
([LICENSE](../../../LICENSE)).
