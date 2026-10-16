# 0005: Derive Jeonghan's Device OS Bootstrap

- Status: Accepted
- Date: 2026-10-16

## Context

The generic DIY Device OS Bootstrap repository supports a broad Catalog and a
multi-purpose World. Jeonghan needs one personal World where device intent,
installation media, and verified USB generations accumulate over time. The
first concrete job is to inventory and install three HP DNS appliances.

GitHub cannot create a formal same-owner fork from `dalsoop` back into the same
personal account. A new repository was therefore seeded from the reviewed
upstream history and retains `dalsoop/diy-device-os-bootstrap` as its `upstream`
remote.

## Decision

`dalsoop/device-os-bootstrap-for-jeonghan` is the operator repository for
Jeonghan's home World.

- The product name is **Device OS Bootstrap for Jeonghan**.
- The generated removable media is **Device OS USB for Jeonghan**.
- The operator command remains `device-os`.
- The single mutable World is `jeonghan-home`.
- `dns-install` selects only `dns-appliance`.
- `inventory-capture` selects only `debian-live`.
- The USB data label is `DEVICE-OS`.
- The Debian installer defaults to Korean while retaining a US keyboard map.
- Removed `write` command aliases and DNS-specific argument aliases are not
  supported in this derivative; only the documented `burn` surface remains.
- The embedded Catalog keeps upstream-compatible public metadata, but entries
  not selected by the World are neither downloaded nor staged.

The repository records its own URL in resolved plans, source archives, license
material, schemas, and SBOM output. Upstream changes are reviewed before being
selectively merged or cherry-picked.

## Alternatives

- A formal same-owner GitHub fork was unavailable because both repositories are owned by `dalsoop`.
- Editing the generic upstream as the personal operator source was rejected because local device intent and generation history should not define the reusable product for every user.
- A DNS-specific derivative was rejected because Proxmox, storage, desktop, and later device roles must accumulate in the same personal World.
- Separate personal World, Installer, and Catalog repositories were rejected because the earlier split created coordination cost without independent release value.

## Consequences

The operator normally edits only the home World and ignored local inventory.
The current production media has no unrelated boot choices, while future
devices and media extend the same World rather than creating product-specific
repositories. Repository provenance points to the source that produced each
artifact. Automatic World-generation publication and physical qualification
remain separate unfinished gates.
