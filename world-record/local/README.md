# Local Inputs

This folder holds machine-local inputs and observations. Git ignores
everything here except this README and the public `keys/*.example` templates.

Do not place long-lived secrets here merely because the folder is ignored.
Passwords, tokens, private SSH keys, age identities, and recovery archives
belong in the principal secret store. The World may contain a non-sensitive
reference to that store, never the value.

```text
local/
├── keys/
│   ├── operator-authorized-keys            operator SSH public key(s)
│   ├── operator-authorized-keys.example    tracked template
│   ├── age-recipient                       public age recipient for enrollment bundles
│   └── age-recipient.example               tracked template
├── inventory/
│   ├── dns01.conf                          real hardware capture per role
│   ├── dns02.conf
│   └── dns03.conf
└── usb-events/                             burn recorder working state
```

- `keys/` holds only public material. The DNS image build reads
  `keys/operator-authorized-keys` and `keys/age-recipient` unless
  `DNS_APPLIANCE_AUTHORIZED_KEYS` or `DNS_APPLIANCE_AGE_RECIPIENT` points
  elsewhere.
- `inventory/` holds real hardware captures produced by
  `engine/installer/dns-image/capture-inventory` on each target device. The
  reviewed build reads it unless `DNS_APPLIANCE_INVENTORY_DIR` points
  elsewhere. The Installer rejects a missing, ambiguous, stale, or
  non-matching inventory before any destructive operation.
- `usb-events/` is created automatically for the checkout-local writer lock,
  pending event transactions, safe writer evidence, and atomic staging. It is
  not the durable event history: successful generations are published to
  `../records/usb/` and failed or cancelled physical attempts to
  `../records/usb-failed/`.
