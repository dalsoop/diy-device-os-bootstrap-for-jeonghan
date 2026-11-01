# DNS Image Source

This directory contains the first implementation of the Debian OS installer:

- `fetch-locked-sources` verifies and caches the pinned Technitium OCI image and
  the static archives of the overlay clients the World selects (Tailscale with
  its dependency-license report, NetBird).
- `build-image` builds an offline amd64 image and release evidence on Debian 13.
  It embeds only the selected overlay clients and an `overlays` file, and
  `render-build-records` writes the SBOM, component registry, and build
  manifest for exactly that selection.
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
  health (with one status entry per selected overlay), backup, the firewall
  template and its `nftables.service` drop-in, NTP, SSH, Cockpit integration,
  the NetBird unit, and the unattended-upgrade configuration: deb822 Debian
  sources, the per-role `apt-daily-upgrade` timer and refresh drop-ins, the
  `dns-appliance-reboot` script, service, and timer, and the kernel postinst
  hook `dns-appliance-reboot-required` that writes `/run/reboot-required`.

The firewall is the single nftables table `inet dns_appliance`, rendered at
installation for the selected overlays; loading, reloading, and stopping it
never touch the overlay clients' tables. DNS and the management ports on
`tailscale0` and `wt0` are limited in its prerouting chain, which the NetBird
client's inserted `iifname "wt0" accept` cannot bypass; the overlay access
policy decides which peers reach them.

The generated image installs Debian, OpenSSH, Cockpit, nftables, Podman, a
digest-pinned Technitium image, the checksum-pinned overlay clients the World
selects, `unattended-upgrades`, and operational utilities without Internet
access. First boot generates credentials once, enables exactly the selected
overlay daemons, verifies services, and writes age-encrypted recovery secrets
plus plaintext `public.json`, sanitized logs, completion markers, and
generation pointers to `DNS-ENROLL`. Each overlay client remains unenrolled
until the management host supplies a one-off key after Internet connectivity is
available.

After installation, each node installs Debian updates at its role's time
(dns01 02:00, dns02 02:30, dns03 03:00 `Asia/Seoul`) and reboots one hour later
only when a reboot is required and every peer that has ever answered DNS still
answers. A reboot is required when a kernel package was installed since boot:
its postinst runs the appliance's hook in `/etc/kernel/postinst.d`, which
writes `/run/reboot-required` and names the package in
`/run/reboot-required.pkgs`. Skips are logged under the journal tag `dns-appliance-reboot` and
exported as `dns_appliance_reboot_*` node-exporter metrics.

See [`docs/os-install.md`](../docs/os-install.md) before building or booting it.
