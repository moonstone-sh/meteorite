# Meteorite Release Process

Use this process for a Meteorite release tag. It applies the v0.1 contract and
keeps published claims tied to reproducible artifacts.

## Prepare

1. Update the version in `moonstone.toml` and add a release-note document under
   `docs/release-notes/`.
2. Run `bash tests/release-gate.sh` from a clean checkout with the required
   Moonstone/Ballad/Zig toolchain.
3. Create or update the dated audit in `docs/maintenance/` with the tested
   commit, tool versions, certified targets, and any known boundaries.

## Package

1. Build and inspect the registry source package:

   ```bash
   bash tests/registry-export.sh
   ```

2. Generate checksums outside the artifact directory so the checksum list does
   not include itself:

   ```bash
   scripts/release-checksums.sh \
     dist/registry/meteorite \
     dist/registry/SHA256SUMS-v<version>.txt
   ```

3. Review `dist/registry/meteorite/package.toml`, the source archive, and the
   checksum file before publishing.

## Publish

1. Commit the release notes, audit, and version update; then create the signed
   Git tag.
2. Publish the registry artifact using the generated `publish.sh` with the
   required Moonstone token.
3. Publish the release notes, support matrix, known boundaries, artifact
   filenames, checksums, tag commit, and audit reference together.

Do not broaden the supported-target or feature claims beyond the gate evidence
recorded for that tag.
