# Local Inputs

This directory is reserved for ignored machine-local inputs and observations,
including captured hardware inventory and operator public-key files.

Do not place long-lived secrets here merely because the directory is ignored.
Passwords, tokens, private SSH keys, age identities, and recovery archives
belong in the principal secret store. The World may contain a non-sensitive
reference to that store, never the value.

Expected local inventory paths for the example draft are:

```text
local/inventory/dns01.yaml
local/inventory/dns02.yaml
local/inventory/dns03.yaml
```

The Installer integration must reject a missing, ambiguous, stale, or
non-matching inventory before any destructive operation.

`local/usb-events/` is created automatically for the checkout-local writer
lock, pending event transactions, safe writer evidence, and atomic staging.
It is ignored and is not the durable event history. Successful records move to
`worlds/`; failed and cancelled physical attempts move to `events/`.
