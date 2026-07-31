---
name: ilumionate-testflight-upload
description: Build and upload Ilumionate to App Store Connect for the user's own TestFlight testing. Use this skill whenever the user says “upload this for testing,” “send this to TestFlight,” “make me a beta build,” “push a testing build to App Store Connect,” or asks to increment Ilumionate’s version/build and upload it.
compatibility: macOS with Xcode, Homebrew asc CLI, an App Store Connect API key in Keychain, and Xcode automatic signing.
---

# Ilumionate TestFlight upload

Use the checked-in release command instead of reconstructing the Xcode and App Store Connect workflow.

## Default interpretation

When the user says “upload this for testing” or equivalent:

- Treat the request as authorization to increment the patch marketing version, choose the next safe build number, archive/export the current working tree, upload it to App Store Connect, wait for processing, and assign an internal TestFlight group.
- The working tree may be dirty because the user commonly tests uncommitted work. Report that fact, but do not block the release solely because of it.
- Do not commit, tag, push Git changes, notify external testers, submit for beta review, or submit to App Review unless the user explicitly asks.
- Do not expose or commit App Store Connect credentials.

## Release command

From the repository root, run:

```bash
Scripts/release-testflight.sh
```

Useful variants:

```bash
# Explicit marketing version
Scripts/release-testflight.sh --version 0.8.0

# Resolve the plan without changing files or uploading
Scripts/release-testflight.sh --dry-run

# Select an exact internal group
Scripts/release-testflight.sh --group "Internal Testing"

# Upload without assigning a group
Scripts/release-testflight.sh --no-group
```

The command:

1. Validates keychain-backed `asc` authentication.
2. Resolves the numeric App Store Connect app ID from `com.byronquine.lumenSync`.
3. Defaults to a patch marketing-version increment.
4. Uses `asc builds next-build-number` with the local next build as its floor, avoiding collisions with processed and in-flight uploads.
5. Updates both the app and share-extension version/build settings.
6. Archives and exports with automatic signing and `-allowProvisioningUpdates`.
7. Uploads the IPA, waits for a valid processed build, and adds an internal TestFlight group.
8. Restores version changes if archive/export fails before App Store Connect accepts the upload.

## One-time authentication

If authentication is missing, explain that this is a one-time machine setup. Ask the user for:

- the path to their downloaded App Store Connect `AuthKey_*.p8` file;
- its Key ID;
- its Issuer ID.

Then run:

```bash
asc auth login \
  --name "Ilumionate" \
  --key-id "KEY_ID" \
  --issuer-id "ISSUER_ID" \
  --private-key "/path/to/AuthKey_KEY_ID.p8" \
  --network
```

Prefer macOS Keychain storage. Do not use `--bypass-keychain`, do not copy the private key into this repository, and do not delete the user's downloaded key file without a separate explicit request.

Generate a team API key in App Store Connect under Users and Access → Integrations. It needs access to this app and enough permission to upload builds and manage internal TestFlight distribution.

## Signing recovery

The project uses automatic signing for team `GUHEBKT9SX`. If archive/export reports a missing Apple Distribution certificate or provisioning profile:

1. Confirm the user's Apple Developer account is signed into Xcode.
2. Retry the release command; it already passes `-allowProvisioningUpdates`.
3. If Xcode still cannot create or retrieve signing assets, have the user open Xcode → Settings → Accounts → their team → Manage Certificates and create an Apple Distribution certificate once.

Do not revoke or replace existing certificates as part of routine TestFlight uploads.

## Completion report

Report the uploaded marketing version and build number, whether Apple processing reached `VALID`, and the internal group assigned. Mention any remaining problem precisely. A successful upload does not imply App Store review submission.
