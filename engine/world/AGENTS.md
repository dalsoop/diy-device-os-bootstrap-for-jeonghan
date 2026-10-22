# World Module

This module holds the World tools for Jeonghan's single accumulating home-infrastructure World. The World data itself lives in `world-record/`; this module reads it and publishes records into it. DNS is the first service represented in it; future device roles and media extend `jeonghan-home` rather than creating DNS-, storage-, or hypervisor-specific Worlds.

## Boundaries

- `bin/resolve-world` reads `world-record/world-playbook.yaml` and the drafts it registers, validates them, and emits declarative plans. Registered paths must stay inside `world-record/`. It never downloads images, invokes Catalog code, or writes a device.
- `bin/record-usb-event` serializes physical writes and publishes their records into `world-record/history/`. Its generation root equals the playbook's `generations.root`.
- `schemas/` owns the versioned published event and verification record shapes (schema version 2).
- `tests/` owns the World contract and USB event simulations.
- Configuration is not owned here: `world-record/world-playbook.yaml` registers the draft, the completed-generation root, timezone, and generation format, and `world-record/blueprint/home.yaml` owns assets, networks, nodes, services, media selection, language, and fail-closed intent.
- Records are not owned here either: `world-record/history/usb/` holds immutable completed physical USB generations, and `world-record/history/usb-failed/` holds append-only redacted records for failed or cancelled physical writes; successful event records live inside their generation.
- `world-record/private/` holds private files never committed (machine observations and public inputs); secrets and raw hardware inventory remain outside Git.
- Public release metadata belongs to the Catalog. Fetching, image assembly, target inspection, and erasure belong to the Installer.

## Invariants

- IDs are unique lowercase kebab-case values and every reference resolves exactly once.
- Static addresses are unique and belong to their network. A gateway is directly reachable or has an explicit route.
- `defaultMedia` names one declared media definition. A selected entry exists in the public Catalog or reviewed Installer-local registry.
- `inventory-capture` selects only `debian-live`; default `dns-install` selects only `dns-appliance` until an intentional World edit changes them.
- World intent never authorizes erasure. Every policy must retain exact hardware matching, one internal target disk, target-specific confirmation, and no automatic boot timeout.
- A DNS media selection retains guarded unattended policy; a non-DNS selection does not reserve the DNS enrollment partition.
- Completed generation IDs use `{YYYYMMDDHHmmss}-{world-slug}` in `Asia/Seoul`, captured at the physical USB creation event after sealing and before the target-specific write.
- Failed or cancelled writes never publish. Every verified physical rewrite creates a new generation, and an existing generation is never edited, renamed, reformatted, or overwritten.

## Change pattern

Edit `world-record/blueprint/home.yaml` for personal intent. Add reusable public release metadata to the Catalog and executable behavior to the Installer instead of duplicating either here. A World vocabulary change updates the resolver, Installer consumer, fixtures, and generation contract together.

The World event recorder serializes physical writes, keeps pending state under the ignored `world-record/private/usb-events/`, records unsuccessful attempts under `world-record/history/usb-failed/`, and atomically publishes successful readback evidence under `world-record/history/usb/`. Do not create either record from a plan, build, capacity query, or simulation.

## Verification

Run `engine/world/tests/world-contract-simulation.rb` and `engine/world/tests/usb-event-simulation.rb`, then exercise `./device-os world validate`, `available`, `plan`, `capacity`, and `simulate`. Cover unknown or duplicate IDs, missing references, duplicate addresses, unreachable gateways, invalid paths, unsupported language, invalid default media, weakened safety policy, failed writes, readback failure, and generation collisions. These checks prove source behavior only, not physical media creation.
