# World Module

This module owns Jeonghan's single accumulating home-infrastructure World. DNS is the first service represented in it; future device roles and media extend `jeonghan-home` rather than creating DNS-, storage-, or hypervisor-specific Worlds.

## Boundaries

- `world-playbook.yaml` registers mutable draft paths, the completed-generation root, timezone, and generation format.
- `drafts/jeonghan-home/world.yaml` owns mutable assets, networks, nodes, services, media selection, language, and fail-closed intent.
- `worlds/` owns immutable completed physical USB generations.
- `events/` owns append-only redacted records for failed or cancelled physical writes; successful event records live inside their generation.
- `schemas/` owns the versioned event and verification record shapes.
- `local/` owns ignored machine-local observations and public inputs; secrets and raw hardware inventory remain outside Git.
- `bin/resolve-world` validates and emits declarative plans. It never downloads images, invokes Catalog code, or writes a device.
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

Edit the draft for personal intent. Add reusable public release metadata to the Catalog and executable behavior to the Installer instead of duplicating either here. A World vocabulary change updates the resolver, Installer consumer, fixtures, and generation contract together.

The World event recorder serializes physical writes, keeps pending state under ignored `local/`, records unsuccessful attempts under `events/`, and atomically publishes successful readback evidence under `worlds/`. Do not create either record from a plan, build, capacity query, or simulation.

## Verification

Run `world/tests/world-contract-simulation.rb` and `world/tests/usb-event-simulation.rb`, then exercise `./device-os world validate`, `available`, `plan`, `capacity`, and `simulate`. Cover unknown or duplicate IDs, missing references, duplicate addresses, unreachable gateways, invalid paths, unsupported language, invalid default media, weakened safety policy, failed writes, readback failure, and generation collisions. These checks prove source behavior only, not physical media creation.
