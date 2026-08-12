function Build-UpdateManifest {
    param(
        [Parameter(Mandatory = $true)]
        [string]$AppId,
        [Parameter(Mandatory = $true)]
        [string]$VersionName,
        [Parameter(Mandatory = $true)]
        [int]$VersionCode,
        [Parameter(Mandatory = $true)]
        [string]$ReleaseNotes,
        [Parameter(Mandatory = $true)]
        [hashtable]$ApkEntries
    )

    $manifest = [ordered]@{
        app_id        = $AppId
        version_name  = $VersionName
        version_code  = $VersionCode
        force_update  = $true
        release_notes = $ReleaseNotes
        published_at  = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        apks          = $ApkEntries
    }

    return ($manifest | ConvertTo-Json -Depth 6)
}

function Get-FileSha256Hex {
    param([Parameter(Mandatory = $true)][string]$Path)
    $hash = Get-FileHash -LiteralPath $Path -Algorithm SHA256
    return $hash.Hash.ToLowerInvariant()
}
