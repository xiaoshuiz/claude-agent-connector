# Release Playbook

## Release outputs

Every release publishes:

- `ClaudeAgentConnector-macOS-Release.zip`
- `ClaudeAgentConnector-macOS-Release.zip.sha256`

## Build locally

Prerequisites: macOS, Xcode, XcodeGen.

```bash
brew install xcodegen
make release
```

Build flow:

1. Generate Xcode project from `project.yml`
2. Build `Release` with `xcodebuild`
3. Package `.app` into zip using `ditto`
4. Produce SHA256 checksum file

## CI validation

`ci-macos.yml` runs on:

- pull requests
- pushes to `main` and `cursor/**`

It guarantees that project generation and macOS debug build remain healthy.

## Publish a version

1. Create and push a semantic tag:

   ```bash
   git tag v0.1.0
   git push origin v0.1.0
   ```

2. `release.yml` automatically:
   - builds release assets
   - uploads workflow artifacts
   - attaches zip + checksum to GitHub Release

## Versioning fields

Manage versions in `project.yml`:

- `MARKETING_VERSION` (human-readable app version, e.g. `0.1.0`)
- `CURRENT_PROJECT_VERSION` (incrementing build number)
