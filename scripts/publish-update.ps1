#Requires -Version 5.1
param(
    [string]$ReleaseNotes = 'App update',
    [string]$InboxDir,
    [string]$ConfigFile,
    # 'prod' writes ota/manifest.json and is the default, so an existing caller
    # is unchanged. 'beta' writes ota/beta/manifest.json, tags the release with a
    # -beta suffix, marks it a prerelease, and refuses a build number outside the
    # beta band.
    [ValidateSet('prod', 'beta')]
    [string]$Channel = 'prod'
)

$ErrorActionPreference = 'Stop'

# Build numbers are disjoint per channel. Without this a beta publish would be
# offered to production phones, because the update check is a plain integer
# compare with nothing channel-aware in it.
$BetaVersionFloor = 9000
$ProdVersionCeiling = 8999

$scriptsDir = $PSScriptRoot
$rootDir = Split-Path $scriptsDir -Parent
. (Join-Path $scriptsDir 'lib\Read-ApkVersion.ps1')
. (Join-Path $scriptsDir 'lib\Build-Manifest.ps1')
. (Join-Path $scriptsDir 'lib\Publish-GitHubRelease.ps1')
. (Join-Path $scriptsDir 'lib\Update-GitHubManifest.ps1')

if (-not $InboxDir) { $InboxDir = Join-Path $rootDir 'inbox' }
if (-not $ConfigFile) { $ConfigFile = Join-Path $rootDir 'config\github.env' }

# Beta keeps its own inbox so a beta build can never be picked up by a later
# prod publish that only copies over the two filenames.
if (-not $PSBoundParameters.ContainsKey('InboxDir') -and $Channel -eq 'beta') {
    $InboxDir = Join-Path $rootDir 'inbox\beta'
}

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

# Enforced before anything is uploaded. A build number in the wrong band would
# be offered to the other channel's devices on their next cold start, and the
# failure would only show up in the field.
if ($Channel -eq 'beta' -and $versionCode -lt $BetaVersionFloor) {
    throw "Beta build number $versionCode is below the beta floor ($BetaVersionFloor). Rebuild with scripts\build-production-apk.ps1 -Channel beta so the number lands in the beta band."
}
if ($Channel -eq 'prod' -and $versionCode -gt $ProdVersionCeiling) {
    throw "Prod build number $versionCode is inside the beta band (> $ProdVersionCeiling). Publishing it to the prod manifest would send beta builds to production phones."
}

Write-Host "Publishing [$Channel] v$versionName+$versionCode to GitHub..." -ForegroundColor Green

$apkFiles = @(
    @{ Abi = 'arm64-v8a'; FileName = 'app-arm64-v8a-release.apk'; Path = $arm64Apk },
    @{ Abi = 'armeabi-v7a'; FileName = 'app-armeabi-v7a-release.apk'; Path = $armApk }
)

$releaseResult = Publish-GitHubReleaseApks `
    -Config $config `
    -VersionName $versionName `
    -VersionCode $versionCode `
    -ReleaseNotes $ReleaseNotes `
    -ApkFiles $apkFiles `
    -Channel $Channel

# Beta is not forced. A forced update on a test build strands a tester who
# cannot get through the flow, and the whole point of the channel is that a
# tester can walk away from a bad build.
$forceUpdate = if ($Channel -eq 'beta') { $false } else { $true }

$manifestJson = Build-UpdateManifest `
    -AppId $config.APP_ID `
    -VersionName $versionName `
    -VersionCode $versionCode `
    -ReleaseNotes $ReleaseNotes `
    -ApkEntries $releaseResult.ApkEntries `
    -ForceUpdate $forceUpdate `
    -Channel $Channel

$outDir = Join-Path $rootDir 'out'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

# Per-channel out files, so publishing beta does not overwrite the record of
# what production last shipped.
$ChannelSuffix = if ($Channel -eq 'beta') { '-beta' } else { '' }
$manifestPath = Join-Path $outDir "manifest$($ChannelSuffix).json"

function Write-Utf8NoBomFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Content
    )
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
}

Write-Utf8NoBomFile -Path $manifestPath -Content $manifestJson

# Mirrors the remote layout, so the local seed copy sits where the file it
# mirrors actually lives. `ota\beta\` is created on demand.
$otaLocalPath = if ($Channel -eq 'beta') {
    Join-Path $rootDir 'ota\beta\manifest.json'
} else {
    Join-Path $rootDir 'ota\manifest.json'
}
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $otaLocalPath) | Out-Null
Write-Utf8NoBomFile -Path $otaLocalPath -Content $manifestJson

Write-Host 'Updating manifest on GitHub...' -ForegroundColor Cyan
$manifestResult = Update-GitHubManifestFile `
    -Config $config `
    -ManifestJson $manifestJson `
    -CommitMessage "OTA release [$Channel] $versionName+$versionCode" `
    -Channel $Channel

$audit = [ordered]@{
    published_at  = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    channel       = $Channel
    version_name  = $versionName
    version_code  = $versionCode
    release_tag   = $releaseResult.TagName
    release_notes = $ReleaseNotes
    manifest_url  = $manifestResult.ManifestUrl
    apks          = $releaseResult.ApkEntries
}
$auditPath = Join-Path $outDir ("last-publish$($ChannelSuffix).json")
Write-Utf8NoBomFile -Path $auditPath -Content ($audit | ConvertTo-Json -Depth 6 -Compress)

Write-Host ''
Write-Host 'Publish complete!' -ForegroundColor Green
Write-Host "  Channel:      $Channel"
Write-Host "  Manifest URL: $($manifestResult.ManifestUrl)"
Write-Host "  Release tag:  $($releaseResult.TagName)"
Write-Host "  Releases URL: https://github.com/$($config.GITHUB_OWNER)/$($config.GITHUB_REPO)/releases/latest" -ForegroundColor Cyan
Write-Host "  Local manifest: $manifestPath"
Write-Host "  Audit log: $auditPath"
Write-Host ''
Write-Host 'Ensure app builds use:' -ForegroundColor Yellow
Write-Host "  --dart-define=UPDATE_MANIFEST_URL=$($manifestResult.ManifestUrl)"
