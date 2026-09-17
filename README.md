# DeepSeek Harness Desktop (macOS & Windows)

This repository is the lightweight release home for the customised DeepSeek Harness Desktop application (macOS & Windows). It deliberately contains distribution metadata, patches, and build workflows; full source changes remain in the corresponding upstream history to preserve a clean, auditable upstream boundary.

---

## What is in this release

- Native Electron application for **macOS (`arm64`)** and **Windows (`win-x64` / x86_64)**.
- Work and Code views, native workspace file operations, editor save and right-click actions.
- System copy/paste and Markdown editing shortcuts.
- Conversation, project, album and puppy-theme features backed by Desktop services.
- Unsigned release support: Built with `DSH_DESKTOP_ALLOW_UNSIGNED_WINDOWS: '1'`, eliminating the mandatory EV code-signing certificate requirement.

---

## Install

### macOS (Apple Silicon `arm64`)
1. Download `DeepSeek-Harness-mac-arm64.zip` from the latest **Release**.
2. Unzip it and move `DeepSeek Harness.app` to `/Applications`.
3. If macOS displays a gatekeeper warning, go to **System Settings > Privacy & Security** and choose **Open Anyway** (ad-hoc signed).

### Windows (x86_64 / x64)
1. Download `DeepSeek-Harness-win-x64.exe` from the latest **Release** (or build it locally).
2. Run the installer.
3. Because the build is intentionally unsigned, Windows SmartScreen will display:
   > "Windows protected your PC / Windows 已保护你的电脑"
4. Click **More info (更多信息)** -> **Run anyway (仍要运行)** to complete installation.

> [!NOTE]
> The app persists its own data under `~/.dsh`; replacing or upgrading the application does not remove your workspaces, conversations, or albums.

---

## Architecture Note: x86 / x64 Support

DeepSeek Harness Desktop bundles Node.js v24 and modern Electron v44:
- Target architecture is **Windows x86_64 (`win-x64`)**.
- 32-bit (IA-32) is **not supported** by the upstream runtime environment. All standard Intel and AMD 64-bit PCs running Windows 10/11 are fully supported.

---

## Building the Windows Release

### Method 1: Local One-Click Build (PowerShell)

Run the automated build script on any Windows machine:

```powershell
pwsh scripts/build-windows.ps1
```

*What the script does automatically:*
1. Checks for Git, Node.js (>= 22.19.0) and pnpm (11.7.0). If Node.js is missing or too old, it automatically downloads and uses a portable Node 22 environment in `.tools/`.
2. Clones the official upstream repository (`deepseek-ai/deepseek-harness`) at baseline commit `c389f96bf3a9b6807cb71ed6bdad5849be0df6d8`.
3. Extracts and applies the customization patch `patches/desktop-customizations.patch.zip`.
4. Installs dependencies and bootstraps the Typert Remote contracts.
5. Packages the unsigned Windows installer (`.exe`) via electron-builder.
6. Copies the installer to `release/DeepSeek-Harness-win-x64.exe` and outputs its SHA-256 hash.

### Method 2: GitHub Actions (Cloud Build)

1. Push this repository to your GitHub account.
2. Navigate to **Actions** -> **Build Windows installer** (`build-windows.yml`).
3. Click **Run workflow**, enter your release tag (e.g. `v0.1.3-alpha.2`), and run.
4. The workflow will package the installer on a GitHub Windows runner and attach `DeepSeek-Harness-win-x64.exe` directly to your GitHub Release.

---

## Verification

### Verify on macOS:
```bash
sh scripts/verify-macos-app.sh "DeepSeek Harness.app"
```

### Verify on Windows:
```powershell
pwsh scripts/verify-windows-app.ps1
```

Compare the SHA-256 output with the checksum published in the release notes.

---

## License & Provenance

Release `0.1.3-alpha.2` is built from DeepSeek Harness alpha.2 line plus the Desktop customisation patch. Upstream project is licensed under MIT.
