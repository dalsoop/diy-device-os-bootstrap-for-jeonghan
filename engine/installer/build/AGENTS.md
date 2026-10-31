# Build Lock Module

This module records immutable external identities used by the DNS image.

- Keep one reviewed source-of-truth value for each upstream release, snapshot,
  architecture, URL, digest, and tool version.
- Use authoritative vendor provenance for every digest update.
- Never store downloaded archives, packages, images, or generated media here.
- A lock update must also update every consumer and expected build evidence.
- Do not replace exact versions, dated snapshots, OCI digests, or SHA-256 values
  with branches, tags that can move, or `latest`.
- Verification failure stops the build; there is no warning-only mode.
- `DEBIAN_SNAPSHOT` and the three Simple-CDD mirror URLs move together;
  `verify-locks` rejects any mirror that names another snapshot.
- The NetBird pin follows the Tailscale pin: exact version, the version-pinned
  GitHub release asset URL, and a SHA-256 accepted only when the vendor's
  checksum file and GitHub's release-asset digest agree.
- `distribution-policy.json` lists every known DNS component ID in canonical
  order; registries and manifests carry the subset that the image's overlay
  selection implies.
- Verify a lock change by checking authoritative provenance, running the lock
  verifier, and recording the resolved artifact identity in release evidence.

