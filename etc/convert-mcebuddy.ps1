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

# [System.Windows.Forms.Application]::EnableVisualStyles()

# Default path fallback for rootDir
if (-not $env:rootDir) {
    $env:rootDir = (Resolve-Path "$PSScriptRoot\..").Path
}
$rootDir = $env:rootDir 

Import-Module (Join-Path $rootDir "etc\includes\UIHelpers.psm1") -Force
Import-Module (Join-Path $rootDir "etc\includes\alert.psm1") -Force
Import-Module (Join-Path $rootDir "etc\includes\settings.psm1") -Force 
Import-Module (Join-Path $rootDir "etc\includes\addinputrow.psm1") -Force

$settings = Import-Settings

if ($settings) {
    $global:MCEBuddyCLI		= $settings.MCEBuddyCLI 
    $mceBuddyConfig		= $settings.MCEBuddyConf
    $global:HandBrakeCLI	= $settings.HandBrakeCLI  
    $global:FFmpegPath		= $settings.FFmpegPath             
    $DefaultVideoDir		= $settings.SEGvideoDir
    $global:tempMp4Dir		= $settings.TempMp4Dir
    $DefaultVideoQuality	= $settings.VideoQuality
    $DefaultProfileName		= $settings.ProfileName
    $DefaultMaxJobs		= $settings.MaxJobs
    $DefaultAudioName		= $settings.AudioOverride
    $DefaultPresetValue		= $settings.Preset
}

function Pause-MCEBuddy {
    & $MCEBuddyCLI --command=engine --action=pause
}

function Resume-MCEBuddy {
    & $MCEBuddyCLI --command=engine --action=resume
}

function Start-MCEBuddy {
    & $MCEBuddyCLI --command=engine --action=start
}

function Stop-MCEBuddy {
    & $MCEBuddyCLI --command=engine --action=stop
}

function Get-MCEBuddyState {
    & $MCEBuddyCLI --command=query --action=enginestate
}

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
            Enabled     = ($section.Enabled -eq 'True') # convert value to boolean
            MonitorTask = $section.MonitorTaskNames
	    FileSelection = $section.FileSelection
        }
    }
    return $tasks
}
# ------------------------------------------------------------------------
# Load-MCEBuddyTaskList
# =========================================================================
function Load-MCEBuddyTaskList {

    param(
        $Tasks
    )

    $listViewTasks.Items.Clear()

    foreach ($task in $Tasks) {

        $item = New-Object System.Windows.Forms.ListViewItem("      " + $task.Name)

        # Checkbox state
        $item.Checked = $task.Enabled

        # Enabled column symbol
        [void]$item.SubItems.Add(
            $(if ($task.Enabled) { "✓" } else { " " })
        )

        # Profile
        [void]$item.SubItems.Add($task.Profile)

        # CLI status symbol
        $cliStatus = if ($task.MonitorTask -match "CLI") {
            "✓"
        }
        else {
            "⚠"
        }

        [void]$item.SubItems.Add($cliStatus)

        $item.Tag = $task

        [void]$listViewTasks.Items.Add($item)
    }

    if ($listViewTasks.Items.Count -gt 0) {

        $listViewTasks.Items[0].Selected = $true
        $listViewTasks.Select()

        Update-TaskInfo $listViewTasks.Items[0].Tag
    }
}

# ------------------------------------------------------------------------
# Set-MCEBuddyTaskEnabled
# Update the enable status of user defined conversion tasks in mcebuddy.conf 
# =========================================================================
function Set-MCEBuddyTaskEnabled {
    param(
        [string]$ConfigFile = "C:\Program Files\MCEBuddy2x\config\mcebuddy.conf",
        [string]$TaskName,
        [bool]$Enabled
    )

    if (-not (Test-Path $ConfigFile)) {
        throw "Config file not found: $ConfigFile"
    }

    $updated = $false

    $lines = Get-Content $ConfigFile

    $inSection = $false

    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i].Trim()
        # Detect section headers
        if ($line -match '^\[(.+?)\]$') {
            if ($Matches[1] -eq $TaskName) {
                $inSection = $true
                continue
            }
            else {
                $inSection = $false
            }
        }

        if ($inSection -and $line -match '^Enabled\s*=') {
            $value = if ($Enabled) { 'True' } else { 'False' }
            $lines[$i] = "Enabled=$value"
	    $updated = $true
            break
        }
    }

    if ($updated) {
	Set-Content -Path $ConfigFile -Value $lines
    }

    return $updated

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
# =========================================================================
# =========================================================================
# =========================================================================


$themeFile = Join-Path $rootDir "data\theme.txt"
$currentMode = Import-ThemeState -themeFile $themeFile
$global:encoder = "FFmpeg"
$global:tempFilesWaiting = 0

$DefaultRunMode         = "fallback"

# Ensure temp folder exists (UNC ok)
if (-not (Test-Path $tempMp4Dir)) {
    New-Item -Path $tempMp4Dir -ItemType Directory | Out-Null
}

if ([string]::IsNullOrWhiteSpace($DefaultVideoDir)) {
    $DefaultVideoDir = "D:\Desktop\Tablo\rec" 
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

# ------------------------------------------------------------------------
# Update-TaskInfo
# =========================================================================
function Update-TaskInfo {

    param(
        $selectedTask
    )

    if ($null -eq $selectedTask) {
	$labelDest.Text = "Destination:"
        $labelTaskProfile.Text = "Profile:"
        $labelTaskMonitor.Text = "Task Monitor:"
        $labelEnabled.Text = "Enabled:"
        $labelFileFilter.Text = "File Filter:"
        $labelFileFilter.ForeColor = [System.Drawing.Color]::White
        return
    }

    $labelDest.Text = "Destination: $($selectedTask.Destination)"
    $labelTaskProfile.Text = "Profile: $($selectedTask.Profile)"
    $labelTaskMonitor.Text = "Task Monitor: $($selectedTask.MonitorTask)"
    $labelEnabled.Text = "Enabled: $($selectedTask.Enabled)"
    $labelFileFilter.Text = "File Filter: $($selectedTask.FileSelection)"

    # FileSelection warnings
    if ([string]::IsNullOrWhiteSpace($selectedTask.FileSelection)) {
	$labelFileFilter.Text = "File Filter: (none - accepts all files)"
    }
    elseif ($selectedTask.FileSelection -in @("*.mp4","*.MP4","*")) {
	$labelFileFilter.ForeColor = [System.Drawing.Color]::Red
    }
    else {
	$labelFileFilter.ForeColor = [System.Drawing.Color]::White
    }

}

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

$topStrt = 40
$spacing = 40
$top = $topstrt - 10
$topstrtgrp = 40

# ----------------------
# --- MCEBuddy Task Mgmt CheckBox---
# ----------------------

$CheckboxMCE, $label = Add-InputRow $form "" $top "checkbox"
$CheckboxMCE.text = "MCEBuddy Task Management  "
$CheckboxMCE.Appearance = [System.Windows.Forms.Appearance]::Button
# $CheckboxMCE.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$CheckboxMCE.FlatAppearance.BorderSize = 0
# $CheckboxMCE.BackColor = [System.Drawing.Color]::SteelBlue
$CheckboxMCE.BackColor = [System.Drawing.ColorTranslator]::FromHtml("#444")
$CheckboxMCE.ForeColor = [System.Drawing.Color]::White
# $CheckboxMCE.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$CheckboxMCE.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
# $CheckboxMCE.AutoSize = $false
# $CheckboxMCE.Width = 100
# $CheckboxMCE.Height = 32

  
$top = (1*$spacing) +  $topstrt

# ---------------------------------------------------------------
#  MCE BUDDY TASK GROUP
# ===============================================================

$groupTasks = New-Object System.Windows.Forms.GroupBox
$groupTasks.Text = "MCEBuddy Tasks"
$groupTasks.Location = New-Object Drawing.Point($labelleft,$top)
$groupTasks.Size = New-Object Drawing.Size(620,230)
Set-GroupBoxStyle -GroupBox $groupTasks -Mode $currentMode
$form.Controls.Add($groupTasks)

$topgrp =  $topstrtgrp

# ----------------------
# Task ListView
# ----------------------
$listViewTasks = New-Object System.Windows.Forms.ListView
$listViewTasks.Location = New-Object System.Drawing.Point($global:labelLeft,$topgrp)
$listViewTasks.Size     = New-Object System.Drawing.Size(580,150)

$listViewTasks.View = [System.Windows.Forms.View]::Details
$listViewTasks.FullRowSelect = $true
$listViewTasks.GridLines = $true
$listViewTasks.MultiSelect = $false
$listViewTasks.HideSelection = $false
$listViewTasks.CheckBoxes = $true

# Columns
[void]$listViewTasks.Columns.Add("✓      Task", 220)
[void]$listViewTasks.Columns.Add("Enabled", 90)
[void]$listViewTasks.Columns.Add("Profile", 180)
[void]$listViewTasks.Columns.Add("CLI Status", 90)
Set-ListViewStyle -ListView $listViewTasks -Mode $currentMode
# $form.Controls.Add($listViewTasks)

$topgrp = $topstrtgrp + (1*$spacing)

$btnApply, $null = Add-InputRow $form ""   $top "button"
 $btnApply.Text = "Update MCEBuddy Tasks"
 $btnApply.Location = New-Object System.Drawing.Point(40,190)
 $btnApply.Width = $buttonwidth + 400


$groupTasks.Controls.Add($listViewTasks)
$groupTasks.Controls.Add($btnApply)


# ---------------------------------------------------------------
#  MCE BUDDY TASK INFORMATION GROUP
# ===============================================================

$groupInfo = New-Object System.Windows.Forms.GroupBox
$groupInfo.Text = "Selected Task"
$groupInfo.Location = New-Object Drawing.Point(650,$top)
$groupInfo.Size = New-Object Drawing.Size(620,230)
Set-GroupBoxStyle -GroupBox $groupInfo -Mode $currentMode

$form.Controls.Add($groupInfo)

$topgrp = $topstrtgrp
# ----------------------
# MCEbuddy conversion engine state
# ----------------------

$null, $labelConvEngine = Add-InputRow $form "Conversion Engine State:"   $topgrp "$null"

$topgrp = (1*$spacing) +  $topstrtgrp
# ----------------------
# Enabled
# ----------------------

$null, $labelEnabled = Add-InputRow $form "Enabled:"   $topgrp "$null"
# $labelEnabled.Font = New-Object System.Drawing.Font('Arial', 12)

$topgrp = (2*$spacing) +  $topstrtgrp

# ----------------------
# --- Profile ---
# ----------------------

$null, $labelTaskProfile = Add-InputRow $form "Profile:"   $topgrp "$null"
$labelTaskProfile.Left =  $global:labelLeft

$topgrp = (3*$spacing) + $topstrtgrp

# ----------------------
# --- Destination folder ---
# ----------------------
$null, $labelDest = Add-InputRow $form "Destination:"   $topgrp "$null"
$labelDest.Left = $global:labelLeft

$topgrp = (3*$spacing) + $topstrtgrp

# ----------------------
# --- Task Monitor ---
# ----------------------

$null, $labelTaskMonitor = Add-InputRow $form "Task Monitor:"   $topgrp "$null"
$labelTaskMonitor.Left = $global:labelLeft

$topgrp = (4*$spacing) + $topstrtgrp

# ----------------------
# --- File Filters ---
# ----------------------

$null, $labelFileFilter = Add-InputRow $form "File Filter:"   $topgrp "$null"
$labelFileFilter.Left = $global:labelLeft

$groupinfo.Controls.Add($labelEnabled)
$groupinfo.Controls.Add($labelTaskProfile)
$groupinfo.Controls.Add($labelDest)
$groupinfo.Controls.Add($labelTaskMonitor)
$groupinfo.Controls.Add($labelFileFilter)
$groupinfo.Controls.Add($labelConvEngine)

$top = $topstrt

$top = (8*$spacing) + $topstrt

# ---------------------------------------------------------------
# Video Directory
# ===============================================================
$textboxVideoDir, $labelVideoDir = Add-InputRow $form "Videos folder:"  $top "textbox"
$textboxVideoDir.text = $DefaultVideoDir

$browseVideoDir, $null = Add-InputRow $form ""   $top "browse"
$browseVideoDir.Add_Click({
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $textboxVideoDir.Text = $dlg.SelectedPath
    }
})

$top = (9*$spacing) + $topstrt
# ---------------------------------------------------------------
# Maximumconcurrent jobs
# ===============================================================

$textboxMaxJobs , $labelMaxJobs  = Add-InputRow $form "Max Concurrent Jobs:"   $top "textbox"
$textboxMaxJobs.Text = $DefaultMaxJobs
$textboxMaxJobs.Width = 35
$textboxMaxJobs.Left = $global:labelLeft + $labelMaxJobs.Width

# ---------------------------------------------------------------
# Run Mode
# ===============================================================

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

$top = (11*$spacing) + $topstrt

# ---------------------------------------------------------------
# --- FFmpeg Encoding Check Box ---
# ===============================================================

$CheckboxEnc, $label = Add-InputRow $form "" $top "checkbox"
$CheckboxEnc.text = "FFmpeg Encoding Parameters  "

$CheckboxEnc.Appearance = [System.Windows.Forms.Appearance]::Button
# $CheckboxEnc.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$CheckboxEnc.FlatAppearance.BorderSize = 0
$CheckboxEnc.BackColor = [System.Drawing.ColorTranslator]::FromHtml("#444")
$CheckboxEnc.ForeColor = [System.Drawing.Color]::White
$CheckboxEnc.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter



# $top = (4*$spacing) + $topstrt
$top = (13*$spacing) + $topstrt

# ---------------------------------------------------------------
#  FFmpeg encoding parameters group
# ===============================================================

$groupEnc = New-Object System.Windows.Forms.GroupBox
$groupEnc.Text = "FFmpeg Encoding Parameters"
$groupEnc.Location = New-Object Drawing.Point($labelleft,$top)
$groupEnc.Size = New-Object Drawing.Size(920,130)
Set-GroupBoxStyle -GroupBox $groupEnc -Mode $currentMode
$form.Controls.Add($groupEnc)


$topgrp = $topstrtgrp

# Video Profile
$comboProfile , $labelProfile  = Add-InputRow $form "Video Profile:"   $topgrp "combobox"
$labelProfile.Left = $global:labelLeft
$comboProfile.Left = $labelLeft + $labelProfile.Width 
$comboProfile.Size     = New-Object System.Drawing.Size(250, 30)
$comboProfile.Items.AddRange([string[]]$profiles.Keys)
$comboProfile.SelectedItem = $DefaultProfileName

# Video Quality Label & ComboBox
$comboVidQual, $labelVidQual = Add-InputRow $form "Video Quality override (CRF):" $topgrp "combobox"
$comboVidQual.Width = 60
$labelVidQual.Left = $global:labelLeft2 + 100
$comboVidQual.Left = $global:labelLeft2 + 100 + $labelVidQual.Width
# Add blank option and values 15-30
$comboVidQual.Items.Add(" ") | Out-Null
foreach ($quality in 15..30) {
    $comboVidQual.Items.Add($quality.ToString()) | Out-Null
}

# Set default selection
if ($null -eq $DefaultVideoQuality -or
    [string]::IsNullOrWhiteSpace([string]$DefaultVideoQuality)) {

    $comboVidQual.SelectedIndex = 0
}
else {
    $comboVidQual.SelectedItem = $DefaultVideoQuality.ToString()
}

$topgrp = (1*$spacing) + $topstrtgrp

# Label encoder preset
$comboBoxPreset , $labelPreset  = Add-InputRow $form  "Encoder Preset:"   $topgrp "combobox"
$comboBoxPreset.Left = $global:labelLeft + $labelPreset.Width
$comboBoxPreset.Size = New-Object System.Drawing.Size(230,30)
$comboBoxPreset.Items.AddRange([string[]]$presets.Keys)
$comboBoxPreset.SelectedItem = $DefaultPresetValue

# Label audio override
$comboBoxAudio , $labelAudio  = Add-InputRow $form  "Audio Override:"   $topgrp "combobox"
$labelAudio.Left = $global:labelLeft2 + 100
$comboBoxAudio.Left = $global:labelLeft2 + $labelAudio.Width + 100
$comboBoxAudio.Size = New-Object System.Drawing.Size(250,30)
$comboBoxAudio.Items.AddRange([string[]]$audioOverride.Keys)
$comboBoxAudio.SelectedItem = $DefaultAudioName


$groupEnc.Controls.Add($comboVidQual)
$groupEnc.Controls.Add($labelVidQual)
$groupEnc.Controls.Add($comboProfile)
$groupEnc.Controls.Add($labelProfile)
$groupEnc.Controls.Add($comboBoxPreset)
$groupEnc.Controls.Add($labelPreset)
$groupEnc.Controls.Add($comboBoxAudio)
$groupEnc.Controls.Add($labelAudio)



# $top = (8*$spacing) + $topstrt
$top = (15*$spacing) + $topstrt

# ---------------------------------------------------------------
# --- Start button ---
# ===============================================================

$btnStart, $null = Add-InputRow $form ""   $top "button"
$btnStart.Text = "Start Processing"
$btnStart.Location = New-Object System.Drawing.Point($global:labelLeft, $top)
$btnStart.Width = $buttonwidth + 30

# ---------------------------------------------------------------
# --- Cancel button ---
# ===============================================================

$btnCancel, $null = Add-InputRow $form ""   1000 "button"
$btnCancel.Text = "Cancel Processing"
$btnCancel.Width = $buttonwidth + 30
$btnCancel.Left = $global:labelLeft + 650
$btnCancel.Top = $top
$btnCancel.Enabled = $false

# $top = (9*$spacing-10) + $topstrt
$top = (16*$spacing-10) + $topstrt

# ---------------------------------------------------------------
# --- ListView for job status ---
# ===============================================================
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


# ------------------------------------------------------------------------
# DropDownDisp
# =========================================================================

function DropDownDisp {
    $isVisible = $CheckboxMCE.Checked
    $groupinfo.Visible = $groupTasks.Visible =  $isVisible
    if ($isVisible) {
	$tasks = Get-MCEBuddyTasks $mceBuddyConfig -ConfigFile $mceBuddyConfig
	Load-MCEBuddyTaskList $tasks
	$dispMCEmgmt = 7*$spacing
    } else {
	$dispMCEmgmt = 0
    }

    $top = (1*$spacing) +  $topstrt
    $textboxVideoDir.Top = $labelVideoDir.Top = $browseVideoDir.Top = $top + $dispMCEmgmt
    $top = (2*$spacing) +  $topstrt
    $textboxMaxJobs.Top = $labelMaxJobs.Top = $top + $dispMCEmgmt
    $comboBoxRunMode.Top = $labelrunMode.Top = $top + $dispMCEmgmt
    $top = (3*$spacing) + $topstrt
    $CheckboxEnc.Top = $top + $dispMCEmgmt
    $top = (4*$spacing) + $topstrt
    $groupEnc.Top = $top + $dispMCEmgmt

    $isVisible = $CheckboxEnc.Checked
    $groupEnc.Visible = $isVisible

    if ($isVisible) {
	$dispEnc = 4*$spacing
    } else {
	$dispEnc = 0
    }

    $top = ((5*$spacing) + $topstrt)
    $btnStart.Top = $top + $dispEnc + $dispMCEmgmt
    $btnCancel.Top = $top + $dispEnc + $dispMCEmgmt
    $top = ((6*$spacing) + $topstrt)
    $listView.Top = $top + $dispEnc + $dispMCEmgmt

}


DropDownDisp

# ------------------------------------------------------------------------
# CheckboxMCE.Add_CheckedChanged
#     display/hide encoding parameters 
# =========================================================================
$CheckboxMCE.Add_CheckedChanged({
    DropDownDisp
    
    if ($CheckboxMCE.Checked) {
	$CheckboxMCE.BackColor = ([System.Drawing.Color]::FromArgb(100, 100, 100))
    }
    else {
        $CheckboxMCE.BackColor = [System.Drawing.ColorTranslator]::FromHtml("#444")
    }
    # Query the MCEBuddy engine state
    $engineOutput = Get-MCEBuddyState

    # Extract engine state
    $engineState = "unknown"

    if ($engineOutput -match 'Engine state\s*=\s*(\w+)') {
	$engineState = [regex]::Match(
	    $engineOutput,
	    'Engine state\s*=\s*(\w+)'
	).Groups[1].Value
    }
    $labelConvEngine.text = "Conversion Engine State: $engineState"
    Write-Host "MCEBuddy Engine State: $engineState"
})

# ------------------------------------------------------------------------
# CheckboxEnc.Add_CheckedChanged
#     display/hide encoding parameters 
# =========================================================================
$CheckboxEnc.Add_CheckedChanged({
    DropDownDisp
     if ($CheckboxEnc.Checked) {
	$CheckboxEnc.BackColor = ([System.Drawing.Color]::FromArgb(100, 100, 100))
    }
    else {
        $CheckboxEnc.BackColor = [System.Drawing.ColorTranslator]::FromHtml("#444")
    }
})

# ------------------------------------------------------------------------
# $btnApply.Add_Click
# event handler for apply button associated with enabling/disabling tasks.
# updates MCEBuddy config file with the status of the conversion tasks 
# allowing user to determine which tasks are active
# =========================================================================
$btnApply.Add_Click({

    # Make sure at least one task is enabled
    $enabledCount = 0
    foreach ($item in $listViewTasks.Items) {
        if ($item.Checked) {
            $enabledCount++
        }
    }
    if ($enabledCount -eq 0) {
	Show-Alert -Title "MCEBuddy Task Selection" -Message "At least one MCEBuddy task must be enabled."
	$tasks = Get-MCEBuddyTasks
	Load-MCEBuddyTaskList $tasks
	return
    }

    $changes = 0

    Stop-MCEBuddy

    foreach ($item in $listViewTasks.Items) {

        $task = $item.Tag

        # Only update changed tasks
        if ($task.Enabled -ne $item.Checked) {
	    if (Set-MCEBuddyTaskEnabled -TaskName $task.Name -Enabled $item.Checked) {

		$changes++
	    }
        }
    }

    if ($changes -gt 0) {

        # Reload from the config file
        $tasks = Get-MCEBuddyTasks
        Load-MCEBuddyTaskList $tasks

	Show-Alert -Title "MCEBuddy" -Message "$changes task(s) updated."
    }

})

# ----------------------
# Button Cancel Event
# ----------------------

$btnCancel.Add_Click({
     

    # Tell worker to stop
    $global:CancelToken.Cancel = $true
   
    # Stop the ThreadJob
    if ($global:processJob) {
        Stop-Job -Job $global:processJob -ErrorAction SilentlyContinue

        Remove-Job -Job $global:processJob -Force -ErrorAction SilentlyContinue

        $global:processJob = $null
    }


    # Stop ffmpeg
    Get-Process ffmpeg -ErrorAction SilentlyContinue |
    ForEach-Object {
        try {
            $_.Kill()
        }
        catch {
            Write-Host "Could not kill ffmpeg PID $($_.Id)"
        }
    }

    Start-Sleep -Seconds 3

    # Cleanup temp files
    Get-ChildItem $tempMp4Dir -Filter *.mp4 |
    ForEach-Object {
        try {
            Remove-Item $_.FullName -Force -ErrorAction Stop
        }
        catch {
            Write-Host "File locked: $($_.Name)"
        }
    }

    $timer.Stop()

    $global:tempFilesWaiting = 0
    $cleaned.Clear()
    $listView.Items.Clear()
    $btnStart.Enabled = $true
    $btnCancel.Enabled = $false
    # allow updating mcebuddy config 
     $btnApply.Enabled = $true
})

# ----------------------
# listViewTasks Change Event
# ----------------------
$listViewTasks.Add_SelectedIndexChanged({

    if ($listViewTasks.SelectedItems.Count -eq 0) {
        return
    }

    $selectedTask = $listViewTasks.SelectedItems[0].Tag

    Update-TaskInfo $selectedTask
})



$btnStart.DialogResult = [System.Windows.Forms.DialogResult]::OK
$form.AcceptButton = $btnStart

# ----------------------
# Button Start Event
# ----------------------
$btnStart.Add_Click({

   # ensure the tasks have been updated by clicking update button
    $changes = 0
    foreach ($item in $listViewTasks.Items) {
	$task = $item.Tag
	if ($task.Enabled -ne $item.Checked) {
	    $changes++
	}

    }

    if ($changes -gt 0) {
	Show-Alert -Title "MCEBuddy Task Selection" -Message "Changes were made to MCEbuddy tasks and not updated"
	return
    }

   

    
    # $names = $enabledTasks.Name -join ", "
    # Show-Alert -Title "Processing" -Message "Starting with MCEBuddy task(s):`n$names"
    

    # --- Read inputs directly from GUI ---
    $videoDir			    = $textboxVideoDir.Text.Trim()
    $global:videoQuality	    = $comboVidQual.SelectedItem.ToString().Trim()
    $global:maxTempFilesWaiting	    = [int]$textboxMaxJobs.Text 
    $global:runMode		    = $runModeDisplayMap[$comboBoxRunMode.Text]
    

    # if ($listViewTasks.SelectedItems.Count -eq 0) {
    #	Show-Alert "No MCEBuddy task has been selected."
    #	return
    # }

    $global:selectedMCEBuddyTask = $listViewTasks.SelectedItems[0].Tag

   # if ($global:selectedMCEBuddyTask.FileSelection -eq "*.mp4") {
   #	Show-Alert "Warning: This task accepts every MP4 file."
   # }

   # if ($null -eq $global:selectedMCEBuddyTask) {
   #	Show-Alert "No MCEBuddy task has been selected."
   #	return
   # }

   # if (-not $global:selectedMCEBuddyTask.Enabled) {
   #	Show-Alert "Error: This task is not enabled in MCEBuddy."
   #	return
  #  }

   # if ([string]::IsNullOrWhiteSpace($global:selectedMCEBuddyTask.FileSelection)) {
   #	$msg = "Warning: This task has no FileSelection filter set and will accept all requests. "
   #	$msg += " Manage tasks accepting requests by enabling the task accepting requests and disabling othres. "
   #	Show-Alert $msg
  #  }

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


    # Validate Video Quality only when a value was entered
    if (-not [string]::IsNullOrWhiteSpace($global:videoQuality) -and
	$global:videoQuality -ne '0') {

	$parsedQuality = 0

	if (-not [int]::TryParse(
		[string]$global:videoQuality,
		[ref]$parsedQuality
	    ) -or
	    $parsedQuality -lt 15 -or
	    $parsedQuality -gt 30) {

	    Show-Alert -Title "Invalid Input" -Message "Please enter a valid Video Quality (CRF) number between 15 and 30."
	    $form.DialogResult = [System.Windows.Forms.DialogResult]::None
	    return
	}
    }

    $settings = Import-Settings
    $settings.SEGvideoDir   = $videoDir
    $settings.VideoQuality  = $global:videoQuality
    $settings.ProfileName   = $global:selectedEncodingProfile
    $settings.MaxJobs       = $global:maxTempFilesWaiting
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
    # dont allow updating mcebuddy config 
     $btnApply.Enabled = $false

    $global:CancelToken = [hashtable]::Synchronized(@{
    Cancel = $false
})

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
	    $CancelToken,
	    $rootDir
        )

	# ------------------------------------------------------------------------
	# Get-MCEBuddyOutputName
	# =========================================================================
	function Get-MCEBuddyOutputName {
	    param(
		[string]$BaseName,
		[string]$Extension,
		 [string]$FileSelection = ""
	    )

	    return "$BaseName$Extension"

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
	    

        # Ensure engine is running (idempotent)
        try { & $mcebuddyCLI --command=engine --action=start | Out-Null; Start-Sleep -Seconds 2 } catch {}

	$folders = Get-ChildItem -Path $videoDir -Directory

	# --- Check for folders ---
	if ($null -eq $folders -or $folders.Count -eq 0) {
	    $logFile    = Join-Path $logDir "logs.log"
	    "No folders found - exiting job: $videoDir" |
		Out-File -FilePath $logFile -Append
	    return 1
	}

	foreach ($folderItem in $folders) 
	{
            $folder     = $folderItem.FullName
            $folderName = $folderItem.Name
            $segsDir    = Join-Path $folder "segs"
	    $logFile    = Join-Path $logDir "$folderName.log"

	    if ($CancelToken.Cancel) {
		break
	    }

	    if (-not (Test-Path $segsDir)) {
		 
		$formRef.Invoke([Action]{
		    $item = $listRef.Items.Add($folderName)
		    [void]$item.SubItems.Add($outputFile)
		    [void]$item.SubItems.Add("failed")
		    [void]$item.SubItems.Add("No segs directory")
		    [void]$item.SubItems.Add("—")
		    [void]$item.SubItems.Add("—")
		})

		continue

	    }

	    $fileName = Get-MCEBuddyOutputName `
		-BaseName $folderName `
		-Extension ".mp4" `
		-FileSelection $selectedMCEBuddyTask.FileSelection

	    # Output file for ffmpeg to be passed to mcebuddy as input file
	    $outputFile = Join-Path $tempMp4Dir $fileName

	    # Add row to ListView (UI thread)
	    $formRef.Invoke([Action]{
		$item = $listRef.Items.Add($folderName)
		[void]$item.SubItems.Add($outputFile)
		[void]$item.SubItems.Add("Waiting...")
		[void]$item.SubItems.Add("—")
		[void]$item.SubItems.Add("—")
		[void]$item.SubItems.Add("—")
	    })

	    $tsFiles = Get-ChildItem -Path $segsDir -Filter "*.ts" -File |
		Sort-Object Name

	    # No TS files
	    if ($null -eq $tsFiles -or $tsFiles.Count -eq 0) {

		"No TS files found - skipping: $folderName" |
		    Out-File -FilePath $logFile -Append

		$formRef.Invoke([Action]{
		    foreach ($row in $listRef.Items) {
			if ($row.Text -eq $folderName) {
			    $row.SubItems[2].Text = "Failed"
			    $row.SubItems[3].Text = "No TS files"
			    break
			}
		    }
		})

		continue
	    }

	    # Only create concat.txt when TS files exist
	    $mylistPath = Join-Path $segsDir "concat.txt"

	    # Build concat file
	    $tsFiles |
		ForEach-Object {
		    # Escape apostrophes for FFmpeg concat-file syntax
		    $fullPath = $_.FullName -replace "'", "'\''"
		    "file '$fullPath'"
		} |
		Set-Content -Path $mylistPath -Encoding ASCII


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
		
	    # --- Check encoder exists ---
	    if (-not (Test-Path $encoderPath)) {

		"Encoder not found: $encoderPath - skipping $folderName" |
		    Out-File -FilePath $logFile -Append

		$formRef.Invoke([Action]{
		    foreach ($row in $listRef.Items) {
			if ($row.Text -eq $folderName) {
			    $row.SubItems[2].Text = "Failed"
			    $row.SubItems[3].Text = "Encoder not found"
			    break
			}
		    }
		})

		continue
	    }

	    $audioBitrate  = $encodingProfile.Audio.Bitrate

	    # check for video qual override
	    if ([string]::IsNullOrWhiteSpace($global:videoQuality) -or
		$global:videoQuality -eq '0') {

		$videoQuality  = $encodingProfile.Video.Quality
	    }

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
		$ffmpegOutput = & $encoderPath @args 2>&1 
		$ffmpegOutput | Out-File -FilePath $logFile -Append	    
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

		    continue  # Skip this folder; process the next one
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
		$ffmpegOutput = & $encoderPath @args 2>&1 
		$ffmpegOutput | Out-File -FilePath $logFile -Append

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
		    
		    continue  # Copy and re-encode failed; process the next folder
		  
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
	    if ($CancelToken.Cancel) {
		break
	    }
	   

	    "DEBUG: MCEbuddy -> inputfile = $outputFile" |
		    Out-File -FilePath $logFile -Append

            try {
		#call MCEbuddyCli using $outputFile created by FFmpeg as input
		& $mcebuddyCLI --command=addfile --action="$outputFile" | Out-Null
                # & $mcebuddyCLI --command=addfile --action="$outputFile" | 
		#     Out-File -FilePath $logFile -Append

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
        } # end foreach folder
	return 0

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
		    $global:CancelToken,
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
		    # allow updating mcebuddy config 
		    $btnApply.Enabled = $true

		    # Get-ChildItem -Path $global:selectedMCEBuddyTask.Destination -File -Recurse |
		    #	Where-Object { $_.Name -like "*$($global:selectedMCEBuddyTask.FileSelection)*" } |
		    #	ForEach-Object {
		    #	   $newName = Restore-MCEBuddyOutputName `
		    #	    -FileName $_.Name `
		    #	    -FileSelection $global:selectedMCEBuddyTask.FileSelection
		    #	    
		    #	    Write-Host "Renamed:"
		    #	    Write-Host "  $($_.Name)"
		    #	    Write-Host "  -> $newName"
		    #	    Rename-Item -LiteralPath $_.FullName -NewName $newName
			   
		   # }


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
    

# if ($global:processJob -and $global:processJob.State -in @('Completed','Failed','Stopped')) {
    #	Receive-Job -Job $global:processJob -ErrorAction SilentlyContinue | Out-Null
    #	Remove-Job  -Job $global:processJob -ErrorAction SilentlyContinue
    #	$global:processJob = $null
    # }

    if ($global:processJob -and $global:processJob.State -in @('Completed', 'Failed', 'Stopped')) 
    {
	# Capture the background job's output
	$jobOutput = @(Receive-Job -Job $global:processJob `
	    -ErrorAction SilentlyContinue)

	# Check for the returned error code
	$exitCode = $jobOutput |
	    Where-Object { $_ -is [int] } |
	 Select-Object -Last 1

	 WRITE-HOST "EXITCODE $exitCode"

	if ($exitCode -eq 1) {
	    # No folders found - reset the GUI
	    $btnStart.Enabled  = $true
	    $btnCancel.Enabled = $false
	    $btnApply.Enabled  = $true
	    $form.Invoke([Action]{
		$item = $listView.Items.Add("No video folders in segs directory")
		[void]$item.SubItems.Add("-")
		[void]$item.SubItems.Add("-")
		[void]$item.SubItems.Add("Finished")
	    })
    }

	Remove-Job -Job $global:processJob -ErrorAction SilentlyContinue
	$global:processJob = $null
    }
})
$timer.Start()


# --- Show the form ---
[System.Windows.Forms.Application]::Run($form)
# [System.Windows.Forms.Application]::EnableVisualStyles()










