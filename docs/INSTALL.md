# Installation

## Online (recommended)

```powershell
irm https://github.com/st0rax/webagent/releases/latest/download/install-webagent.ps1 | iex
```

Installs to `%USERPROFILE%\Desktop\webagent` and `%USERPROFILE%\Desktop\bot2bot`.

## Offline

1. Download `webagent-suite_vX.Y.Z.zip` from [Releases](https://github.com/st0rax/webagent/releases).
2. Extract to Desktop.
3. Run `INSTALL.ps1` inside the extracted folder.

## Verify

```powershell
cd $env:USERPROFILE\Desktop\bot2bot\scripts
.\verify_install.ps1

cd $env:USERPROFILE\Desktop\webagent
.\webagent.bat brains-health
```

## Brain login (first use)

Each web brain needs a one-time browser login:

```cmd
webagent.bat login --brain chatgpt
webagent.bat login --brain claude
```

Use `diagnose --brain <id>` if selectors need updating.

## Troubleshooting

| Problem | Fix |
|---------|-----|
| `ExecutionPolicy` blocked | Use `install-webagent.cmd` or `-ExecutionPolicy Bypass` |
| Parser error on German PC | Scripts are ASCII-only; re-download latest release |
| `irm` connection reset | Check release URL exists; try `install-webagent.cmd` with local copy |
| Playwright / Chrome lock | Close other Chromium windows using `data/profiles/shared` |