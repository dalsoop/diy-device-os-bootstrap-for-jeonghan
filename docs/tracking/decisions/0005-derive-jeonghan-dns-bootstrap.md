# 0005: Derive Jeonghan's DNS Bootstrap

- Status: Accepted
- Date: 2026-10-16

## Context

The generic DIY Device OS Bootstrap repository supports a broad Catalog and a
multi-purpose World. Jeonghan's home deployment currently needs one repeatable
job: inventory and install three HP DNS appliances. Presenting unrelated
TrueNAS, Proxmox, and desktop media in the production path increases operator
choice without helping that job.

GitHub cannot create a formal same-owner fork from `dalsoop` back into the same
personal account. A new repository was therefore seeded from the reviewed
upstream history and retains `dalsoop/diy-device-os-bootstrap` as its `upstream`
remote.

## Decision

`dalsoop/dns-device-os-bootstrap-for-jeonghan` is the operator repository for this DNS
cluster.

- The product name is **DNS Device OS Bootstrap for Jeonghan**.
- The generated production media is **DNS Install USB for Jeonghan**.
- The operator command remains `device-os`.
- The single mutable World is `jeonghan-home-dns`.
- `dns-install` selects only `dns-appliance`.
- `inventory-capture` selects only `debian-live`.
- The USB data label is `DNS-INSTALL`.
- The Debian installer defaults to Korean while retaining a US keyboard map.
- Removed `write` command aliases and DNS-specific argument aliases are not
  supported in this derivative; only the documented `burn` surface remains.
- The embedded Catalog keeps upstream-compatible public metadata, but entries
  not selected by the World are neither downloaded nor staged.

The repository records its own URL in resolved plans, source archives, license
material, schemas, and SBOM output. Upstream changes are reviewed before being
selectively merged or cherry-picked.

## Consequences

The operator normally edits only the DNS World and ignored local inventory.
Production media has no unrelated boot choices. Repository provenance now
points to the source that actually produced an artifact. The derivative must
continue to carry upstream safety fixes, and automatic World-generation
publication and physical qualification remain separate unfinished gates.
