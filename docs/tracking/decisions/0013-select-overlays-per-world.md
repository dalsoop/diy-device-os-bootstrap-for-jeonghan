# 0013: Select Overlay Networks per World and Bundle Only the Selected Clients

- Status: Accepted
- Date: 2026-11-01

## Context

The DNS appliances are managed from the management host over a private overlay
network. Tailscale and NetBird both meet that need, and a home may use either
one or both. A client that the home does not use still adds code, a running
daemon, license and notice duties, and a component to review. A DNS image built
for one selection and installed into a World that expects another would leave
the nodes unreachable through the overlay the operator plans to use, and the
mismatch would surface only after installation.

## Decision

Every World declares `spec.overlays`: a required, non-empty list of unique
values from the closed set `tailscale`, `netbird`. There is no default; a
missing, empty, duplicated, unknown, or non-list value fails validation. The
World plan carries the selection in World order.

The DNS image follows the resolved World. `fetch-locked-sources` fetches and
`build-image` embeds only the selected clients and their license material,
plus an `overlays` file in the canonical order `tailscale`, `netbird`. The
component registry, build manifest, and SBOM describe exactly the selected
subset, and the installed appliance installs and enables only the selected
clients. No client is enrolled at installation; enrollment stays a
management-host action per overlay (`tailscale-enroll`, `netbird-enroll`).

`world readiness`, `world build-image`, and `world burn` compare the DNS build
manifest's `overlays` with the World's as a set and refuse any difference
before an image is assembled, a target is inspected, or a USB event is opened.
A manifest without `overlays` is refused. `world burn-image-macos` relies on
its raw-image manifest's binding to the resolved Catalog digest, which embeds
the World plan and therefore the selection.

## Alternatives

- Always bundling both clients was rejected because an unused client still
  brings a daemon, license duties, and review scope into every image.
- A default selection when the field is absent was rejected because a
  remote-access client would then enter or leave the image without anyone
  choosing it.
- Choosing the overlay at installation time was rejected because the image,
  its records, and its review must describe exactly the bytes it carries.
- Comparing in canonical order only, without set semantics, was rejected for
  the World side because the World records intent in the order written; the
  manifest itself keeps the canonical order.

## Consequences

Changing a World's overlays requires a rebuilt DNS image and new media; an
older image is refused for that World. Records without `overlays` are not
accepted for new use, while completed USB generations stay unchanged and are
not re-validated. Each added overlay needs a pinned client, license material,
a registry component, manifest fields, and enrollment tooling before it can
enter the closed set.
