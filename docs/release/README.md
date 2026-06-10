# Release Readiness

This directory stores reproducible release and publish-readiness evidence.

Run:

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File scripts\release_guard.ps1
```

The guard checks:

- `moon.mod.json` package metadata.
- README / changelog / license consistency.
- release workflow hard-gate behavior.
- `moon package` artifact generation.
- `moon publish --dry-run` status.

`moon publish --dry-run` still requires local mooncakes credentials. If the
machine has not run `moon login`, the guard records that as an environment
blocker rather than pretending publishing happened.
