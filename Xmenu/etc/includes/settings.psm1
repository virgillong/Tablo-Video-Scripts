$settingsFile = Join-Path $env:rootDir "data\settings.json"

function Save-Settings {
    param(
          [psobject]$Settings
    )

    $Settings |
        ConvertTo-Json |
        Set-Content $settingsFile
}

function Import-Settings {

    if (-not (Test-Path $settingsFile)) {
        return $null
    }

    Get-Content $settingsFile -Raw | ConvertFrom-Json
}
Export-ModuleMember -Function Save-Settings, Import-Settings