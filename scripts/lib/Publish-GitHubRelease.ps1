function Get-GitHubApiHeaders {
    param([string]$Token)
    return @{
        Authorization = "Bearer $Token"
        Accept        = 'application/vnd.github+json'
        'X-GitHub-Api-Version' = '2022-11-28'
    }
}

function New-GitHubRelease {
    param(
        [hashtable]$Config,
        [string]$TagName,
        [string]$ReleaseName,
        [string]$ReleaseNotes
    )

    $owner = $Config.GITHUB_OWNER
    $repo = $Config.GITHUB_REPO
    $uri = "https://api.github.com/repos/$owner/$repo/releases"

    $body = @{
        tag_name = $TagName
        name     = $ReleaseName
        body     = $ReleaseNotes
        draft    = $false
        prerelease = $false
    } | ConvertTo-Json

    try {
        return Invoke-RestMethod -Method Post -Uri $uri -Headers (Get-GitHubApiHeaders -Token $Config.GITHUB_PAT) -Body $body -ContentType 'application/json; charset=utf-8'
    } catch {
        $err = $_.ErrorDetails.Message
        if ($err -match 'already_exists|Reference already exists') {
            $listUri = "https://api.github.com/repos/$owner/$repo/releases/tags/$TagName"
            return Invoke-RestMethod -Method Get -Uri $listUri -Headers (Get-GitHubApiHeaders -Token $Config.GITHUB_PAT)
        }
        throw "Failed to create GitHub release $TagName`: $err"
    }
}

function Upload-GitHubReleaseAsset {
    param(
        [hashtable]$Config,
        [int]$ReleaseId,
        [string]$FilePath,
        [string]$AssetName
    )

    $owner = $Config.GITHUB_OWNER
    $repo = $Config.GITHUB_REPO
    $uploadUri = "https://uploads.github.com/repos/$owner/$repo/releases/$ReleaseId/assets?name=$AssetName"

    $bytes = [System.IO.File]::ReadAllBytes($FilePath)
    $headers = Get-GitHubApiHeaders -Token $Config.GITHUB_PAT
    $headers['Content-Type'] = 'application/vnd.android.package-archive'

    try {
        return Invoke-RestMethod -Method Post -Uri $uploadUri -Headers $headers -Body $bytes
    } catch {
        throw "Failed to upload $AssetName`: $($_.ErrorDetails.Message)"
    }
}

function Get-GitHubReleaseDownloadUrl {
    param(
        [hashtable]$Config,
        [string]$TagName,
        [string]$FileName
    )
    $owner = $Config.GITHUB_OWNER
    $repo = $Config.GITHUB_REPO
    return "https://github.com/$owner/$repo/releases/download/$TagName/$FileName"
}

function Publish-GitHubReleaseApks {
    param(
        [hashtable]$Config,
        [string]$VersionName,
        [int]$VersionCode,
        [string]$ReleaseNotes,
        [array]$ApkFiles
    )

    $tagName = "v$VersionName-build$VersionCode"
    $releaseName = "$VersionName+$VersionCode"

    Write-Host "Creating GitHub release $tagName..." -ForegroundColor Cyan
    $release = New-GitHubRelease -Config $Config -TagName $tagName -ReleaseName $releaseName -ReleaseNotes $ReleaseNotes

    $apkEntries = @{}
    foreach ($apk in $ApkFiles) {
        Write-Host "Uploading $($apk.FileName)..." -ForegroundColor Cyan
        Upload-GitHubReleaseAsset -Config $Config -ReleaseId $release.id -FilePath $apk.Path -AssetName $apk.FileName | Out-Null
        $url = Get-GitHubReleaseDownloadUrl -Config $Config -TagName $tagName -FileName $apk.FileName
        $apkEntries[$apk.Abi] = [ordered]@{
            url        = $url
            size_bytes = (Get-Item -LiteralPath $apk.Path).Length
            sha256     = (Get-FileSha256Hex -Path $apk.Path)
        }
        Write-Host "  -> $url" -ForegroundColor DarkGray
    }

    return [pscustomobject]@{
        TagName    = $tagName
        ReleaseId  = $release.id
        ApkEntries = $apkEntries
    }
}
