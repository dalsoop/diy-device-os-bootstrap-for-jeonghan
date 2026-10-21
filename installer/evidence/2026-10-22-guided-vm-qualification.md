# Guided VM qualification — 2026-10-22

## Scope

This repeats `2026-10-21-guided-vm-qualification.md` after the license and
redistribution policy merged (PR #9). It is the current burn candidate. As
before, there is one disposable QEMU (TCG) install per firmware from the
exact-size Ventoy raw image, with every guided answer typed into the real
installer dialogs. This is VM evidence only: it is not a physical write, HP
firmware boot, physical install or Secure Boot result.

- Source commit: `63cd0f4cc0a71311ed239fdfdfe8f3315135f2f6` (main `8998759` plus the license-checker fix; clean checkout, full guided build)
- Host: `m5m1` (QEMU q35, TCG, 2 vCPU, 2 GiB)
- ISO SHA-256: `5e9ff81cf5568ab0eeeec8925497a76fdc035a00a2b38a1a1e532a3f492aa963`
- Build manifest SHA-256: `757a15f43dc158d94c17f0ff89afc1190c02b44c54ea124d5c44a7595c76fe8b` (`source_revision` and `iso_sha256` match; `install_mode: guided`; `distribution_status: personal-use-only`)
- Raw image: 30,784,094,208 bytes, SHA-256 `53c6bff1fa92345264d8389cb8cc6090fc09d84942eb49f9a5ede01cdb29869d`
- Raw image license decision: `personal-use` / `allow`
- Build gates: all 45 installer target packages on the offline DVD; no installer glyph missing
- Public inputs: real operator SSH public key (`SHA256:qovlUmIoxKJLybPzlzhBz7lwjYbihLnHIrzIq3+BJuA`) and real age recipient
- Role: `dns01` (10.0.5.1/16, gateway 10.0.0.1)
- `secure_boot: off`

## Result

| Check | BIOS (SATA `DNS-VM-SATA`, `/dev/sda`) | UEFI (NVMe `DNS-VM-NVME`, `/dev/nvme0n1`) |
| --- | --- | --- |
| Guided install to completion | passed | passed |
| Internal-disk boot with USB attached | passed | passed |
| DNS over UDP (host-forwarded to 10.0.5.1:53) | passed (NXDOMAIN answer) | passed (NXDOMAIN answer) |
| DNS over TCP | passed | passed |
| `technitium-dns` and first boot | active; enrollment complete | active; enrollment complete |
| License, notices, source snapshot and distribution status in `/usr/share/doc/diy-device-os-bootstrap-for-jeonghan` | present | present |
| DNS-ENROLL after power-off (read-only) | `recovery.tar.age`, `public.json`, `COMPLETE`, `ACTIVE` | same |
| Plaintext secrets in enrollment output | none | none |

The only plaintext-scan match was the PAM log line "password changed for
dns-operator", which carries no value. As in the previous run, the BIOS VM was
restarted with the same USB overlay and the internal disk first, the
equivalent of choosing the disk in the HP boot menu.

## Defect found on the way

At main `8998759`, `world build-image` failed with "personal-use license
policy denied raw image creation". Every image builder and writer passes its
resolved catalog to `check-license-policy` in `USB_MEDIA_CATALOG`, and the
checker rejected any catalog outside `prebuilt-release`. The simulations used
mock checkers only. Fixed in `63cd0f4`.

## Remaining evidence gap

Burning and reading back the USB, HP BIOS and UEFI boot, physical install,
Secure Boot, and the second and third roles remain unverified.
