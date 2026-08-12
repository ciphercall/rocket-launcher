function Update-GitHubManifestFile {
    param(
        [hashtable]$Config,
        [string]$ManifestJson,
        [string]$CommitMessage
    )

    $owner = $Config.GITHUB_OWNER
    $repo = $Config.GITHUB_REPO
    $branch = if ($Config.GITHUB_BRANCH) { $Config.GITHUB_BRANCH } else { 'main' }
    $path = 'ota/manifest.json'
    $uri = "https://api.github.com/repos/$owner/$repo/contents/$path"

    $headers = @{
        Authorization = "Bearer $($Config.GITHUB_PAT)"
        Accept        = 'application/vnd.github+json'
        'X-GitHub-Api-Version' = '2022-11-28'
    }

    $existingSha = $null
    try {
        $existing = Invoke-RestMethod -Method Get -Uri "$uri`?ref=$branch" -Headers $headers
        $existingSha = $existing.sha
    } catch {
        # File does not exist yet on remote.
    }

    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    $contentBytes = $utf8NoBom.GetBytes($ManifestJson)
    $contentBase64 = [Convert]::ToBase64String($contentBytes)

    $body = @{
        message = $CommitMessage
        content = $contentBase64
        branch  = $branch
    }
    if ($existingSha) {
        $body.sha = $existingSha
    }

    $jsonBody = $body | ConvertTo-Json
    $result = Invoke-RestMethod -Method Put -Uri $uri -Headers $headers -Body $jsonBody -ContentType 'application/json; charset=utf-8'

    $manifestUrl = if ($Config.UPDATE_MANIFEST_URL) {
        $Config.UPDATE_MANIFEST_URL
    } else {
        "https://raw.githubusercontent.com/$owner/$repo/$branch/ota/manifest.json"
    }

    return [pscustomobject]@{
        ManifestUrl = $manifestUrl
        CommitSha     = $result.commit.sha
    }
}
