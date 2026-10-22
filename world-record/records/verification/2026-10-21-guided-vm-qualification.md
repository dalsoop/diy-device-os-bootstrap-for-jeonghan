# Guided VM qualification — 2026-10-21

## Scope

One disposable QEMU (TCG) install per firmware from the exact-size Ventoy raw
image that would be burned. Every guided answer (role, wired NIC, exact
`ERASE` phrase) was typed into the real installer dialogs. This is VM
evidence only: it is not a physical write, HP firmware boot, physical install
or Secure Boot result.

- Source commit: `0f0664e2bc1d2821bde6a5055c8c2ff1951b355c` (clean checkout, full guided build)
- Host: `m5m1` (QEMU q35, TCG, 2 vCPU, 2 GiB)
- ISO SHA-256: `d5d36a8966cbc794a01f86736c31e31f948a31b606065b6d1de3fb64f5beb1fd`
- Build manifest SHA-256: `1b10695509274d7856f7cdf72e507b2527a7d38fb3ae2194d33b67337bd9d893` (`source_revision` and `iso_sha256` match)
- Raw image: 30,784,094,208 bytes, SHA-256 `71dfca12be9e448e94c5734104de8feeb0ded14fda53f83b8be18e80e4e2e890`
- Build gates: all 45 installer target packages on the offline DVD; no installer glyph missing
- Public inputs: real operator SSH public key (`SHA256:qovlUmIoxKJLybPzlzhBz7lwjYbihLnHIrzIq3+BJuA`) and real age recipient; no private key on `m5m1`
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
| DNS-ENROLL after power-off (read-only) | `recovery.tar.age`, `public.json`, `COMPLETE`, `ACTIVE` | same |
| Plaintext secrets in enrollment output | none | none |

The only plaintext-scan match was the PAM log line "password changed for
dns-operator", which carries no value.

The BIOS VM keeps the USB first in its boot order, so after installation it
returned to the Ventoy menu. It was restarted with the same USB overlay and the
internal disk first, which is the equivalent of choosing the disk in the HP
boot menu. Ventoy's "첫 번째 로컬 디스크 부팅" entry left a blank screen in
this VM and is not a qualified path.

## Defects found and fixed on the way

1. `ea5a0a2`: the BIOS GRUB install failed because `dns.packages` installed the Secure Boot chain on every target (fixed in `6084f39`).
2. `ea5a0a2`: the appliance setup never ran because simple-cdd ran `dns.postinst` inside the target chroot (fixed in `f43a093`).
3. `f43a093`: grub-pc asked for the BIOS boot device because the USB was a second disk (fixed in `0f0664e`).

## Remaining evidence gap

Burning and reading back the USB, HP BIOS and UEFI boot, physical install,
Secure Boot, and the second and third roles remain unverified.
