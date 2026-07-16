# WebAgent Suite

Local AI agent for Windows with swappable web-brain backends (ChatGPT, Claude, Gemini, Kimi, Mistral, Qwen, DeepSeek) plus **bot2bot** — an agent-to-agent messaging layer for desktop and web brains.

Monorepo layout:

```
webagent/          # Core agent (Python, Playwright, REPL, Genius council)
bot2bot/           # AI-to-AI inbox, history, webbrain bridge
install-webagent.ps1
install-webagent.cmd
```

## Install (new PC)

One-liner (Windows PowerShell 5.1 or pwsh 7):

```powershell
irm https://github.com/alexanderkrenz89-ctrl/webagent/releases/latest/download/install-webagent.ps1 | iex
```

Or download and run locally:

```powershell
pwsh -ExecutionPolicy Bypass -File install-webagent.ps1
```

Double-click: `install-webagent.cmd` (no execution-policy prompt).

Requirements: Windows 10/11, user-level install (no admin). Python and PowerShell 7 are installed automatically if missing.

## Quick start (after install)

```cmd
cd %USERPROFILE%\Desktop\webagent
start.bat
```

```powershell
cd %USERPROFILE%\Desktop\bot2bot\scripts
.\append_message.ps1 -From grok -To claude -Subject "Hello" -Body "Test" -Status info
```

## Documentation

| Doc | Topic |
|-----|--------|
| [webagent/README.md](webagent/README.md) | Agent features, CLI, Genius, shared browser |
| [bot2bot/README.md](bot2bot/README.md) | Inbox protocol, webbrain bridge, count-up tests |
| [docs/INSTALL.md](docs/INSTALL.md) | Install paths, verification, troubleshooting |
| [docs/RELEASE.md](docs/RELEASE.md) | Build and publish releases (`gh` CLI) |

## Releases

Pre-built assets: [GitHub Releases](https://github.com/alexanderkrenz89-ctrl/webagent/releases)

| Asset | Purpose |
|-------|---------|
| `webagent-suite_vX.Y.Z.zip` | Full suite for offline copy |
| `install-webagent.ps1` | Online installer (`irm \| iex`) |
| `install-webagent.cmd` | Double-click wrapper |
| `ensure_prerequisites.ps1` | Python / pwsh bootstrap |

## Development (source tree)

Maintained on the developer machine; this repo is synced via `bot2bot/scripts/sync_git_monorepo.ps1`.

```powershell
cd bot2bot\scripts
.\build_release_zip.ps1 -Version 0.1.5
.\pre_release_verify.ps1 -Version 0.1.5 -SkipInstall
.\git_release.ps1 -Version 0.1.5 -PushSource
```

Releases use **GitHub CLI** (`gh`), not browser upload.

## License

Private / personal project. No warranty. Web automation may conflict with third-party terms of service.