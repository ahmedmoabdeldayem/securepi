# Security Policy

SecurePi is a reference implementation of a hardened Linux stack for the
Raspberry Pi 5 (secure boot, dm-verity, LUKS with a TPM-sealed key, SELinux,
kernel hardening). It is not a finished product. Read the notes below before you
build anything you rely on.

## Reporting a vulnerability

For a problem in this project's own code (the `meta-securepi` layer and the
docs), open a GitHub issue, or use private vulnerability reporting ("Report a
vulnerability" on the Security tab) for anything sensitive. Please don't post
working exploits in public issues.

Problems in upstream components (Linux, U-Boot, BusyBox, systemd, cryptsetup,
the tpm2 stack and so on) should go to those projects. Use `cve-check` and an
SBOM to track them for your own builds.

## Defaults you must change before real use

These defaults make the image usable out of the box. They are fine on a test
bench and not fine on a deployed or networked device.

| Default | Where | What to do |
|---|---|---|
| Console password `123` for the `securepi` user | `recipes-core/images/securepi-image.bb` | Replace the `-p '$6$...'` hash with your own (`openssl passwd -6`). The root filesystem is read-only, so the password is fixed at build time, and every build that uses the shipped hash has the same password. |
| Passwordless `sudo` for `securepi` | `recipes-extended/sudo/files/securepi-sudo` | Together with the default password this gives root to anyone on the serial console. Remove `NOPASSWD` once you have your own password. |
| Example signing keys | `keys/` | The committed `.crt` files are example public certificates. Create your own keys for FIT, EEPROM and `boot.img` signing (see Getting started in the [README](README.md)). Private keys are git-ignored and are not in this repository. |

## OTP is permanent

Enabling secure boot writes a public key hash into the Pi's one-time
programmable fuses. This cannot be undone, and a mistake with the signing key
can permanently brick a locked board. Understand the whole secure boot chain and
practice on a board you can afford to lose before enabling OTP locking.

## Scope

Features marked Done in the README are implemented and were tested on hardware.
Features marked In progress or Planned (OP-TEE, RAUC updates, nftables, mTLS
telemetry) are not implemented and give no protection. The README also lists the
known gaps in the current image, for example that the kernel still allows
`setenforce 0` and does not yet refuse unsigned modules. The TPM bus encryption
protects against a passive sniffer only, not against an active device placed
between the SoC and the TPM.
