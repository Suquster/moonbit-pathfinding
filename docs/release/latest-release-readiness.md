# Release Readiness

- Generated at: 2026-05-31T18:40:42.8463821+08:00
- Script: scripts\release_guard.ps1
- MoonBit: moon 0.1.20260427 (48d7def 2026-04-27)  Feature flags enabled: rr_moon_pkg
- Module: taoyouce/moonbit-pathfinding@0.0.1
- Status: pass-with-warnings
- Package artifact: D:\my\STUDY\university\U_3\down\Competitions\MoonBit国产基础软件开源大赛\moonbit-pathfinding\_build\publish\taoyouce-moonbit-pathfinding-0.0.1.zip
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

Raw JSON: release-readiness-20260531-184042.json and latest-release-readiness.json.
