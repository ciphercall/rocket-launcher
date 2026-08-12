#Requires -Version 5.1
param(
    [string]$ReleaseNotes = 'App update',
    [string]$InboxDir,
    [string]$ConfigFile
)

$ErrorActionPreference = 'Stop'

$scriptsDir = $PSScriptRoot
$rootDir = Split-Path $scriptsDir -Parent
. (Join-Path $scriptsDir 'lib\Read-ApkVersion.ps1')
. (Join-Path $scriptsDir 'lib\Build-Manifest.ps1')
. (Join-Path $scriptsDir 'lib\Publish-GitHubRelease.ps1')
. (Join-Path $scriptsDir 'lib\Update-GitHubManifest.ps1')

if (-not $InboxDir) { $InboxDir = Join-Path $rootDir 'inbox' }
if (-not $ConfigFile) { $ConfigFile = Join-Path $rootDir 'config\github.env' }

if (-not (Test-Path -LiteralPath $ConfigFile)) {
    throw "Missing config: $ConfigFile`nCopy config\github.env.example to config\github.env and fill in credentials."
}

$config = @{}
Get-Content -LiteralPath $ConfigFile | ForEach-Object {
    $line = $_.Trim()
    if ($line -eq '' -or $line.StartsWith('#')) { return }
    if ($line -match '^([^=]+)=(.*)$') {
        $config[$Matches[1].Trim()] = $Matches[2].Trim()
    }
}

if ([string]::IsNullOrWhiteSpace($config.GITHUB_PAT) -and -not [string]::IsNullOrWhiteSpace($env:GITHUB_PAT)) {
    $config.GITHUB_PAT = $env:GITHUB_PAT.Trim()
}

foreach ($key in @('GITHUB_OWNER', 'GITHUB_REPO', 'GITHUB_PAT')) {
    if (-not $config.ContainsKey($key) -or [string]::IsNullOrWhiteSpace($config[$key])) {
        throw "Missing $key in $ConfigFile"
    }
}
if (-not $config.ContainsKey('APP_ID')) {
    $config.APP_ID = 'com.pphl.employee_attendance'
}
if (-not $config.ContainsKey('GITHUB_BRANCH')) {
    $config.GITHUB_BRANCH = 'main'
}
if (-not $config.ContainsKey('UPDATE_MANIFEST_URL')) {
    $config.UPDATE_MANIFEST_URL = "https://raw.githubusercontent.com/$($config.GITHUB_OWNER)/$($config.GITHUB_REPO)/$($config.GITHUB_BRANCH)/ota/manifest.json"
}

$arm64Apk = Join-Path $InboxDir 'app-arm64-v8a-release.apk'
$armApk = Join-Path $InboxDir 'app-armeabi-v7a-release.apk'

if (-not (Test-Path -LiteralPath $arm64Apk)) {
    throw "Missing $arm64Apk - copy build output from Attandance_App\build\app\outputs\flutter-apk\"
}
if (-not (Test-Path -LiteralPath $armApk)) {
    throw "Missing $armApk - copy build output from Attandance_App\build\app\outputs\flutter-apk\"
}

Write-Host 'Reading APK versions...' -ForegroundColor Cyan
$arm64Info = Read-ApkVersionInfo -ApkPath $arm64Apk
$armInfo = Read-ApkVersionInfo -ApkPath $armApk

if ($arm64Info.VersionCode -ne $armInfo.VersionCode) {
    throw "Version code mismatch: arm64=$($arm64Info.VersionCode) armeabi=$($armInfo.VersionCode)"
}
if ($arm64Info.VersionName -ne $armInfo.VersionName) {
    throw "Version name mismatch: arm64=$($arm64Info.VersionName) armeabi=$($armInfo.VersionName)"
}

$versionCode = $arm64Info.VersionCode
$versionName = $arm64Info.VersionName
Write-Host "Publishing v$versionName+$versionCode to GitHub..." -ForegroundColor Green

$apkFiles = @(
    @{ Abi = 'arm64-v8a'; FileName = 'app-arm64-v8a-release.apk'; Path = $arm64Apk },
    @{ Abi = 'armeabi-v7a'; FileName = 'app-armeabi-v7a-release.apk'; Path = $armApk }
)

$releaseResult = Publish-GitHubReleaseApks `
    -Config $config `
    -VersionName $versionName `
    -VersionCode $versionCode `
    -ReleaseNotes $ReleaseNotes `
    -ApkFiles $apkFiles

$manifestJson = Build-UpdateManifest `
    -AppId $config.APP_ID `
    -VersionName $versionName `
    -VersionCode $versionCode `
    -ReleaseNotes $ReleaseNotes `
    -ApkEntries $releaseResult.ApkEntries

$outDir = Join-Path $rootDir 'out'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$manifestPath = Join-Path $outDir 'manifest.json'
Set-Content -LiteralPath $manifestPath -Value $manifestJson -Encoding UTF8

$otaLocalPath = Join-Path $rootDir 'ota\manifest.json'
Set-Content -LiteralPath $otaLocalPath -Value $manifestJson -Encoding UTF8

Write-Host 'Updating manifest on GitHub...' -ForegroundColor Cyan
$manifestResult = Update-GitHubManifestFile `
    -Config $config `
    -ManifestJson $manifestJson `
    -CommitMessage "OTA release $versionName+$versionCode"

$audit = [ordered]@{
    published_at  = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    version_name  = $versionName
    version_code  = $versionCode
    release_tag   = $releaseResult.TagName
    release_notes = $ReleaseNotes
    manifest_url  = $manifestResult.ManifestUrl
    apks          = $releaseResult.ApkEntries
}
$auditPath = Join-Path $outDir 'last-publish.json'
Set-Content -LiteralPath $auditPath -Value ($audit | ConvertTo-Json -Depth 6) -Encoding UTF8

Write-Host ''
Write-Host 'Publish complete!' -ForegroundColor Green
Write-Host "  Manifest URL: $($manifestResult.ManifestUrl)"
Write-Host "  Release tag:  $($releaseResult.TagName)"
Write-Host "  Releases URL: https://github.com/$($config.GITHUB_OWNER)/$($config.GITHUB_REPO)/releases/latest" -ForegroundColor Cyan
Write-Host "  Local manifest: $manifestPath"
Write-Host "  Audit log: $auditPath"
Write-Host ''
Write-Host 'Ensure app builds use:' -ForegroundColor Yellow
Write-Host "  --dart-define=UPDATE_MANIFEST_URL=$($manifestResult.ManifestUrl)"
