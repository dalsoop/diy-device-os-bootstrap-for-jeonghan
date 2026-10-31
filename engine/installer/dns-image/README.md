# DNS Image Source

This directory contains the first implementation of the Debian OS installer:

- `fetch-locked-sources` verifies and caches the pinned Technitium OCI image and
  Tailscale static archive.
- `build-image` builds an offline amd64 image and release evidence on Debian 13.
- `write-usb-linux` writes the verified ISO and appends `DNS-ENROLL` after an
  exact destructive confirmation. It accepts only a build manifest whose
  `overlays`, overlay fields, components and SBOM agree, and its
  `installer.json` summary names the selected overlays with only their fields.
- `overlay-selection` resolves the World's overlay selection and compares it, as
  a set, with a build manifest's `overlays`. `check-readiness` reports any
  difference as a blocker, and `./device-os world build-image` and
  `world burn` refuse it before any image, target or USB event is touched.
- `capture-inventory` hashes the exact identity of one HP PC, NIC, and disk.
- `inventory-wizard` (`tools/dns-inventory` on the USB) asks for the role,
  wired interface, and internal disk by number, offers only install-gate
  candidates, and saves one `inventory-<role>.conf` on the inventory medium.
- `simple-cdd/` holds the unattended Debian Installer profile.
- `scripts/install-gate` refuses partitioning unless one inventory entry and one
  internal disk match exactly.
- `payload/` holds the Technitium container service, first-boot enrollment,
  health, backup, firewall, NTP, SSH, and Cockpit integration.

The generated image installs Debian, OpenSSH, Cockpit, nftables, Podman, a
digest-pinned Technitium image, a checksum-pinned Tailscale client, and
operational utilities without Internet access. First boot generates credentials
once, verifies services, and writes age-encrypted recovery secrets plus plaintext
`public.json`, sanitized logs, completion markers, and generation pointers to
`DNS-ENROLL`. Tailscale remains logged out until the management host supplies
a one-off key after Internet connectivity is available.

See [`docs/os-install.md`](../docs/os-install.md) before building or booting it.
