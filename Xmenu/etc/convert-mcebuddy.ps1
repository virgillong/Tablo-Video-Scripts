# -----------------------------
# Tablo → MP4 → MCEBuddy (GUI)
# $jobs = & $mcebuddyCLI --command=query --action=queue
# 
# $mcebuddyCLI = "C:\Program Files\MCEBuddy2x\MCEBuddy.UserCLI.exe"
# $mcebuddyCLI --command=addfile --action="\\hpdesktop\videos\Videos\mcebuddy_temp" | Out-Null
# Write-Host "RAW OUTPUT:"
# $jobs
#
# $mcebuddyCLI = "C:\Program Files\MCEBuddy2x\MCEBuddy.UserCLI.exe"
# $q = & $mcebuddyCLI --command=query --action=queue
# $q | ForEach-Object { "'$_'" }
#
# -----------------------------
Add-Type -AssemblyName 'System.Windows.Forms'
Add-Type -AssemblyName 'System.Drawing'
Import-Module Microsoft.PowerShell.ThreadJob

# Default path fallback for rootDir
if (-not $env:rootDir) {
    $env:rootDir = (Resolve-Path "$PSScriptRoot\..").Path
}
$rootDir = $env:rootDir 

Import-Module (Join-Path $rootDir "etc\includes\UIHelpers.psm1") -Force
Import-Module (Join-Path $rootDir "etc\includes\alert.psm1") -Force
Import-Module (Join-Path $rootDir "etc\includes\settings.psm1") -Force 
Import-Module (Join-Path $rootDir "etc\includes\addinputrow.psm1") -Force

# ------------------------------------------------------------------------
# Get-MCEBuddyTasks
# read MCEBuddy config file and retrieve and return as an PSCustomObject all task names defined
# along with the following parameters - Profile, Destination, WorkingPath. Enabled, MonitorTask 
# =========================================================================
function Get-MCEBuddyTasks {
    param(
        [string]$ConfigFile = "C:\Program Files\MCEBuddy2x\config\mcebuddy.conf"
    )
    $content = Get-Content $ConfigFile

    # Get task names from Engine section
    $taskLine = $content | Where-Object { $_ -match '^Tasks=' } | Select-Object -First 1

    if (-not $taskLine) {
        return @()
    }
    $taskNames = ($taskLine -replace '^Tasks=', '').Split(',').Trim()
    $tasks = @()
    foreach ($task in $taskNames) {
        $start = $content.IndexOf("[$task]")
        if ($start -lt 0) {
            continue
        }
        $section = @{}
        for ($i = $start + 1; $i -lt $content.Count; $i++) {
            $line = $content[$i]
            # Next section?

            if ($line -match '^\[') { break }

            if ($line -match '^(.+?)=(.*)$') {
                $section[$matches[1]] = $matches[2]
            }
        }
        $tasks += [PSCustomObject]@{
            Name        = $task
            Profile     = $section.Profile
            Destination = $section.DestinationPath
            WorkingPath = $section.WorkingPath
            Enabled     = ($section.Enabled -eq 'True')
            MonitorTask = $section.MonitorTaskNames
	    FileSelection = $section.FileSelection
        }
    }
    return $tasks
}

# ------------------------------------------------------------------------
# Get-MCEBuddyDestination
# read MCEBuddy config file and get the destination associated with the Task 
# passed to function
# =========================================================================
function Get-MCEBuddyDestination {
    param(
        [string]$ConfigFile,
        [string]$TaskName = "Tablo"
    )

    $inSection = $false

    foreach ($line in Get-Content $ConfigFile) {

        $line = $line.Trim()

        if ($line -match '^\[(.+)\]$') {
            $inSection = ($Matches[1] -eq $TaskName)
            continue
        }

        if ($inSection -and $line -match '^DestinationPath=(.*)$') {
            return $Matches[1]
        }
    }

    return $null
}

# ------------------------------------------------------------------------
# Get-MCEBuddyConversionTasks 
# read MCEBuddy config file and retrieve the tasks that are defined within
# the tasks= parameter
# =========================================================================
function Get-MCEBuddyConversionTasks {

    param(
        [string]$ConfigFile = "C:\Program Files\MCEBuddy2x\config\mcebuddy.conf"
    )

    if (-not (Test-Path $ConfigFile)) {
        throw "Cannot find $ConfigFile"
    }

    $line = Get-Content $ConfigFile |
        Where-Object { $_ -match '^Tasks=' } |
        Select-Object -First 1

    if (-not $line) {
        return @()
    }

    ($line -replace '^Tasks=', '').Split(',').Trim()
}


# $configFile = Join-Path (Split-Path $settings.MCEBuddyCLI) "config\mcebuddy.conf"
# $tasks = Get-MCEBuddyConversionTasks -ConfigFile $configFile
# $tasks = Get-MCEBuddyConversionTasks

# ------------------------------------------------------------------------
# Convert-ToBytes
# Converts user input like 400MB or 2GB into bytes
# =========================================================================
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
	Show-Alert -Message "Invalid size format. Use numeric bytes or format like 400MB."
        
    }
}

# ------------------------------------------------------------------------
# Restore-MCEBuddyOutputName
#
# Supported MCEBuddy FileSelection patterns
# *.Tag.ext
# Prefix*.ext
# *Tag*
# Prefix*
# *Suffix
#
# Keep this list synchronized with
# Get-MCEBuddyOutputName()
# =========================================================================
function Restore-MCEBuddyOutputName {

    param(
        [string]$FileName,
        [string]$FileSelection
    )

    $base = [IO.Path]::GetFileNameWithoutExtension($FileName)
    $ext  = [IO.Path]::GetExtension($FileName)

    if ([string]::IsNullOrWhiteSpace($FileSelection)) {
        return "$base$ext"
    }

    $FileSelection = $FileSelection.Trim()

    switch -Regex ($FileSelection) {

        # *.Tag.ext
        '^\*\.(.+)\.(\w+)$' {
            $base = $base -replace "\.$([regex]::Escape($matches[1]))$", ""
            $ext  = ".$($matches[2])"
        }

        # Prefix*.ext
        '^(.+)\*\.(\w+)$' {
            $base = $base -replace "^$([regex]::Escape($matches[1]))", ""
            $ext  = ".$($matches[2])"
        }

        # *Tag*
        '^\*(.+)\*$' {
            $base = $base -replace "\.$([regex]::Escape($matches[1]))$", ""
        }

        # Prefix*
        '^([^*]+)\*$' {
            $base = $base -replace "^$([regex]::Escape($matches[1]))", ""
        }

        # *Suffix
        '^\*([^*]+)$' {
            $base = $base -replace "$([regex]::Escape($matches[1]))$", ""
        }
    }

    return "$base$ext"
}


# =========================================================================


$themeFile = Join-Path $rootDir "data\theme.txt"
$currentMode = Import-ThemeState -themeFile $themeFile
$global:encoder = "FFmpeg"
$global:CancelProcessing = $false
$global:tempFilesWaiting = 0
$global:maxTempFilesWaiting = 3 

$settings = Import-Settings

if ($settings) {
    $MCEBuddyTask	    = $settings.MCEBuddyTask
    $global:MCEBuddyCLI	    = $settings.MCEBuddyCLI        
    $global:HandBrakeCLI    = $settings.HandBrakeCLI       
    $global:FFmpegPath	    = $settings.FFmpegPath             
    $DefaultVideoDir	    = $settings.SEGvideoDir
    $global:tempMp4Dir	    = $settings.TempMp4Dir
    $DefaultVideoQuality    = $settings.VideoQuality
    $DefaultProfileName	    = $settings.ProfileName
    $DefaultMaxJobs         = $settings.MaxJobs
    $DefaultAudioName	    = $settings.AudioOverride
    $DefaultPresetValue	    = $settings.Preset
}

$DefaultRunMode         = "fallback"

# Ensure temp folder exists (UNC ok)
if (-not (Test-Path $tempMp4Dir)) {
    New-Item -Path $tempMp4Dir -ItemType Directory | Out-Null
}

if ([string]::IsNullOrWhiteSpace($DefaultVideoDir)) {
    $DefaultVideoDir = "D:\Desktop\Tablo\rec" 
}   

if ([string]::IsNullOrWhiteSpace($DefaultVideoQuality)) {
    $DefaultVideoQuality = "23"
}


# --- Encoding Profiles ---
$profiles = @{
    "Fast + Compatible" = @{
        Video = @{
            FFmpeg    = "libx264"
            HandBrake = "x264"
            Quality   = 23
    }
        Audio = @{
            FFmpeg    = "aac"
            HandBrake = "av_aac"
            Bitrate   = 128
        }
    }

    "High Compression (x265)" = @{
        Video = @{
            FFmpeg    = "libx265"
            HandBrake = "x265"
            Quality   = 23
    }
        Audio = @{
            FFmpeg    = "aac"
            HandBrake = "av_aac"
            Bitrate   = 128
        }
    }

    "Music Quality" = @{
        Video = @{
            FFmpeg    = "libx264"
            HandBrake = "x264"
            Quality   = 23
    }
        Audio = @{
            FFmpeg    = "aac"
            HandBrake = "av_aac"
            Bitrate   = 256
        }
    }

    "Voice / Low Bandwidth" = @{
        Video = @{
            FFmpeg    = "libx264"
            HandBrake = "x264"
            Quality   = 23
    }
        Audio = @{
            FFmpeg    = "libopus"
            HandBrake = "opus"
            Bitrate   = 64
        }
    }

    "Future-Proof (AV1)" = @{
        Video = @{
            FFmpeg    = "svtav1"
            HandBrake = "svt_av1"
            Quality   = 35
    }
        Audio = @{
            FFmpeg    = "libopus"
            HandBrake = "opus"
            Bitrate   = 128
        }
    }

    "GPU Accelerated (NVIDIA H.264)" = @{
        Video = @{
            FFmpeg    = "h264_nvenc"
            HandBrake = "nvenc_h264"
            Quality   = 23
    }
        Audio = @{
            FFmpeg    = "aac"
            HandBrake = "av_aac"
            Bitrate   = 128
}
    }
}


# 1 = Mono
# 2 = Stereo
# 6 = 5.1
# 8 = 7.1

$audioOverride = @{
    "Stereo AAC" = @{
        FFmpeg = "aac"
        HandBrake = "av_aac"
        Channels = 2
        Bitrate = 128
    }
    
    "Surround Sound ac3" = @{
        FFmpeg = "ac3"
        HandBrake = "ac3"
        Bitrate = 448
    }

    "Stereo Opus" = @{
        FFmpeg = "libopus"
        HandBrake = "opus"
        Channels = 2
        Bitrate = 96
    }

    "None" = @{}
    }


$presets = [ordered]@{
    "Ultrafast" = "ultrafast"
    "Super Fast" = "superfast"
    "Very Fast" = "veryfast"
    "Faster" = "faster"
    "Fast" = "fast"
    "Medium (Default)" = "medium"
    "Slow (Recommended)" = "slow"
    "Slower" = "slower"
    "Very Slow (Best Compression)" = "veryslow"
}


function Update-TaskInfo {

    $selectedTask = $comboBoxTasks.SelectedItem
   
    if ($null -ne $selectedTask) {

        $labelDest.Text = "Destination: $($selectedTask.Destination)"
        $labelTaskProfile.Text = "Profile: $($selectedTask.Profile)"
        $labelTaskMonitor.Text = "Task Monitor: $($selectedTask.MonitorTask)"
        $labelEnabled.Text = "Enabled: $($selectedTask.Enabled)"
        $labelFileFilter.Text = "File Filter: $($selectedTask.FileSelection)"

        # FileSelection warnings
        if ([string]::IsNullOrWhiteSpace($selectedTask.FileSelection)) {
            $labelFileFilter.ForeColor = [System.Drawing.Color]::Red
            $labelFileFilter.Text = "File Filter: (none - accepts all matching files)"
        }
        elseif ($selectedTask.FileSelection -in @("*.mp4","*.MP4","*")) {
            $labelFileFilter.ForeColor = [System.Drawing.Color]::Red
        }
        else {
            $labelFileFilter.ForeColor = [System.Drawing.Color]::White
        }

    } else {

        $labelDest.Text = "Destination:"
        $labelTaskProfile.Text = "Profile:"
        $labelTaskMonitor.Text = "Task Monitor:"
        $labelEnabled.Text = "Enabled:"
        $labelFileFilter.Text = "File Filter:"
        $labelFileFilter.ForeColor = [System.Drawing.Color]::White
    }
}


$tasks = Get-MCEBuddyTasks
# $tasks

# $DefaultDest = $tasks.Destination
# $DefaultTaskProfile = $tasks.Profile
# $DefaultTaskMonitor = $tasks.MonitorTask

$formHght = 850
$formWidth = 1400
$listViewHght = 320

# --- Form ---
$form = New-Object System.Windows.Forms.Form
$form.Font = $global:FontRegular
$form.Text = "Join/Re-encode video files ts → mp4 ffmpeg/MCEBuddy"
$form.Size = New-Object System.Drawing.Size($formWidth,$formHght)
$form.StartPosition = "CenterScreen"
Set-FormTheme -Form $form -Mode $currentMode

$topStrt = 20
$spacing = 40
$top = $topstrt

# --- Enabled ---
$null, $labelEnabled = Add-InputRow $form "Enabled:"   $top "$null"
$labelEnabled.Left = $global:labelLeft2 + 200
$labelEnabled.Font = New-Object System.Drawing.Font('Arial', 12)
# $labelEnabled.ForeColor = [System.Drawing.Color]::Black

$top = (.5*$spacing) + $topstrt

# --- Profile ---
$null, $labelTaskProfile = Add-InputRow $form "Profile:"   $top "$null"
$labelTaskProfile.Left = $global:labelLeft2 + 200
$labelTaskProfile.Font = New-Object System.Drawing.Font('Arial', 12)
# $labelTaskProfile.ForeColor = [System.Drawing.Color]::Black

$top = (1*$spacing) + $topstrt

# --- Destination folder ---
$null, $labelDest = Add-InputRow $form "Destination:"   $top "$null"
$labelDest.Left = $global:labelLeft2 + 200
$labelDest.Font = New-Object System.Drawing.Font('Arial', 12)
# $labelDest.ForeColor = [System.Drawing.Color]::Black


$top = (1.5*$spacing) + $topstrt

# --- Task Monitor ---
$null, $labelTaskMonitor = Add-InputRow $form "Profile:"   $top "$null"
$labelTaskMonitor.Left = $global:labelLeft2 + 200
$labelTaskMonitor.Font = New-Object System.Drawing.Font('Arial', 12)
# $labelTaskMonitor.ForeColor = [System.Drawing.Color]::Black


$top = (2*$spacing) + $topstrt

# --- File Filters ---
$null, $labelFileFilter = Add-InputRow $form "File Filter:"   $top "$null"
$labelFileFilter.Left = $global:labelLeft2 + 200
$labelFileFilter.Font = New-Object System.Drawing.Font('Arial', 12)


$topStrt = 120
$spacing = 50
$top = $topstrt


$comboBoxTasks , $labelTasks  = Add-InputRow $form  "MCEbuddy Tasks"   $top "combobox"
$comboBoxTasks.Size = New-Object System.Drawing.Size(200, 30)
$comboBoxTasks.DataSource = $null
$comboBoxTasks.DisplayMember = "Name"
$comboBoxTasks.DataSource = [System.Collections.ArrayList]$tasks
if ($comboBoxTasks.Items.Count -gt 0) {
     $comboBoxTasks.SelectedIndex = 1
}

Update-TaskInfo

$top = (1*$spacing) + $topstrt

# --- Folder selection ---
$textboxVideoDir, $labelVideoDir = Add-InputRow $form "Videos folder:"  $top "textbox"
$textboxVideoDir.text = $DefaultVideoDir

$browseVideoDir, $null = Add-InputRow $form ""   $top "browse"
$browseVideoDir.Add_Click({
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $textboxVideoDir.Text = $dlg.SelectedPath
    }
})

$top = (2*$spacing) + $topstrt

# Maximumconcurrent jobs Label & Textbox
$textboxMaxJobs , $labelMaxJobs  = Add-InputRow $form "Max Concurrent Jobs:"   $top "textbox"
$textboxMaxJobs.Text = $DefaultMaxJobs
$textboxMaxJobs.Width = 35
$textboxMaxJobs.Left = $global:labelLeft + $labelMaxJobs.Width

$comboBoxRunMode , $labelrunMode = Add-InputRow $form "FFmpeg Run Mode:"   $top "combobox"
$labelrunMode.Left = $global:labelLeft + $labelMaxJobs.Width + $textboxMaxJobs.Width + 20
$comboBoxRunMode.Left = $global:labelLeft + $labelMaxJobs.Width + $textboxMaxJobs.Width + 20 + $labelrunMode.Width
$comboBoxRunMode.Width = 475
$comboBoxRunMode.DropDownStyle = 'DropDownList'
# Map friendly names to internal values
$runModeDisplayMap = @{ 
    "FFmpeg Copy/Re-encode on failure -> MCEBuddy" = "fallback"
    "FFmpeg Copy -> MCEBuddy" = "fast" 
}
$comboBoxRunMode.Items.AddRange(@($runModeDisplayMap.Keys))
# $comboBoxRunMode.Items.AddRange(@("FFmpeg Copy -> MCEBuddy", "FFmpeg Copy/Re-encode on failure -> MCEBuddy"))
$comboBoxRunMode.Text = ($runModeDisplayMap.Keys | Where-Object { 
    $runModeDisplayMap[$_] -eq $DefaultRunMode 
})

$top = (3*$spacing) + $topstrt

# Seperator
$CheckboxEnc, $label = Add-InputRow $form "" $top "checkbox"
$CheckboxEnc.text = "FFmpeg Encoding Parameters _________________________________________________________"
# $null , $label  = Add-InputRow $form "Encoding Parameters  _____________________________________________________________________________________________________________"   $top "$null"

$top = (4*$spacing) + $topstrt

# Video Quality Label & Textbox
$textboxVidQual , $labelVidQual  = Add-InputRow $form "Video Quality (CRF, 15-30):"   $top "textbox"
$textboxVidQual.Width = 30
$textboxVidQual.Left = $labelLeft + $labelVidQual.Width 
$textboxVidQual.Text = $DefaultVideoQuality

# Video Profile
$comboProfile , $labelProfile  = Add-InputRow $form "Video Profile:"   $top "combobox"
$labelProfile.Left = $global:labelLeft2
$comboProfile.Left = $global:labelLeft2 + $labelProfile.Width
$comboProfile.Size     = New-Object System.Drawing.Size(250, 30)
$comboProfile.Items.AddRange([string[]]$profiles.Keys)
$comboProfile.SelectedItem = $DefaultProfileName

$top = (5*$spacing) + $topstrt

# Label encoder preset
$comboBoxPreset , $labelPreset  = Add-InputRow $form  "Encoder Preset:"   $top "combobox"
$comboBoxPreset.Left = $global:labelLeft + $labelPreset.Width
$comboBoxPreset.Size = New-Object System.Drawing.Size(230,30)
$comboBoxPreset.Items.AddRange([string[]]$presets.Keys)
$comboBoxPreset.SelectedItem = $DefaultPresetValue

# Label audio override
$comboBoxAudio , $labelAudio  = Add-InputRow $form  "Audio Override:"   $top "combobox"
$labelAudio.Left = $global:labelLeft2
$comboBoxAudio.Left = $global:labelLeft2 + $labelAudio.Width
$comboBoxAudio.Size = New-Object System.Drawing.Size(250,30)
$comboBoxAudio.Items.AddRange([string[]]$audioOverride.Keys)
$comboBoxAudio.SelectedItem = $DefaultAudioName

$top = (7*$spacing) + $topstrt

# --- Start button ---
$btnStart, $null = Add-InputRow $form ""   $top "button"
$btnStart.Text = "Start Processing"
$btnStart.Location = New-Object System.Drawing.Point($global:labelLeft, $top)
$btnStart.Width = $buttonwidth + 30


# --- Cancel button ---
$btnCancel, $null = Add-InputRow $form ""   1000 "button"
$btnCancel.Text = "Cancel Processing"
$btnCancel.Width = $buttonwidth + 30
$btnCancel.Left = $global:labelLeft + 650
$btnCancel.Top = $top
$btnCancel.Enabled = $false

$top = (8*$spacing-10) + $topstrt

# --- ListView for job status ---
$listView = New-Object System.Windows.Forms.ListView
$listView.Location = New-Object System.Drawing.Point($global:labelLeft,$top)
$listView.Size = New-Object System.Drawing.Size($formWidth,$listViewHght)
$listView.View = 'Details'
$listView.FullRowSelect = $true
$listView.GridLines = $true
[void]$listView.Columns.Add("Folder",420)
[void]$listView.Columns.Add("Destination MP4",420)
[void]$listView.Columns.Add("Copy Status",140)
[void]$listView.Columns.Add("Encode Status",140)
[void]$listView.Columns.Add("MCEBuddy Status",140)
[void]$listView.Columns.Add("Counter",90) 
Set-ListViewStyle -ListView $listView -Mode $currentMode
$form.Controls.Add($listView)


function EncParamDisplay {

    $isVisible = $CheckboxEnc.Checked
    $labelVidQual.Visible = $textboxVidQual.Visible =  $isVisible
    $labelProfile.Visible = $comboProfile.Visible =  $isVisible
    $labelPreset.Visible = $comboBoxPreset.Visible =  $isVisible
    $labelAudio.Visible =  $comboBoxAudio.Visible =  $isVisible
    if ($isVisible) {
	$top = (7*$spacing) + $topstrt
	$btnStart.Top = $top
	$btnCancel.Top = $top
	$top = (8*$spacing) + $topstrt
	$listView.Top = $top
    } else {
	$top = (4*$spacing-10) + $topstrt
	$btnStart.Top = $top
	$btnCancel.Top = $top
	$top = (5*$spacing) + $topstrt
	$listView.Top = $top
    }
}

EncParamDisplay

#
# CheckboxEnc.Add_CheckedChanged
#
#
$CheckboxEnc.Add_CheckedChanged({
    EncParamDisplay
})


# ----------------------
# Button Cancel Event
# ----------------------
$btnCancel.Add_Click({

    # Prevent any new work
    $global:CancelProcessing = $true

    # Stop the worker thread
    Get-Job -Name ProcessFolders -ErrorAction SilentlyContinue |
        Stop-Job -PassThru |
        Remove-Job -Force

    # Kill any running ffmpeg
    Get-Process ffmpeg -ErrorAction SilentlyContinue |
        Stop-Process -Force

    # Stop updating the UI
    $timer.Stop()

    # Reset globals
    $global:tempFilesWaiting = 0
    $cleaned.Clear()

    # Optional - remove unfinished temp mp4 files
    Get-ChildItem $tempMp4Dir -Filter *.mp4 | Remove-Item -Force

    # Reset UI
    $listView.Items.Clear()
    $btnStart.Enabled  = $true
    $btnCancel.Enabled = $false

})


# comboBoxTasks.Add_SelectedIndexChanged
#   Index Changed for comboBoxTasks
#
$comboBoxTasks.Add_SelectedIndexChanged({
    Update-TaskInfo
    
    $task = $comboBoxTasks.SelectedItem
    
    # if ($null -ne $task) {
     #   if ($task.FileSelection -eq "*.mp4") {
     #       $labelFileFilter.ForeColor = [System.Drawing.Color]::Red
      #  }
      #  else {
      #      $labelFileFilter.ForeColor = [System.Drawing.Color]::Black
       # }
   # }
    
})


$btnStart.DialogResult = [System.Windows.Forms.DialogResult]::OK
$form.AcceptButton = $btnStart

# ----------------------
# Button Start Event
# ----------------------
$btnStart.Add_Click({

    # --- Read inputs directly from GUI ---
    $videoDir			    = $textboxVideoDir.Text.Trim()
    $global:videoQuality	    = $textboxVidQual.Text.Trim()
    $global:maxConcurrentJobs	    = [int]$textboxMaxJobs.Text
    $global:selectedMCEBuddyTask    = $comboBoxTasks.SelectedItem
    $global:runMode		    = $runModeDisplayMap[$comboBoxRunMode.Text]

    if ($null -eq $global:selectedMCEBuddyTask) {
	Show-Alert "No MCEBuddy task has been selected."
	return
    }

    if ($global:selectedMCEBuddyTask.FileSelection -eq "*.mp4") {
	Show-Alert "Warning: This task accepts every MP4 file."
    }

    if ($null -eq $global:selectedMCEBuddyTask) {
	Show-Alert "No MCEBuddy task has been selected."
	return
    }

    if (-not $global:selectedMCEBuddyTask.Enabled) {
	Show-Alert "Error: This task is not enabled in MCEBuddy."
	return
    }

    if ([string]::IsNullOrWhiteSpace($global:selectedMCEBuddyTask.FileSelection)) {
	Show-Alert "Warning: This task has no FileSelection filter set."
    }

    # Get Encoding Profile delected
    $global:selectedEncodingProfile = $comboProfile.SelectedItem
    $global:encodingProfile = $profiles[$global:selectedEncodingProfile]

    # Get audio override selected
    $global:selectedAudioProfile = $comboBoxAudio.SelectedItem
    $global:audioProfile =$audioOverride[$global:selectedAudioProfile]

    # Get preset selected
    $global:selectedPresetValue = $presets[$comboBoxPreset.SelectedItem]

    Write-Host "Using Encoder: $global:encoder "
    Write-Host Selected Encoding Profile: $global:selectedEncodingProfile
    switch ($encoder) {
	"Handbrake" {
	    Write-Host Video: $global:encodingProfile.Video.HandBrake
	    Write-Host Audio: $global:encodingProfile.Audio.HandBrake
	}	
	"FFmpeg" {
	    Write-Host Video: $global:encodingProfile.Video.FFmpeg
	    Write-Host Audio: $global:encodingProfile.Audio.FFmpeg
	}
    }	
    Write-Host Encoder Bitrate: $global:encodingProfile.Audio.Bitrate
    Write-Host Encoder Video Quality: $global:encodingProfile.Video.Quality
    Write-Host Selected Audio Override Profile: $global:selectedAudioProfile
    if ($selectedAudioProfile -ne "None") {
	switch ($encoder) {
	    "Handbrake" {
		Write-Host Override Audio: $global:audioProfile.HandBrake
	    }
	    "FFmpeg" {
		Write-Host  Override Audio: $global:audioProfile.FFmpeg
	    }
	}	
    }
    Write-Host $global:runMode
    Write-Host  "Override Audio Channels: $global:audioProfile.Channels"
    Write-Host  Override Audio Bitrate: $global:audioProfile.Bitrate
    Write-Host "Preset:  $global:selectedPresetValue"

    # --- Validation ---
    if ([string]::IsNullOrWhiteSpace($videoDir) -or -not (Test-Path $videoDir)) {
	Show-Alert -Title "Invalid Video Directory" -Message "Please select a valid video directory."
        $form.DialogResult = [System.Windows.Forms.DialogResult]::None
        return
    }

    if (-not [int]::TryParse($global:videoQuality, [ref]$null) -or
        [int]$global:videoQuality -lt 15 -or [int]$global:videoQuality -gt 30) {
	Show-Alert -Title "Invalid Input"-Message "Please enter a valid Video Quality (CRF) number between 15 and 30."
        $form.DialogResult = [System.Windows.Forms.DialogResult]::None
	return
    }

   $settings = Import-Settings

    $settings.SEGvideoDir      = $videoDir
    $settings.VideoQuality  = $global:videoQuality
    $settings.ProfileName   = $global:selectedEncodingProfile
    $settings.MaxJobs       = $global:maxConcurrentJobs
    $settings.AudioOverride = $global:selectedAudioProfile
    $settings.Preset        = $comboBoxPreset.SelectedItem



   Save-Settings $settings 

    # --- Prepare logs directory ---
    $global:logDir = Join-Path $PSScriptRoot "logs"
    if (-not (Test-Path $global:logDir)) {
        New-Item -ItemType Directory -Path $global:logDir | Out-Null
    }

    $btnStart.Enabled  = $false
    $btnCancel.Enabled = $true
    $global:CancelProcessing = $false


    # Start a single background thread to process folders sequentially
    $global:processJob = Start-ThreadJob -Name "ProcessFolders" -ScriptBlock {
	param(
            $videoDir,
	    $logDir,
	    $runMode,
            $tempMp4Dir,
            $formRef,
            $listRef,
            [ref]$tempFilesWaitingRef,
	    $maxTempFilesWaiting,
	    $videoQuality,
	    $encoder,  # $profiles,
	    $encodingProfile,
	    $selectedEncodingProfile,
	    $audioProfile,		
	    $selectedAudioProfile,
	    $selectedPresetValue,
	    $ffmpegPath,
	    $mcebuddyCLI,
	    $selectedMCEBuddyTask,
	    $CancelProcessing,
	    $rootDir
        )


        # Ensure engine is running (idempotent)
        try { & $mcebuddyCLI --command=engine --action=start | Out-Null; Start-Sleep -Seconds 2 } catch {}

        Get-ChildItem -Path $videoDir -Directory | ForEach-Object {
            $folder     = $_.FullName
            $folderName = $_.Name
            $segsDir    = Join-Path $folder "segs"
	    $logFile    = Join-Path $global:logDir "$folderName.log"

	    if ($CancelProcessing) {
		break
	    }

            if (-not (Test-Path $segsDir)) { return }

            $tsFiles = Get-ChildItem -Path $segsDir -Filter "*.ts" | Sort-Object Name
            if ($tsFiles.Count -eq 0) { return }

	    $mylistPath  = Join-Path $segsDir "concat.txt"


	    function Get-MCEBuddyOutputName {
		param(
		    [string]$BaseName,
		    [string]$Extension,
		    [string]$FileSelection
		)

		if ([string]::IsNullOrWhiteSpace($FileSelection)) {
		    return "$BaseName$Extension"
		}

		# *text*
		if ($FileSelection -match '^\*(.+)\*$') {
		    return "$BaseName.$($matches[1])$Extension"
		}

		# *.something.ext
		if ($FileSelection -match '^\*\.(.+)\.(\w+)$') {
		    return "$BaseName.$($matches[1]).$($matches[2])"
		}

		# prefix*.ext
		if ($FileSelection -match '^(.+)\*\.(\w+)$') {
		    return "$($matches[1])$BaseName.$($matches[2])"
		}

		# something*
		if ($FileSelection -match '^(.+)\*$') {
		    return "$($matches[1])$BaseName$Extension"
		}

		# fallback
		return "$BaseName$Extension"
	    }

	    $fileName = Get-MCEBuddyOutputName `
		-BaseName $folderName `
		-Extension ".mp4" `
		-FileSelection $selectedMCEBuddyTask.FileSelection

	    $outputFile = Join-Path $tempMp4Dir $fileName

            # Build concat file
            $tsFiles | 
		ForEach-Object { 
		    "file '$($_.FullName)'" 
		} | Set-Content -Path $mylistPath -Encoding ASCII

            # Add row to ListView (UI thread) — placeholder for MCEBuddy status
            $formRef.Invoke([Action]{
                $item = $listRef.Items.Add($folderName)
		 [void]$item.SubItems.Add($outputFile)
                [void]$item.SubItems.Add("Converting...")   # copy status
		[void]$item.SubItems.Add("—")		    # encode status
                [void]$item.SubItems.Add("—")		    # MCEBuddy Status
		[void]$item.SubItems.Add("—")		    # Counter
            })

	    # --- Encoding Variables ---
	    # get video parameters based on encoder

	    switch ($encoder) {
		"Handbrake" {
		    $videoEncoder	= $encodingProfile.Video.HandBrake
		    $audioEncoder	= $encodingProfile.Audio.HandBrake
		    $encoderPath	= $handBrakeCLI
		}	
		"FFmpeg" {
		    $videoEncoder	= $encodingProfile.Video.FFmpeg
		    $audioEncoder	= $encodingProfile.Audio.FFmpeg
		    $encoderPath	= $ffmpegPath
		}
	    }	
		
	    if (-not (Test-Path $encoderPath)) {
		   return
	    }

	    $audioBitrate  = $encodingProfile.Audio.Bitrate
	    $videoQuality  = $encodingProfile.Video.Quality

	    # see if audio override parameters  video parameters were selected for ffmpeg encode
	    $audioChannels = ""

	    if ($selectedAudioProfile -ne "None") {
		switch ($encoder) {
		    "Handbrake" {
			$audioEncoder  = $audioProfile.HandBrake
			$audioChannels = $audioProfile.Channels
			$audioBitrate  = $audioProfile.Bitrate
		    }
		    "FFmpeg" {
			$audioEncoder  = $audioProfile.FFmpeg
			$audioChannels = $audioProfile.Channels
			$audioBitrate  = $audioProfile.Bitrate
		    }
		}	
	    }

	    "DEBUG: Encoders ->  selectedEncodingProfile=$selectedEncodingProfile, SelectedAudioProfile=$selectedAudioProfile, Video=$videoEncoder, Audio=$audioEncoder, Bitrate=${audioBitrate}k, CRF=$videoQuality" |
		Out-File -FilePath $logFile -Append
	    
	    #------------------------------------------------
	    # FFmpeg COPY 
            # capture all output (stdout + stderr) in order
	    # Waits automatically, since this is synchronous
	    #-------------------------------------------------

	    $FFmpegFunctions = Join-Path $rootDir "etc\FFmpegFunctions.ps1"
	    . $FFmpegFunctions

	    #
	    # Profile  = "Copy"	    $Source   = $inputPath
	    # Profile  = "Encode"	    $Source   = $inputPath
	    # Profile  = "ConcatCopy    $Source  = $myListPath
	    # Profile  = "ConcatEncode" $Source   = $myListPath
	    # Profile  = "Handbrake

	    $Source   = $myListPath
	    switch ($encoder) {
		"Handbrake" {
		    $vidProfile = "Handbrake"
		}
		"FFmpeg" {
		    $vidProfile = "ConcatCopy"
		}
	    }	
		
	    $args = Get-FFmpegArguments `
		-RootDir $rootDir `
		-Profile $vidProfile `
		-InputPath $Source `
		-OutputPath $outputFile `
		-VideoEncoder $videoEncoder `
		-VideoQuality $videoQuality `
		-AudioEncoder $audioEncoder `
		-AudioBitrate $audioBitrate `
		-AudioChannels $audioChannels `
		-Preset $selectedPresetValue 

	    "DEBUG: Remux -> args=$args" |
		Out-File -FilePath $logFile -Append

	   
	   
	    # $ffmpeg = Start-Process -FilePath ffmpeg -ArgumentList $ffmpegArgs -NoNewWindow -Wait -PassThru 2>&1
	    $exitCode = $LASTEXITCODE
	    # this code allows for log files to be produced
	    $ffmpegOutput | Out-File -FilePath $logFile -Encoding UTF8 -Append	    
	    
	    try {
		# --- FAST CONCAT ---
		# $ffmpegOutput = & $ffmpegPath @ffmpegArgsConcatCopy 2>&1
		$ffmpegOutput = & $encoderPath @args 2>&1 
		# $ffmpegOutput | Out-File -FilePath $logFile -Encoding UTF8 -Append	    
		$exitCode = $LASTEXITCODE
	    } catch {
		"$($_.Exception.Message)" | Out-File -FilePath $logFile -Encoding UTF8 -Append
		$exitCode = 1
	    }

	    if ($exitCode -eq 0) {
                $statusCopy = "MP4 created"      
            } else {
                $statusCopy = "Failed"
            }

            # Update ListView
            $formRef.Invoke([Action]{
                foreach ($row in $listRef.Items) {
                    if ($row.Text -eq $folderName) {
                        $row.SubItems[2].Text = $statusCopy
                        break
                    }
                }
            })

	
	    if ($exitCode -ne 0) {
		#------------------------------------------------
		# FFmpeg copy failed try  Re-Encode
		#------------------------------------------------
		# if fast only then return, cant do mcebuddy
		if ($runMode -eq "fast") {

		    if (Test-Path $outputFile) {
			Remove-Item $outputFile -Force -ErrorAction SilentlyContinue
		    }

		    $formRef.Invoke([Action]{
			foreach ($row in $listRef.Items) {
			    if ($row.Text -eq $folderName) {
				$row.SubItems[4].Text = "Failed"
				break
			    }
			}
		    })

		    return
		}

		$formRef.Invoke([Action]{
		    foreach ($row in $listRef.Items) {
			if ($row.Text -eq $folderName) {
			    $row.SubItems[3].Text = "Converting..."
			    break
			}
		    }
		})
		
		$Source   = $myListPath
		switch ($encoder) {
		    "Handbrake" {
			$vidProfile = "Handbrake"
		    }
		    "FFmpeg" {
			$vidProfile = "ConcatEncode"
		    }
		}	

		$args = Get-FFmpegArguments `
		    -RootDir $rootDir `
		    -Profile $vidProfile `
		    -InputPath $Source `
		    -OutputPath $outputFile `
		    -VideoEncoder $videoEncoder `
		    -VideoQuality $videoQuality `
		    -AudioEncoder $audioEncoder `
		    -AudioBitrate $audioBitrate `
		    -AudioChannels $audioChannels `
		    -Preset $selectedPresetValue 
		    

		"DEBUG: ReEncode -> args=$args" |
		    Out-File -FilePath $logFile -Append
		# $ffmpegOutput = & $ffmpegPath @ffmpegArgsConcatEnc 2>&1
		$ffmpegOutput = & $encoderPath @args 2>&1 
		# $ffmpegOutput | Out-File -FilePath $logFile -Encoding UTF8 -Append

		$exitCode = $LASTEXITCODE
	
		if ($exitCode -eq 0) {
		    # Update ListView
		    $formRef.Invoke([Action]{
		     foreach ($row in $listRef.Items) {
			    if ($row.Text -eq $folderName) {
				$row.SubItems[3].Text = "MP4 created"
				break
			    }
			}
		    })
		} else {
		  
		     # re-encode failed Update ListView
		    $formRef.Invoke([Action]{
			foreach ($row in $listRef.Items) {
			    if ($row.Text -eq $folderName) {
				$row.SubItems[3].Text = "Failed"
				$tempPath = $row.SubItems[1].Text

				"DEBUG: tempPath -> $tempPath" |
				    Out-File -FilePath $logFile -Append
				 if (Test-Path $tempPath) {
				    Remove-Item $tempPath -Force
				 }
				break
			    }
			} #end foreach row in listview
		    })

		    return # failed both copy and encode 

		} #endif re-encode logic
	    } # endif ffmpeg copy failed

	    # ffmpeg has created increment temp file waiting
	    [System.Threading.Interlocked]::Increment($tempFilesWaitingRef) | Out-Null

	      # Update ListView with number of temp files waiting
            $formRef.Invoke([Action]{
                foreach ($row in $listRef.Items) {
                    if ($row.Text -eq $folderName) {
	   		$row.SubItems[5].Text = $tempFilesWaitingRef.Value.ToString()
                        break
                    }
                }
             })


            # Wait for temp queue space
	    while ($tempFilesWaitingRef.Value -ge $maxTempFilesWaiting) { Start-Sleep -Seconds 5 }

            # Submit to MCEBuddy
	    # exit if cancel processing is active, preventing new work
	    if ($CancelProcessing) {
		break
	    }
	   

	    "DEBUG: MCEbuddy -> inputfile = $outputFile" |
		    Out-File -FilePath $logFile -Append

            try {
		#call MCEbuddyCli using $outputFile created by FFmpeg as input
		& $mcebuddyCLI --command=addfile --action="$outputFile" | Out-Null
                
                $formRef.Invoke([Action]{
                    foreach ($row in $listRef.Items) {
                        if ($row.Text -eq $folderName) {
                           $row.SubItems[3].Text = "Submitted to MCEBuddy"
                           $row.SubItems[4].Text = "queued?" 
                           break
                        }
                    }
                })
            } catch {
                $formRef.Invoke([Action]{
                    foreach ($row in $listRef.Items) {
                        if ($row.Text -eq $folderName) {
                            $row.SubItems[4].Text = "Submit failed"
                            if ($row.SubItems.Count -ge 4) { $row.SubItems[3].Text = "—" }
                            break
                        }
                    }
                })
            }
        } # foreach folder

    } -ArgumentList $videoDir, 
		    $global:logDir,
		    $global:runMode,
		    $tempMp4Dir,
		    $form, 
		    $listView, 
		    ([ref]$global:tempFilesWaiting), 
		    $global:maxTempFilesWaiting,
		    $global:videoQuality,
		    $global:encoder,
		    $global:encodingProfile,
		    $global:selectedEncodingProfile,
		    $global:audioProfile,
		    $global:selectedAudioProfile,
		    $global:selectedPresetValue,
		    $global:ffmpegPath,
		    $global:mcebuddyCLI,
		    $global:selectedMCEBuddyTask,
		    $global:CancelProcessing,
		    $rootDir


}) # buttonStart

# $global:tempFilesWaiting = 0
# $global:maxTempFilesWaiting = 3 

# Track which temp files we've already deleted (prevents repeats)
$cleaned = New-Object 'System.Collections.Generic.HashSet[string]'


# --- Timer to poll MCEBuddy queue, update column, and clean temp files ---
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 15000  # 15s
$timer.Add_Tick({
    try {
        # --quiet reduces banner noise; only prints results or -2 on error
        $q = & $mcebuddyCLI --command=query --action=queue --quiet 2>&1

        # Keep only the queue rows (start with a number)
        $jobLines = $q | Where-Object { $_ -match '^\d+\s' }

        # Build a quick lookup: filename -> status
        $statusByFilename = @{}
        foreach ($line in $jobLines) {
            # Prefer tab-split; fallback to multi-space
            $cols = $line -split "\t+"
            if ($cols.Count -lt 5) { $cols = $line -split "\s{2,}" }

            if ($cols.Count -ge 5) {
                $status   = $cols[1]           # queued / converting
                $filename = $cols[3]           # e.g., MyShow.mp4
                $statusByFilename[$filename] = $status
            }
        }

        # Update each row by matching the Temp MP4 filename
        foreach ($row in $listView.Items) {
            $tempPath     = $row.SubItems[1].Text
            $tempPathLeaf = [System.IO.Path]::GetFileName($tempPath)
            if ([string]::IsNullOrWhiteSpace($tempPathLeaf)) { continue }

            if ($statusByFilename.ContainsKey($tempPathLeaf)) {
                # Still in queue -> reflect real-time status
                $row.SubItems[4].Text = $statusByFilename[$tempPathLeaf]
            } else {
                # No longer in queue. If it was queued/converting earlier, treat as completed.
                if ($row.SubItems[4].Text -in @('queued','converting','queued?')) {
                    $row.SubItems[4].Text = "Completed"

		    $btnStart.Enabled  = $true
		    $btnCancel.Enabled = $false
		    $global:CancelProcessing = $false

		    Get-ChildItem -Path $global:selectedMCEBuddyTask.Destination -File -Recurse |
			Where-Object { $_.Name -like "*$($global:selectedMCEBuddyTask.FileSelection)*" } |
			ForEach-Object {
			   $newName = Restore-MCEBuddyOutputName `
			    -FileName $_.Name `
			    -FileSelection $global:selectedMCEBuddyTask.FileSelection

			    Rename-Item -LiteralPath $_.FullName -NewName $newName
			    # Write-Host "Renamed:"
			    # Write-Host "  $($_.Name)"
			    # Write-Host "  -> $newName"
		    }


                    # Attempt to delete temp file once (we'll retry next tick if it fails due to a lock)
                    if (-not $cleaned.Contains($tempPath)) {
                        if (Test-Path $tempPath) {
                            try {
                                Remove-Item $tempPath -Force
                                # mark the row and remember we cleaned it
                                $row.SubItems[2].Text = "Temp deleted" 
				$row.SubItems[3].Text = "Temp deleted" 
				# decrement the number of temp files waiting
				[System.Threading.Interlocked]::Decrement([ref]$global:tempFilesWaiting) | Out-Null
				[void]$cleaned.Add($tempPath)

                            } catch {
                                # Could be locked; will try again on the next tick
                            }
                        } else {
                            # File already gone; mark as cleaned to avoid retries
                            $row.SubItems[2].Text = "Temp deleted"
			    $row.SubItems[3].Text = "Temp deleted" 
                            [void]$cleaned.Add($tempPath)
                        }
                    }
		}
            }
        }  #end foreach
    } catch {
        Write-Warning "Queue polling failed: $_"
   }
    
  

# if ($global:processJob) {
#     Write-Host "State = $($global:processJob.State)"
# }
if ($global:processJob -and $global:processJob.State -in @('Completed','Failed','Stopped')) {
    Receive-Job -Job $global:processJob -ErrorAction SilentlyContinue | Out-Null
    Remove-Job  -Job $global:processJob -ErrorAction SilentlyContinue
    $global:processJob = $null
    }
})
$timer.Start()


# --- Show the form ---
[System.Windows.Forms.Application]::Run($form)
# [System.Windows.Forms.Application]::EnableVisualStyles()

