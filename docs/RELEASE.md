# Release workflow

All releases go through **git** and **GitHub CLI** — no browser upload.

## Prerequisites

```powershell
gh auth status   # must show logged-in user
```

One-time: `gh auth login --web`

## Build and publish

```powershell
cd C:\Users\storax\Desktop\bot2bot\scripts

.\build_release_zip.ps1 -Version 0.1.5
.\pre_release_verify.ps1 -Version 0.1.5 -SkipInstall
.\git_release.ps1 -Version 0.1.5 -PushSource
```

`pre_release_verify.ps1` is mandatory before upload (parser check, ASCII, live URL smoke).

## Source sync

`git_release.ps1 -PushSource` runs `sync_git_monorepo.ps1`, which pushes this monorepo layout to `main` on GitHub.

## Install URL after release

```powershell
irm https://github.com/st0rax/webagent/releases/download/v0.1.5/install-webagent.ps1 | iex
```