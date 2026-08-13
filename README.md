# Rocket Launcher — PPHL Attendance App OTA Publisher

Publishes split-per-ABI APKs to **GitHub Releases** and updates `ota/manifest.json` on the public OTA repo so installed apps detect and force-install updates.

**Production repo:** [github.com/ciphercall/rocket-launcher](https://github.com/ciphercall/rocket-launcher)  
**Full app-side docs:** [`Attandance_App/docs/OTA_UPDATES.md`](../Attandance_App/docs/OTA_UPDATES.md)

---

## Quick publish (one double-click)

**Double-click `PUBLISH-OTA-UPDATE.cmd`** (in this folder or in `../Attandance_App/`).

1. Enter release notes when prompted
2. Wait for Flutter build + GitHub upload (~3–5 min)
3. Done — installed apps get the update on next cold start

| Script | Purpose |
|--------|---------|
| `PUBLISH-OTA-UPDATE.cmd` | Build APKs + publish to GitHub (normal release) |
| `PUBLISH-APK-ONLY.cmd` | Publish APKs already in `inbox/` (no rebuild) |
| `../Attandance_App/scripts/build-production-apk.cmd` | Build APKs only (no publish) |

---

## Architecture

```
Maintainer PC                    GitHub (public)                 Android phones
─────────────                    ───────────────                 ──────────────
PUBLISH-OTA-UPDATE.cmd    ──►   ota/manifest.json (main)  ◄──  GET on cold start
  ├─ flutter build APK    ──►   Release assets (APKs)     ◄──  GET when updating
  └─ publish-update.ps1   ──►   GitHub API (PAT auth)
```

| Item | Location | Public URL |
|------|----------|------------|
| Manifest | `ota/manifest.json` on `main` | `https://raw.githubusercontent.com/ciphercall/rocket-launcher/main/ota/manifest.json` |
| APKs | GitHub Release assets | `https://github.com/ciphercall/rocket-launcher/releases/download/v2.2.3-build{N}/app-arm64-v8a-release.apk` |

The Attendance app fetches the manifest on cold start, then downloads the correct ABI APK from URLs in the manifest.

---

## One-time setup

### 1. Public GitHub repo

Repo **ciphercall/rocket-launcher** (public). Phones must download APKs without authentication.

### 2. Push this project

```powershell
cd "rocket launcher"
git remote add origin https://github.com/ciphercall/rocket-launcher.git
git push -u origin main
```

### 3. GitHub Personal Access Token

GitHub → Settings → Developer settings → Personal access tokens → **Tokens (classic)** → enable **`repo`** scope.

### 4. Configure `config/github.env`

```powershell
copy config\github.env.example config\github.env
```

```env
GITHUB_OWNER=ciphercall
GITHUB_REPO=rocket-launcher
GITHUB_BRANCH=main
GITHUB_PAT=ghp_your_token_here
UPDATE_MANIFEST_URL=https://raw.githubusercontent.com/ciphercall/rocket-launcher/main/ota/manifest.json
APP_ID=com.pphl.employee_attendance
```

Never commit `github.env` (gitignored). Alternatively set `$env:GITHUB_PAT` before running publish scripts.

---

## Publish pipeline (`publish-update.ps1`)

When you run publish (via `-Publish` on build script or `PUBLISH-APK-ONLY.cmd`):

1. Read APK versions from `inbox/app-arm64-v8a-release.apk` and `inbox/app-armeabi-v7a-release.apk` (normalizes ABI-offset version codes)
2. Create GitHub Release tag `v{version}-build{N}` (e.g. `v2.2.3-build41`)
3. Upload both APKs as release assets
4. Build manifest JSON with download URLs + SHA-256 hashes
5. Update `ota/manifest.json` on `main` via GitHub Contents API
6. Write local copies to `out/manifest.json` and `out/last-publish.json`

Manifest JSON is compact UTF-8 **without BOM** (`ConvertTo-Json -Compress`).

---

## Manifest schema

```json
{
  "app_id": "com.pphl.employee_attendance",
  "version_name": "2.2.3",
  "version_code": 41,
  "force_update": true,
  "release_notes": "User-visible changelog",
  "published_at": "2026-08-12T10:56:55Z",
  "apks": {
    "arm64-v8a": { "url": "...", "size_bytes": 47925422, "sha256": "..." },
    "armeabi-v7a": { "url": "...", "size_bytes": 40197422, "sha256": "..." }
  }
}
```

---

## PowerShell alternatives

**Build + publish:**

```powershell
cd ..\Attandance_App
powershell -ExecutionPolicy Bypass -File .\scripts\build-production-apk.ps1 -Publish -ReleaseNotes "Describe what changed"
```

**Publish only** (APKs already in `inbox/`):

```powershell
cd scripts
.\publish-update.ps1 -ReleaseNotes "Describe what changed"
```

---

## App integration

`Attandance_App\scripts\build-production-apk.ps1` reads `UPDATE_MANIFEST_URL` from `config/github.env` and passes it as `--dart-define` when building APKs.

Disable OTA checks in dev:

```powershell
flutter build apk ... --dart-define=UPDATE_CHECK_ENABLED=false
```

---

## Android install note

Google requires the user to tap **Install** on the system dialog. The app opens the installer automatically after download and relaunches via `MY_PACKAGE_REPLACED` after a successful update.

---

## Folder layout

```
rocket launcher/
├── PUBLISH-OTA-UPDATE.cmd      # delegate → Attandance_App
├── PUBLISH-APK-ONLY.cmd        # publish inbox APKs only
├── config/
│   ├── github.env.example
│   └── github.env              # PAT (gitignored)
├── ota/manifest.json           # seed; updated on GitHub by publish script
├── inbox/                      # APKs copied here before publish
├── out/                        # local manifest + last-publish.json audit
└── scripts/
    ├── publish-update.ps1
    ├── publish-update.cmd
    └── lib/
        ├── Read-ApkVersion.ps1
        ├── Build-Manifest.ps1
        ├── Publish-GitHubRelease.ps1
        └── Update-GitHubManifest.ps1
```

---

## First rollout vs ongoing updates

**First rollout (once per device):**

1. Configure `github.env` and push repo to GitHub
2. Run first publish with APKs in `inbox/`
3. Rebuild Attendance app (manifest URL baked in via `github.env`)
4. **Manually install** that baseline on each device

**Ongoing (every release):**

Double-click `PUBLISH-OTA-UPDATE.cmd` → enter notes → wait. No manual APK distribution.

---

## Troubleshooting publish

| Error | Fix |
|-------|-----|
| `Missing GITHUB_PAT` | Fill `config/github.env` or set `$env:GITHUB_PAT` |
| `Missing inbox APK` | Run build first or use `PUBLISH-OTA-UPDATE.cmd` |
| `Version code mismatch` | Ensure both split APKs are from the same build |
| GitHub 401 | Regenerate PAT with `repo` scope |

---

## Status

**Verified:** August 12, 2026 — end-to-end OTA test (v40 → v41) on a real Android phone with Grameenphone/airtel connectivity.
