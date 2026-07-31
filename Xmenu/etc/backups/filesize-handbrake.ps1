Add-Type -AssemblyName 'System.Windows.Forms'
Add-Type -AssemblyName 'System.Drawing'
Import-Module ThreadJob

# Default path fallback for rootDir
if (-not $env:rootDir) {
    $env:rootDir = (Resolve-Path "$PSScriptRoot\..").Path
}
$rootDir = $env:rootDir 

Import-Module (Join-Path $rootDir "etc\includes\UIHelpers.psm1") -Force

# Check for ffmpeg in PATH
if (-not (Get-Command ffmpeg -ErrorAction SilentlyContinue)) {
    [System.Windows.Forms.MessageBox]::Show("FFmpeg not found. Ensure it is in your PATH.", "Error", "OK", "Error")
    return
}

# Converts user input like 400MB or 2GB into bytes
function Convert-ToBytes($sizeStr) {
    if ($sizeStr -match '^\d+$') {
        return [int64]$sizeStr
    } elseif ($sizeStr -match '^(\d+)(MB|GB)$') {
        $value = [int]$matches[1]
        switch ($matches[2]) {
            'MB' { return $value * 1MB }
            'GB' { return $value * 1GB }
        }
    } else {
        throw "Invalid size format. Use numeric bytes or format like 400MB."
    }
}

$themeFile = Join-Path $rootDir "data\theme.txt"
$currentMode = Import-ThemeState -themeFile $themeFile
$videoConvFilePath = Join-Path $rootDir "data\videoconv.txt"
$videoSizedFilePath = Join-Path $rootDir "data\videosized.txt"
$videoDestFilePath = Join-Path $rootDir "data\videoconv.txt"

$DefaultSize = "400MB"
$DefaultMaxJobs = "2"

if (Test-Path -Path $videoConvFilePath) {
   $DefaultInputDir  = (Get-Content -Path $videoConvFilePath -Raw).Trim()
} else {
    $DefaultInputDir  = ""
}

if (Test-Path -Path $videoDestFilePath){ 
    $DefaultDest     = (Get-Content -Path $videoDestFilePath -Raw).Trim() 
} else {
    $DefaultDest     = "" 
}


# --- Build Form ---
$form = New-Object Windows.Forms.Form
$form.Text = "Reduce Video Size using Handbrake"
$form.Width = 520
$form.Height = 350
$form.StartPosition = 'CenterScreen'
$form.TopMost = $true
Set-FormTheme -Form $form -Mode $currentMode

# Input Dir Label & Textbox
$labelInputDir = New-Object Windows.Forms.Label
$labelInputDir.Text = "Input Directory:"
$labelInputDir.AutoSize = $true
$labelInputDir.Left = 10
$labelInputDir.Top = 20
Set-LabelStyle -Label $labelInputDir -Mode $currentMode

$textboxInputDir = New-Object Windows.Forms.TextBox
$textboxInputDir.Width = 350
$textboxInputDir.Left = 10
$textboxInputDir.Top = 40
$textboxInputDir.Text = $DefaultInputDir
Set-TextboxStyle -Textbox $textboxInputDir -Mode $currentMode

$browseInputDirButton = New-Object Windows.Forms.Button
$browseInputDirButton.Text = "Browse"
$browseInputDirButton.Width = 80
$browseInputDirButton.Left = 370
$browseInputDirButton.Top = 38
$browseInputDirButton.Add_Click({
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.SelectedPath = $textboxInputDir.Text
    $dialog.Description = "Select Input Directory"
    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $textboxInputDir.Text = $dialog.SelectedPath
    }
})
Set-ButtonStyle -Button $browseInputDirButton -Mode $currentMode

# Destination Dir Label & Textbox
$labelDest = New-Object Windows.Forms.Label
$labelDest.Text = "Destination Folder:"
$labelDest.AutoSize = $true
$labelDest.Left = 10
$labelDest.Top = 80
Set-LabelStyle -Label $labelDest -Mode $currentMode

$textboxDest = New-Object Windows.Forms.TextBox
$textboxDest.Width = 350
$textboxDest.Left = 10
$textboxDest.Top = 100
$textboxDest.Text = $DefaultDest
Set-TextboxStyle -Textbox $textboxDest -Mode $currentMode

$browseDestButton = New-Object Windows.Forms.Button
$browseDestButton.Text = "Browse"
$browseDestButton.Width = 80
$browseDestButton.Left = 370
$browseDestButton.Top = 98
$browseDestButton.Add_Click({
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.SelectedPath = $textboxDest.Text
    $dialog.Description = "Select Destination Folder"
    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $textboxDest.Text = $dialog.SelectedPath
    }
})
Set-ButtonStyle -Button $browseDestButton -Mode $currentMode

# Minimum Size Label & Textbox
$labelMinSize = New-Object Windows.Forms.Label
$labelMinSize.Text = "Minimum Size (e.g., 400MB or 100000000):"
$labelMinSize.AutoSize = $true
$labelMinSize.Left = 10
$labelMinSize.Top = 150
Set-LabelStyle -Label $labelMinSize -Mode $currentMode

$textboxMinSize = New-Object Windows.Forms.TextBox
$textboxMinSize.Width = 75
$textboxMinSize.Left = 250
$textboxMinSize.Top = 150
$textboxMinSize.Text = $DefaultSize
Set-TextboxStyle -Textbox $textboxMinSize -Mode $currentMode

# Maximumconcurrent jobs Label & Textbox
$labelMaxJobs = New-Object Windows.Forms.Label
$labelMaxJobs.Text = "Maximum Concurrent Jobs"
$labelMaxJobs.AutoSize = $true
$labelMaxJobs.Left = 10
$labelMaxJobs.Top = 180
Set-LabelStyle -Label $labelMaxJobs -Mode $currentMode

$textboxMaxJobs = New-Object Windows.Forms.TextBox
$textboxMaxJobs.Width = 75
$textboxMaxJobs.Left = 250
$textboxMaxJobs.Top = 180
$textboxMaxJobs.Text = $DefaultMaxJobs
Set-TextboxStyle -Textbox $textboxMaxJobs -Mode $currentMode

$labelVidQual = New-Object Windows.Forms.Label
$labelVidQual.Text = "Video Quality (CRF, 15-30):"
$labelVidQual.AutoSize = $true
$labelVidQual.Left = 10
$labelVidQual.Top = 210
Set-LabelStyle -Label $labelVidQual -Mode $currentMode

$textboxVidQual = New-Object Windows.Forms.TextBox
$textboxVidQual.Width = 50
$textboxVidQual.Left = 250
$textboxVidQual.Top = 210
$textboxVidQual.Text = "26"
Set-TextboxStyle -Textbox $textboxVidQual -Mode $currentMode

# OK Button
$okButton = New-Object Windows.Forms.Button
$okButton.Text = "OK"
$okButton.Width = 80
$okButton.Left = 200
$okButton.Top = 250
$okButton.Add_Click({ $form.Close() })
Set-ButtonStyle -Button $okButton -Mode $currentMode

$form.Controls.AddRange(@(
    $labelInputDir, $textboxInputDir, $browseInputDirButton,
    $labelDest, $textboxDest, $browseDestButton,
    $labelMinSize, $textboxMinSize,
    $labelMaxJobs, $textboxMaxJobs,
    $labelVidQual, $textboxVidQual,
    $okButton
))


$okButton.DialogResult = [System.Windows.Forms.DialogResult]::OK

# To also allow pressing Enter to trigger the OK button:
$form.AcceptButton = $okButton

# Use last button to determine needed height
$bottomMostButton = $okButton
$neededHeight = $bottomMostButton.Bottom + 50  # 50 = bottom padding

# Apply it after layout is finalized
$form.Height = $neededHeight


$dialogResult = $form.ShowDialog()


if ($dialogResult -ne [System.Windows.Forms.DialogResult]::OK) {
    return
}

# --- Validate Inputs ---
if (-not (Test-Path $textboxInputDir.Text)) {
    Write-Host "Invalid video directory."
    return
}
if ([string]::IsNullOrWhiteSpace($textboxDest.Text)) {
    Write-Host "Invalid destination directory."
    return
}

try {
    $minFileSizeBytes = Convert-ToBytes $textboxMinSize.Text
} catch {
    Write-Host "Error: $_"
    return
}

$inputDirectory = $textboxInputDir.Text
$outputDirectory = $textboxDest.Text
$maxConcurrentJobs = $textboxMaxJobs.Text

[int]$videoQuality = 0
if (-not [int]::TryParse($textboxVidQual.Text, [ref]$videoQuality) -or $videoQuality -lt 15 -or $videoQuality -gt 30) {
    [System.Windows.Forms.MessageBox]::Show("Please enter a valid Video Quality (CRF) between 15 and 30.","Invalid Input")
    return
}

Write-Host "Input: $inputDirectory"
Write-Host "Output: $outputDirectory"
Write-Host "Min File Size: $minFileSizeBytes bytes"
Write-Host "Max number of jobs: $maxConcurrentJobs"
Write-Host "Video Quality: $videoQuality"


Set-Content -Path $videoConvFilePath -Value $inputDirectory
Set-Content -Path $videoSizedFilePath -Value $outputDirectory

pause

# Create the output directory if needed
if (-not (Test-Path $outputDirectory)) {
    New-Item -ItemType Directory -Path $outputDirectory | Out-Null
}

$videoFiles = Get-ChildItem -Path $inputDirectory -Filter *.mp4
# $maxConcurrentJobs = 4
$i = 0
$total = $videoFiles.Count
$jobs = @()
$successCount = 0
$failCount = 0
$skippedCount = 0

foreach ($file in $videoFiles) {
    $i++
    $inputFilePath = $file.FullName
    $outputFilePath = Join-Path $outputDirectory $file.Name
    $inputFileName = $file.Name

    if ($file.Length -lt $minFileSizeBytes) {
        Write-Host "[$i/$total] Skipping (too small): $inputFileName"
        $skippedCount++
        continue
    }

    if (Test-Path $outputFilePath) {
        Write-Host "[$i/$total] Skipping (already exists): $inputFileName"
        $skippedCount++
        continue
    }

    # Wait for open slot, receiving finished jobs in the meantime
    while (($jobs | Where-Object { $_.State -in @('Running', 'NotStarted') }).Count -ge $maxConcurrentJobs) {
        $finished = $jobs | Where-Object { $_.State -eq 'Completed' }
        foreach ($fj in $finished) {
            $result = Receive-Job $fj
            $result | ForEach-Object { Write-Host $_ }

            if ($result -match "Finished:") {
                $successCount++
            } else {
                $failCount++
            }
            Remove-Job $fj
            $jobs = $jobs | Where-Object { $_.State -ne 'Completed' }
        }
        Start-Sleep -Seconds 1
    }

    # Start the job
    $job = Start-ThreadJob -Name $inputFileName -ScriptBlock {
        param ($inputPath, $outputPath)
        $handbrake = "HandBrakeCLI"
        $args = @(
            "--input", $inputPath,
            "--output", $outputPath,
            "-e", "x265",               # Video encoder
            "--x265-preset", "slow",    # Preset
            "-q", "26",                 # Quality (CRF-like)
            "-E", "av_aac",             # Audio encoder
            "-B", "128"                 # Audio bitrate kbps
        )

        & $handbrake @args

        if ($LASTEXITCODE -eq 0) {
            "Finished: $inputPath"
        } else {
            "Error with: $inputPath"
        }
    } -ArgumentList $inputFilePath, $outputFilePath

    $jobs += $job
    $activeCount = ($jobs | Where-Object { $_.State -in @('Running', 'NotStarted') }).Count
    Write-Host ""
    Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')][$i/$total] QUEUING: $inputFileName (Active: $activeCount)" -ForegroundColor Cyan -BackgroundColor Black
    Write-Host ""
    # Write-Host "[$i/$total] QUEUING: $inputFileName (Active: $activeCount)"
}

# Process any remaining jobs
while ($jobs) {
    $finished = $jobs | Where-Object { $_.State -eq 'Completed' }
    foreach ($fj in $finished) {
        $result = Receive-Job $fj
        $result | ForEach-Object { Write-Host $_ }

        if ($result -match "Finished:") {
            $successCount++
        } else {
            $failCount++
        }
        Remove-Job $fj
        $jobs = $jobs | Where-Object { $_.State -ne 'Completed' }
    }
    Start-Sleep -Seconds 1
}

Write-Host "`n--- Summary ---"
Write-Host "Total input videos: $total"
Write-Host "Successful conversions: $successCount"
Write-Host "Failed conversions: $failCount"
Write-Host "Skipped (already exists or too small): $skippedCount"
