# World Record

This folder is everything you need as the user of this repository. It holds
what you decide about Jeonghan's home, what you keep private on your own
machine, and what has happened so far. Everything else in the repository is
machinery in `engine/` that reads this folder; you do not need to open it.

Editing anything here never creates a USB and never authorizes a destructive
operation. Writes happen only through `./device-os` with a target-specific
confirmation.

```text
world-record/
├── README.md               this guide
├── world-playbook.yaml     registry of the paths below, read by the World tools
├── blueprint/              the home blueprint: desired state you edit (tracked)
│   ├── home.yaml
│   ├── nodes/
│   └── dns/
├── private/                private files never committed (ignored)
│   ├── keys/
│   ├── inventory/
│   └── usb-events/
└── history/                what happened; never edited (tracked)
    ├── usb/
    ├── usb-failed/
    └── verification/
```

## blueprint/ — the home blueprint you edit

| To change | Edit |
| --- | --- |
| Networks, nodes, services, media selections, or policies of the home | [`blueprint/home.yaml`](blueprint/home.yaml) |
| The reviewed hardware profile of one DNS role (`dns01`..`dns03`) | `blueprint/nodes/<role>.conf.example` and [`blueprint/nodes/nodes.example.yml`](blueprint/nodes/nodes.example.yml) |
| DNS records served by the cluster | [`blueprint/dns/home.arpa.zone`](blueprint/dns/home.arpa.zone) and [`blueprint/dns/home.arpa.example.yml`](blueprint/dns/home.arpa.example.yml) |

Check every change before anything is built:

```sh
./device-os world validate
./device-os world plan
./device-os world simulate
DEVICE_OS_MEDIA=inventory-capture ./device-os world plan
```

The default `dns-install` media selects only `dns-appliance`. The separate
`inventory-capture` media selects only `debian-live`. Both use Korean menu
presentation; the DNS installer itself is also configured for `ko_KR.UTF-8`.

See [`blueprint/nodes/AGENTS.md`](blueprint/nodes/AGENTS.md) and
[`blueprint/dns/AGENTS.md`](blueprint/dns/AGENTS.md) for the rules of each part.

## private/ — private files never committed

`private/` is ignored by Git except its README and the public `keys/*.example`
templates. It holds operator public keys, real hardware captures, and the burn
recorder's working state. See [`private/README.md`](private/README.md).

Passwords, tokens, private SSH keys, age identities, and recovery archives do
not belong here either; they stay in the principal secret store.

## history/ — what happened; never edited

`history/` is written by the tools and is never edited by hand.

- `history/usb/` holds one immutable generation per successfully verified
  physical USB creation, named `{YYYYMMDDHHmmss}-{world-slug}/`. The timestamp
  is captured in `Asia/Seoul` when the resolved World is sealed immediately
  before the target-specific write. Rewriting identical intent to another USB
  still creates a new generation. See [`history/usb/README.md`](history/usb/README.md).
- `history/usb-failed/` holds redacted records of physical writes that failed
  or were cancelled. They never become generations. See
  [`history/usb-failed/README.md`](history/usb-failed/README.md).
- `history/verification/` holds verification reports for source checks,
  simulations, and VM qualification runs.

`world burn` and `world burn-image-macos` serialize physical attempts. They
stage pending state under the ignored `private/usb-events/`, publish a completed
generation only after writer readback passes, and retain redacted records of
unsuccessful attempts. A plan or successful simulation is not evidence that a
physical USB was written.

## world-playbook.yaml

[`world-playbook.yaml`](world-playbook.yaml) tells the World tools where the
home definition (`blueprint/home.yaml`) and the generation root (`history/usb`)
live, the timezone, and the generation ID format. Registered paths must stay
inside this folder.
