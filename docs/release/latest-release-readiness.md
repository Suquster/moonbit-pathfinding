# Release Readiness

- Generated at: 2026-07-12T18:48:50.2826716+00:00
- Script: scripts\release_guard.ps1
- MoonBit: moon 0.1.20260703 (6fbf8c3 2026-07-03)  Feature flags enabled: rr_moon_mod,rr_moon_pkg
- Module: Suquster/moonbit-pathfinding@0.2.0
- Status: pass-with-warnings
- Package artifact: /home/ubuntu/repos/moonbit-pathfinding/_build/publish/Suquster-moonbit-pathfinding-0.2.0.zip
- moon publish --dry-run: blocked-missing-credentials

## Checklist

| Check | Status |
|---|---|
| module_name | True |
| version_semver | True |
| readme_exists | True |
| repository_url | True |
| homepage_url | True |
| license_spdx | True |
| keywords | True |
| description | True |
| license_file | True |
| changelog_unreleased | True |
| changelog_current_version | True |
| readme_badge_version | True |
| readme_mbt_exists | True |
| release_workflow_no_continue_on_error | True |
| release_workflow_no_publish_true | True |
| release_workflow_credentials | True |
| package_artifact | True |

## Warnings
- moon publish --dry-run is blocked locally by missing mooncakes credentials; run moon login or configure CI secrets before publishing.

Raw JSON: release-readiness-20260712-184850.json and latest-release-readiness.json.
