# Rocket Launcher — PPHL Attendance App OTA Publisher

Publishes split-per-ABI APKs to **GitHub Releases** and updates `ota/manifest.json` on your public OTA repo so installed apps can detect and force-install updates.

## Architecture

| Item | Location | Public URL |
|------|----------|------------|
| Manifest | `ota/manifest.json` on `main` | `https://raw.githubusercontent.com/{OWNER}/{REPO}/main/ota/manifest.json` |
| APKs | GitHub Release assets | `https://github.com/{OWNER}/{REPO}/releases/download/{TAG}/app-arm64-v8a-release.apk` |

The Attendance app fetches the manifest on cold start, then downloads the correct ABI APK from URLs in the manifest.

## One-time setup

### 1. Create a public GitHub repo

Create a new **public** repository (e.g. `rocket-launcher`). Phones must download APKs without authentication.

### 2. Push this project to GitHub

```powershell
cd "rocket launcher"
git init
git add .
git commit -m "Initial Rocket Launcher OTA publisher"
git branch -M main
git remote add origin https://github.com/ciphercall/rocket-launcher.git
git push -u origin main
```

### 3. Create a GitHub Personal Access Token

GitHub → Settings → Developer settings → Personal access tokens → **Tokens (classic)** → `repo` scope.

### 4. Configure `config/github.env`

```powershell
copy config\github.env.example config\github.env
```

Edit `github.env`:

```env
GITHUB_OWNER=ciphercall
GITHUB_REPO=rocket-launcher
GITHUB_BRANCH=main
GITHUB_PAT=ghp_your_token_here
UPDATE_MANIFEST_URL=https://raw.githubusercontent.com/ciphercall/rocket-launcher/main/ota/manifest.json
APP_ID=com.pphl.employee_attendance
```

Never commit `github.env` (it is gitignored).

You can also set `GITHUB_PAT` as an environment variable instead of storing it in `github.env` (useful with Git Credential Manager).

## Publish a new update

### Option A — build + publish in one step

```powershell
cd ..\Attandance_App
powershell -ExecutionPolicy Bypass -File .\scripts\build-production-apk.ps1 -Publish -ReleaseNotes "Describe what changed"
```

### Option B — manual steps

1. Build production APKs:
   ```powershell
   cd ..\Attandance_App
   powershell -ExecutionPolicy Bypass -File .\scripts\build-production-apk.ps1
   ```
2. Copy both APKs to `inbox/`:
   - `app-arm64-v8a-release.apk`
   - `app-armeabi-v7a-release.apk`
3. Publish:
   ```powershell
   cd scripts
   .\publish-update.ps1 -ReleaseNotes "Describe what changed"
   ```

The script will:

1. Create GitHub Release `v{version}-build{N}` (e.g. `v2.2.3-build38`)
2. Upload both APKs as release assets
3. Update `ota/manifest.json` on `main` via GitHub API
4. Write `out/manifest.json` and `out/last-publish.json` locally

## App integration

`Attandance_App\scripts\build-production-apk.ps1` reads `UPDATE_MANIFEST_URL` from `config/github.env` and passes it as `--dart-define` when building APKs.

Disable OTA checks in dev:

```powershell
flutter build apk ... --dart-define=UPDATE_CHECK_ENABLED=false
```

## Android install note

Google requires the user to tap **Install** on the system dialog. The app opens the installer automatically after download and attempts to relaunch via `MY_PACKAGE_REPLACED` after a successful update.

## Folder layout

```
rocket launcher/
├── config/github.env.example   # template
├── config/github.env           # your PAT (gitignored)
├── ota/manifest.json           # seed + updated by publish script
├── inbox/                      # drop APKs here before publish
├── out/                        # local manifest + audit log
└── scripts/
    ├── publish-update.ps1
    └── lib/
        ├── Read-ApkVersion.ps1
        ├── Build-Manifest.ps1
        ├── Publish-GitHubRelease.ps1
        └── Update-GitHubManifest.ps1
```

## First rollout

1. Fill `github.env` and push this repo to GitHub
2. Run first `publish-update.ps1` with APKs in `inbox/`
3. Verify manifest: open `UPDATE_MANIFEST_URL` in a browser
4. Rebuild Attendance app so `UPDATE_MANIFEST_URL` is baked in
5. Install that build manually on devices once; future updates are OTA via GitHub
