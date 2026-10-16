# DNS World

This module is the operator-owned intent for Jeonghan's home DNS cluster. The
mutable draft is
[`drafts/jeonghan-home-dns/world.yaml`](drafts/jeonghan-home-dns/world.yaml). Editing it
does not create a USB and never authorizes a destructive operation.

```sh
./device-os world validate
./device-os world plan
./device-os world simulate
DEVICE_OS_MEDIA=inventory-capture ./device-os world plan
```

The default `dns-install` media selects only `dns-appliance`. The separate
`inventory-capture` media selects only `debian-live`. Both use Korean menu
presentation; the DNS installer itself is also configured for `ko_KR.UTF-8`.

## Physical USB generations

Every successfully verified physical USB creation receives a new immutable ID:

```text
worlds/{YYYYMMDDHHmmss}-{world-slug}/
```

The timestamp is captured in `Asia/Seoul` when the resolved World is sealed
immediately before the target-specific write. It is not draft creation time,
file modification time, or commit time. Rewriting identical intent to another
USB still creates a new generation. Completed generations are never edited or
overwritten.

```text
world/
├── world-playbook.yaml
├── drafts/jeonghan-home-dns/world.yaml
├── worlds/README.md
├── local/README.md
└── docs/
```

`drafts/` is mutable desired state. `worlds/` is append-only completed history.
`local/` contains ignored machine-local observations and reviewed public inputs.
Generated images, caches, credentials, private keys, raw hardware identifiers,
and recovery material do not belong in Git.

Automatic generation publication remains unimplemented. A plan or successful
simulation is not evidence that a physical USB was written.
