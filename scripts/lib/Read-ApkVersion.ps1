function Normalize-VersionCode {
    param([int]$RawCode)
    if ($RawCode -ge 1000) { return $RawCode % 1000 }
    return $RawCode
}

function Read-ApkVersionInfo {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ApkPath
    )

    if (-not (Test-Path -LiteralPath $ApkPath)) {
        throw "APK not found: $ApkPath"
    }

    $aapt = Find-AaptExe
    if ($aapt) {
        $output = & $aapt dump badging $ApkPath 2>&1
        if ($LASTEXITCODE -eq 0) {
            $versionName = $null
            $versionCode = $null
            $packageName = $null
            foreach ($line in $output) {
                if ($line -match "package: name='([^']+)' versionCode='(\d+)' versionName='([^']+)'") {
                    $packageName = $Matches[1]
                    $versionCode = [int]$Matches[2]
                    $versionName = $Matches[3]
                    break
                }
            }
            if ($versionCode -ne $null) {
                $normalized = Normalize-VersionCode -RawCode $versionCode
                return [pscustomobject]@{
                    PackageName = $packageName
                    VersionName = $versionName
                    VersionCode = $normalized
                    RawVersionCode = $versionCode
                    Source      = 'aapt'
                }
            }
        }
    }

    $pubspec = Join-Path (Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent) 'Attandance_App\pubspec.yaml'
    if (Test-Path -LiteralPath $pubspec) {
        $content = Get-Content -LiteralPath $pubspec -Raw
        if ($content -match '(?m)^version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+(\d+)\s*$') {
            return [pscustomobject]@{
                PackageName = 'com.pphl.employee_attendance'
                VersionName = $Matches[1]
                VersionCode = [int]$Matches[2]
                Source      = 'pubspec'
            }
        }
    }

    throw "Could not read version from APK and pubspec fallback failed: $ApkPath"
}

function Find-AaptExe {
    $candidates = @()

    if ($env:ANDROID_HOME) {
        $candidates += Get-ChildItem -Path (Join-Path $env:ANDROID_HOME 'build-tools') -Filter 'aapt.exe' -Recurse -ErrorAction SilentlyContinue
    }
    if ($env:ANDROID_SDK_ROOT) {
        $candidates += Get-ChildItem -Path (Join-Path $env:ANDROID_SDK_ROOT 'build-tools') -Filter 'aapt.exe' -Recurse -ErrorAction SilentlyContinue
    }

    $localProps = Join-Path (Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent) 'Attandance_App\android\local.properties'
    if (Test-Path -LiteralPath $localProps) {
        foreach ($line in Get-Content -LiteralPath $localProps) {
            if ($line -match '^\s*sdk\.dir=(.+)$') {
                $sdkDir = $Matches[1].Trim().Replace('\\', '\')
                $candidates += Get-ChildItem -Path (Join-Path $sdkDir 'build-tools') -Filter 'aapt.exe' -Recurse -ErrorAction SilentlyContinue
            }
        }
    }

    $latest = $candidates | Sort-Object FullName -Descending | Select-Object -First 1
    if ($latest) { return $latest.FullName }
    return $null
}
