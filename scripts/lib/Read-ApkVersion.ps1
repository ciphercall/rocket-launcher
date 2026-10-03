# Undoes Flutter's split-per-ABI offset so both APKs in a publish report the same
# logical build number.
#
# The offset is ADDED to the base, not prefixed onto it:
#   armeabi-v7a = base + 1000
#   arm64-v8a   = base + 2000
#   x86_64      = base + 3000
#
# So subtraction is the only correct inverse. `raw % 1000` happens to agree for a
# three-digit base (2104 % 1000 = 104) and silently breaks the moment the base has
# four digits: a beta build 9008 becomes 11008 on arm64, and 11008 % 1000 is 8 —
# a beta manifest advertising build 8, which every tester reads as "up to date".
#
# [AbiOffset] is the offset for the APK's own ABI, read from its `native-code`
# entry. Passing it is what makes this exact.
#
# No guessing when it is absent: subtracting an assumed offset from an unknown
# base turns 11008 into 6008 or 8008 depending on which one was assumed, and the
# resulting manifest would be wrong in a way nothing downstream would surface.
#
# Must stay in step with `normalizeVersionCode()` in
# Attandance_App\lib\models\app_update_manifest.dart.
function Normalize-VersionCode {
    param(
        [int]$RawCode,
        [int]$AbiOffset = 0
    )

    if ($AbiOffset -gt 0 -and $RawCode -ge $AbiOffset) {
        return $RawCode - $AbiOffset
    }

    return $RawCode
}

function Get-AbiOffset {
    param([string]$NativeCodeLine)

    if ($NativeCodeLine -match 'armeabi-v7a') { return 1000 }
    if ($NativeCodeLine -match 'arm64-v8a') { return 2000 }
    if ($NativeCodeLine -match 'x86_64') { return 3000 }
    return 0
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
            $nativeCode = ''
            foreach ($line in $output) {
                if ($line -match "package: name='([^']+)' versionCode='(\d+)' versionName='([^']+)'") {
                    $packageName = $Matches[1]
                    $versionCode = [int]$Matches[2]
                    $versionName = $Matches[3]
                }
                if ($line -match "native-code:\s*'([^']+)'") {
                    $nativeCode = $Matches[1]
                }
                if ($versionCode -ne $null -and $nativeCode -ne '') { break }
            }
            if ($versionCode -ne $null) {
                # Subtract this APK's own ABI offset. Guessing it is what made
                # four-digit build numbers normalise to garbage.
                $normalized = Normalize-VersionCode -RawCode $versionCode -AbiOffset (Get-AbiOffset -NativeCodeLine $nativeCode)
                return [pscustomobject]@{
                    PackageName = $packageName
                    VersionName = $versionName
                    VersionCode = $normalized
                    RawVersionCode = $versionCode
                    AbiOffset = Get-AbiOffset -NativeCodeLine $nativeCode
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
