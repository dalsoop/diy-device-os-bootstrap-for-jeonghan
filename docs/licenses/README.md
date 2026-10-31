# Licenses

This repository is licensed under the GNU GPL version 3 in the root
[`LICENSE`](../../LICENSE). Everything else license-related lives here.

| File | Purpose |
| --- | --- |
| [`LICENSE_HISTORY.md`](LICENSE_HISTORY.md) | The MIT-to-GPL transition boundary and what each earlier revision may be used under |
| [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md) | Upstream components, their licenses, and how generated media carry their notices |
| [`Tailscale-BSD-3-Clause.txt`](Tailscale-BSD-3-Clause.txt) | The Tailscale client license text shipped with a DNS image that selects Tailscale |
| [`NetBird-BSD-3-Clause.txt`](NetBird-BSD-3-Clause.txt) | The NetBird repository license text at tag `v0.82.0`, shipped with a DNS image that selects NetBird |

`NetBird-BSD-3-Clause.txt` is the unchanged root `LICENSE` of
<https://github.com/netbirdio/netbird> at tag `v0.82.0`
(<https://raw.githubusercontent.com/netbirdio/netbird/v0.82.0/LICENSE>, SHA-256
`8343fe949e32a30e2261c4f0967365271d08c4644e879dec5b998d1af666fdb3`). It places
the client under BSD-3-Clause and names the server directories that are
AGPL-3.0 instead; the pinned client archive contains only the client.

The DNS image build copies the project license, the license history and the
notices into every image, and the license text of an overlay client only when
the World selects that overlay; it fails when a required file is missing. The
image installs them under the same file names in
`/usr/share/doc/diy-device-os-bootstrap-for-jeonghan/`, and the USB writers
copy them into `licenses/`. When adding or renaming a file here, update
`engine/installer/dns-image/build-image`, `engine/installer/usb-media/write-usb-linux`,
the `contracts` workflow and `engine/installer/tests/repository-contract.sh`
together.
