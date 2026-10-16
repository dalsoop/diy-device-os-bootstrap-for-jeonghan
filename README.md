# Device OS Bootstrap for Jeonghan

[![CI](https://github.com/dalsoop/device-os-bootstrap-for-jeonghan/actions/workflows/ci.yml/badge.svg)](https://github.com/dalsoop/device-os-bootstrap-for-jeonghan/actions/workflows/ci.yml)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)

This repository is Jeonghan's personal device-OS World: it accumulates device
intent, installation media, and immutable physical USB generations over time.
The first deployment is a three-node home DNS cluster. This is a
history-preserving derivative of
[`dalsoop/diy-device-os-bootstrap`](https://github.com/dalsoop/diy-device-os-bootstrap),
the generic upstream, with one operator-owned World.

The default `dns-install` media contains only the guarded DNS appliance image.
The separate `inventory-capture` media contains only Debian Live for collecting
hardware identity before any unattended installation is enabled. Proxmox,
TrueNAS, and desktop images remain available as Catalog metadata for upstream
compatibility, but the current media selections do not download or stage them.

> Current assurance: contracts and isolated simulations run in CI. A successful
> CI run does not prove a physical USB, firmware boot, internal-disk install, or
> network cutover. Each remains a separate verification gate.

## Start here

```sh
git clone https://github.com/dalsoop/device-os-bootstrap-for-jeonghan.git
cd device-os-bootstrap-for-jeonghan
./device-os world validate
./device-os world plan
./device-os world capacity --capacity 16GB
./device-os world simulate
```

The operator normally changes only
[`world/drafts/jeonghan-home/world.yaml`](world/drafts/jeonghan-home/world.yaml).
It defines `dns01`, `dns02`, and `dns03` at `10.0.5.1` through `10.0.5.3`, with
the router at `10.0.0.1`. Hardware observations, keys, generated media,
credentials, and recovery material stay outside Git in the documented ignored
locations or the principal secret store.

## Build and burn flow

1. Boot `inventory-capture` and collect each HP machine's exact hardware data.
2. Review the local inventories and enable one machine at a time.
3. On an amd64 Debian 13 builder, build the offline Korean DNS installer ISO.
4. Check capacity with the exact ISO and its build manifest.
5. On Linux, burn the confirmed removable USB.
6. Verify the USB, boot one machine, and complete all physical gates before
   enabling the next machine.

The destructive command is intentionally explicit:

```sh
sudo ./device-os world burn \
  --device /dev/sdX \
  --runtime-artifact dns-appliance=/absolute/path/dns-appliance.iso \
  --runtime-manifest dns-appliance=/absolute/path/build-manifest.json \
  --confirm 'ERASE /dev/sdX USB_SERIAL'
```

Resolve the current device path and serial immediately before every burn. The
writer rejects a non-removable device, the root disk, a missing serial,
insufficient capacity, an unverified artifact, or an inexact confirmation.

macOS can validate, plan, simulate, and write a prebuilt exact-size MBR raw
image with `burn-image-macos`. Complete Ventoy assembly and DNS ISO construction
currently require Linux; the repository does not yet build that macOS-ready raw
image.

## Repository map

```text
device-os-bootstrap-for-jeonghan/
├── device-os              operator command
├── world/                 home intent and append-only USB generations
├── catalog/               data-only public OS and bootloader metadata
├── installer/             builders, media assembly, and destructive gates
├── agent/                 constrained management-host MCP access plane
└── docs/                  architecture, workflow, and decisions
```

- `world/` owns operator intent, not erasure authority.
- `catalog/` owns public metadata and executes nothing.
- `installer/` validates all inputs and live targets before writing.
- `agent/` exposes planning and reviewed DNS operations, never USB burn or OS
  installation.

Each verified physical USB creation publishes an immutable World
generation named `{YYYYMMDDHHmmss}-{world-slug}`. The timestamp is the USB
creation event in `Asia/Seoul`, not draft or commit time. Failed or cancelled
physical attempts are recorded separately under `world/events/`; simulations
do not create physical evidence.

## Documentation

- [Getting started](docs/getting-started.md)
- [Architecture](docs/architecture.md)
- [Business rules](docs/business-rules.md)
- [Security](docs/security.md)
- [Engineering standards](docs/standards.md)
- [Engineering notes](docs/engineering-notes.md)
- [Operations](docs/operations.md)
- [External contracts](docs/contracts.md)
- [Implementation status](docs/tracking/status.md)
- [Open findings](docs/tracking/findings.md)
- [Decision history](docs/tracking/decisions/index.md)
- [DNS install usability audit](installer/docs/dns-install-usability-audit.md)
- [Physical verification gates](installer/docs/verification.md)
- [Agent Gateway](agent/README.md)

## Upstream updates

The local `upstream` remote should point to the generic source repository:

```sh
git remote add upstream https://github.com/dalsoop/diy-device-os-bootstrap.git
git fetch upstream
```

Review upstream changes to Catalog data, installation gates, media writers, and
safety policy before selectively merging or cherry-picking them. Extend the
existing World with new devices and media; do not weaken target checks.

## License

Except where a file-specific or upstream notice states otherwise, original
content is licensed under GPL-3.0-only. Third-party operating systems,
bootloaders, packages, and container images retain their upstream terms. See
[LICENSE_HISTORY.md](LICENSE_HISTORY.md) and
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
