param(
    [string]$Encoder
)

Add-Type -AssemblyName 'System.Windows.Forms'
Add-Type -AssemblyName 'System.Drawing'
Import-Module Microsoft.PowerShell.ThreadJob

if (-not $Encoder) {
    $global:encoder = "FFmpeg"
} else {
    $global:encoder = $Encoder
}

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
# EncParamDisplay
# Displays encoding parameters based upon $CheckboxEnc.Checked
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

$themeFile = Join-Path $rootDir "data\theme.txt"
$currentMode = Import-ThemeState -themeFile $themeFile
$global:CancelProcessing = $false
$global:tempFilesWaiting = 0
$global:maxTempFilesWaiting = 3 

$settings = Import-Settings

if ($settings) {
    $global:MCEBuddyCLI	    = $settings.MCEBuddyCLI        
    $global:HandBrakeCLI    = $settings.HandBrakeCLI       
    $global:FFmpegPath	    = $settings.FFmpegPath             
    $DefaultVideoDir	    = $settings.SEGvideoDir
    $global:tempMp4Dir	    = $settings.TempMp4Dir
    $DefaultDest            = $settings.Destination
    $DefaultVideoQuality    = $settings.VideoQuality
    $DefaultProfileName	    = $settings.ProfileName
    $DefaultRunMode         = $settings.RunMode
    $DefaultMaxJobs         = $settings.MaxJobs
    $DefaultSize            = $settings.MinSize
    $DefaultAudioName	    = $settings.AudioOverride
    $DefaultPresetValue	    = $settings.Preset
}

if ([string]::IsNullOrWhiteSpace($DefaultSize)) {
    $DefaultSize = "400MB"
}   

if ([string]::IsNullOrWhiteSpace($DefaultVideoDir)) {
    $DefaultVideoDir = "D:\Desktop\Tablo\rec" 
}

# if ([string]::IsNullOrWhiteSpace($DefaultVideoQuality)) {
# 	$DefaultVideoQuality = "23"
#    }   

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

$formHght = 850
$formWidth = 1200
$listViewHght = 320

# --- Form ---
$form = New-Object System.Windows.Forms.Form
$form.Font = $global:FontRegular
$form.Text = "Join video files ts → mp4  ffmpeg"
$form.Size = New-Object System.Drawing.Size($formWidth,$formHght)
$form.StartPosition = "CenterScreen"
Set-FormTheme -Form $form -Mode $currentMode

$topStrt = 40
$spacing = 50
$top = $topstrt
$topstrtgrp = 40

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

$top = (1*$spacing) + $topstrt

# --- Destination folder ---
$textboxDest, $labelDest = Add-InputRow $form "Destination Folder:"   $top "textbox"
$textboxDest.ReadOnly = $true
$textboxDest.Text =  $DefaultDest

$browseDestButton, $null = Add-InputRow $form ""   $top "browse"
$browseDestButton.Add_Click({
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $textboxDest.Text = $dlg.SelectedPath
    }
})

$top = (2*$spacing) + $topstrt

# Maximumconcurrent jobs Label & Textbox
$textboxMaxJobs , $labelMaxJobs  = Add-InputRow $form "Max Concurrent Jobs:"   $top "textbox"
$textboxMaxJobs.Text = $DefaultMaxJobs
$textboxMaxJobs.Width = 35
$textboxMaxJobs.Left = $global:labelLeft + $labelMaxJobs.Width

# --- Run Mode Label ---

$comboBoxRunMode, $labelrunMode = Add-InputRow $form "FFmpeg Run Mode:"   $top "combobox"
$labelrunMode.Left = $global:labelLeft + $labelMaxJobs.Width + $textboxMaxJobs.Width + 20
$comboBoxRunMode.Left = $global:labelLeft + $labelMaxJobs.Width + $textboxMaxJobs.Width + 20 + $labelrunMode.Width
$comboBoxRunMode.Width = 475
$comboBoxRunMode.DropDownStyle = 'DropDownList'

# Map friendly names to internal values
$runModeDisplayMap = @{ 
    "Re-encode Only"		    = "fallback"
    "Remux/Re-encode on failure"    = "both"
    "Remux Only"		    = "fast" 
}

# Populate ComboBox with friendly names (convert Keys to array of strings)
$comboBoxRunMode.Items.AddRange(@($runModeDisplayMap.Keys))
# Set initial selection based on stored DefaultRunMode
$comboBoxRunMode.Text = ($runModeDisplayMap.Keys | Where-Object { 
    $runModeDisplayMap[$_] -eq $DefaultRunMode 
})
$top = (3*$spacing) + $topstrt
# ---------------------------------------------------------------
# --- FFmpeg Encoding Check Box ---
# ===============================================================

$CheckboxEnc, $label = Add-InputRow $form "" $top "checkbox"
$CheckboxEnc.text = "FFmpeg Encoding Parameters"

$CheckboxEnc.Appearance = [System.Windows.Forms.Appearance]::Button
# $CheckboxEnc.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$CheckboxEnc.FlatAppearance.BorderSize = 0
$CheckboxEnc.BackColor = [System.Drawing.ColorTranslator]::FromHtml("#444")
$CheckboxEnc.ForeColor = [System.Drawing.Color]::White
$CheckboxEnc.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter

$top = (4*$spacing) + $topstrt


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
$comboProfile.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
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
if ($null -ne $DefaultVideoQuality) {
    $comboVidQual.SelectedItem = $DefaultVideoQuality.ToString()
}
else {
    $comboVidQual.SelectedIndex = 0  # Select blank option
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

 # $groupEnc.Visible = $false

$top = (8*$spacing) + $topstrt
#$top = (15*$spacing) + $topstrt

# --- Start button ---
$btnStart, $null = Add-InputRow $form ""   $top "button"
$btnStart.Text = "Start Processing"
$btnStart.Location = New-Object System.Drawing.Point($global:labelLeft, $top)
$btnStart.Width = $buttonwidth + 30


# --- Cancel button ---
$btnCancel, $null = Add-InputRow $form ""   $top "button"
$btnCancel.Text = "Cancel Processing"
$btnCancel.Height = $buttonHght
$btnCancel.Width = $buttonwidth + 30
$btnCancel.Left = $global:labelLeft + 650
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
[void]$listView.Columns.Add("Final Status",140)
Set-ListViewStyle -ListView $listView -Mode $currentMode
$form.Controls.Add($listView)

# ------------------------------------------------------------------------
# EncParamDisplay
# Displays encoding parameters based upon $CheckboxEnc.Checked
# =========================================================================
function EncParamDisplay {

   $isVisible = $CheckboxEnc.Checked
    $groupEnc.Visible = $isVisible
   
    if ($isVisible) {
	$dispEnc = 4*$spacing
    } else {
	$dispEnc = 0
    }

    $top = ((4*$spacing) + $topstrt)
    $btnStart.Top = $top + $dispEnc
     
    $btnCancel.Top = $top + $dispEnc

    $top = ((5*$spacing) + $topstrt)
    $listView.Top = $top + $dispEnc

	}
	    

# ------------------------------------------------------------------------
# RemuxDisplay
# Displays encoding parameters based upon run mode
# =========================================================================
function RemuxDisplay {
    
    $CheckboxEnc.Visible = $false
    $groupEnc.Visible = $false
    $top = ((4*$spacing) + $topstrt)
    $btnStart.Top = $top + $dispEnc  
    $btnCancel.Top = $top + $dispEnc
    $top = ((5*$spacing) + $topstrt)
    $listView.Top = $top + $dispEnc

}

if ($comboBoxRunMode.Text -eq "Remux Only") {
	RemuxDisplay
}

$comboBoxRunMode.Add_SelectedIndexChanged({

    if ($comboBoxRunMode.Text -eq "Remux Only") {
	RemuxDisplay
   
    } else {
	$CheckboxEnc.Visible = $true
	EncParamDisplay
    }

})

EncParamDisplay

#
# CheckboxEnc.Add_CheckedChanged
#
#
$CheckboxEnc.Add_CheckedChanged({
    EncParamDisplay
    if ($CheckboxEnc.Checked) {
	$CheckboxEnc.BackColor = ([System.Drawing.Color]::FromArgb(100, 100, 100))
    }
    else {
        $CheckboxEnc.BackColor = [System.Drawing.ColorTranslator]::FromHtml("#444")
    }
})




# ----------------------
# Button Cancel Event
# ----------------------
$btnCancel.Add_Click({

    foreach ($job in $global:jobs) {
	if ($job.State -in 'Running','NotStarted') {
	    Stop-Job $job -ErrorAction SilentlyContinue
	}

	Remove-Job $job -Force -ErrorAction SilentlyContinue
    }

    $global:jobs = @()
    $global:folderQueue.Clear()

    $btnStart.Enabled  = $true
    $btnCancel.Enabled = $false

    # stop timer
    $timer.Stop()

     # clear the list view
    $listView.Items.Clear()
    
    Get-Process ffmpeg -ErrorAction SilentlyContinue |
    Stop-Process -Force

    return
}) # End $btnCancel



$btnStart.DialogResult = [System.Windows.Forms.DialogResult]::OK
$form.AcceptButton = $btnStart

# ----------------------
# Button Start Event
# ----------------------
$btnStart.Add_Click({
   
    $btnStart.Enabled  = $false
    $btnCancel.Enabled = $true

    # --- Read inputs directly from GUI ---
    $videoDir			= $textboxVideoDir.Text.Trim()
    $global:destination		= $textboxDest.Text.Trim()
    $global:videoQuality	= $comboVidQual.SelectedItem
    $global:maxConcurrentJobs	= [int]$textboxMaxJobs.Text
    # $global:encoder		= $comboBoxUsing.SelectedItem
   
    $global:runMode		= $runModeDisplayMap[$comboBoxRunMode.Text]

    # Get Encoding Profile delected
    $global:selectedEncodingProfile = $comboProfile.SelectedItem
    $global:encodingProfile = $profiles[$global:selectedEncodingProfile]

    # Get audio override selected
    $global:selectedAudioProfile = $comboBoxAudio.SelectedItem
    $global:audioProfile =$audioOverride[$global:selectedAudioProfile]

    # Get preset selected
    $global:selectedPresetValue = $presets[$comboBoxPreset.SelectedItem]

    # try {
    #	$global:minFileSizeBytes = Convert-ToBytes $textboxMinSize.Text
    # } catch {
    #	Write-Host "Error: $_"
    #	return
    # }

    Write-Host "Using Encoder: $global:encoder"
    Write-Host "Run Mode: $global:runMode"
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
    Write-Host  Override Audio Channels: $global:audioProfile.Channels
    Write-Host  Override Audio Bitrate: $global:audioProfile.Bitrate
    Write-Host "Min File Size: $global:minFileSizeBytes bytes"
    Write-Host "Preset:  $global:selectedPresetValue"

    # --- Validation ---
    if ([string]::IsNullOrWhiteSpace($videoDir) -or -not (Test-Path $videoDir)) {
	Show-Alert -Title "Invalid Video Directory" -Message "Please select a valid video directory."
        $form.DialogResult = [System.Windows.Forms.DialogResult]::None
        return
    }

    if ([string]::IsNullOrWhiteSpace($global:destination)) {
	Show-Alert -Title "Invalid Destination Directory"-Message "Please select a valid destination directory."
        $form.DialogResult = [System.Windows.Forms.DialogResult]::None
        return
    }

    if (-not (Test-Path $global:destination)) {
	Show-Alert -Title "Invalid Destination Directory"-Message "Please select a valid destination directory."
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

    $settings.SEGvideoDir      = $videoDir
    $settings.Destination   = $global:destination
    $settings.VideoQuality  = $global:videoQuality
    $settings.ProfileName   = $global:selectedEncodingProfile
    $settings.MaxJobs       = $global:maxConcurrentJobs
    $settings.MinSize       = $textboxMinSize.Text
    $settings.AudioOverride = $global:selectedAudioProfile
    $settings.Preset        = $comboBoxPreset.SelectedItem
    $settings.RunMode	    = $runModeDisplayMap[$comboBoxRunMode.Text]


   Save-Settings $settings 

    $btnStart.Enabled  = $false
    $btnCancel.Enabled = $true

    # --- Prepare logs directory ---
    $global:logDir = Join-Path $PSScriptRoot "logs"
    if (-not (Test-Path $global:logDir)) {
        New-Item -ItemType Directory -Path $global:logDir | Out-Null
    }

    # --- Initialize global job tracking ---
    $global:itemMap   = @{}
    $global:successCount = 0
    $global:failCount    = 0
    $global:folderQueue  = [System.Collections.Queue]::new()
    $global:jobs         = @()

    # --- Load folders into queue ---
    $videoFolders = Get-ChildItem -Path $videoDir -Directory
    $i = 0
    $total = $videoFiles.Count
    # Write-Host "Queue=$($global:fileQueue.Count)"

    foreach ($folder in $videoFolders) {
        $global:folderQueue.Enqueue($folder)
    }

    # Write-Host "Queue=$($global:fileQueue.Count)"


    # --- Start timer for throttled job processing ---
    $global:timer = New-Object System.Windows.Forms.Timer
    $global:timer.Interval = 1000

# ----------------------
#  Time Event 
# ----------------------

    $global:timer.Add_Tick({
        # Write-Host "Queue=$($global:folderQueue.Count), Jobs=$($global:jobs.Count), MaxJobs=$($global:maxConcurrentJobs)"
	# Write-Host "videoQuality: $global:videoQuality"

	if (-not (Test-Path $global:ffmpegPath)) {
	    Show-Alert -Title "FFmpeg Error"-Message "FFmpeg not found at $global:ffmpegPath"
	    return
	}
	
	# --- Collect running job updates ---
	$running = $global:jobs | Where-Object { $_.State -eq 'Running' }
	foreach ($rj in $running) {
	    $updates = Receive-Job $rj -Keep   # <- IMPORTANT: don't remove them, just peek
	    foreach ($r in $updates) {
		$form.Invoke([Action]{
		    $item = $global:itemMap[$r.Folder]
		    if ($null -ne $item) {
			$item.SubItems[2].Text = $r.FastStatus
			$item.SubItems[3].Text = $r.FallbackStatus
			$item.SubItems[4].Text = $r.FinalStatus
		    }
		})
	    }
}

	$i = 0
	$total = $global:fileQueue.Count

        # Start jobs if slots available
        while (($global:jobs | Where-Object { $_.State -in 'Running','NotStarted' }).Count -lt $global:maxConcurrentJobs -and
               $global:folderQueue.Count -gt 0) {

	    $folder     = $global:folderQueue.Dequeue()
            $folderName = $folder.Name
            $folderPath = $folder.FullName
            $segsPath   = Join-Path $folderPath "segs"
            $outputFile = Join-Path $global:destination "$folderName.mp4"
            $logFile    = Join-Path $global:logDir "$folderName.log"
	    $i++

	    # Add row to ListView FIRST
            $form.Invoke([Action]{
                $item = $listView.Items.Add($folderName)
                [void]$item.SubItems.Add($outputFile)
                [void]$item.SubItems.Add("—")  # Fast status
                [void]$item.SubItems.Add("—")  # Fallback status
                [void]$item.SubItems.Add("—")  # Final status

                $global:itemMap[$folderName] = $item
            })

            # Build the list of video files

            $tsFiles = @(
                Get-ChildItem -Path $segsPath -Filter "*.ts" -File `
                    -ErrorAction SilentlyContinue |
                    Sort-Object Name
            )

            # Fall back to MP4 files if no TS files were found
            if ($tsFiles.Count -eq 0) {
                $tsFiles = @(
                    Get-ChildItem -Path $segsPath -Filter "*.mp4" -File `
                        -ErrorAction SilentlyContinue |
                        Sort-Object Name
                )
            }

            # No TS or MP4 files found
            if ($tsFiles.Count -eq 0) {

                $message = "No TS or MP4 files found - skipping: $folderName"

                $message | Out-File -FilePath $logFile -Append

                $form.Invoke([Action]{
                    $item = $global:itemMap[$folderName]

                    if ($null -ne $item) {
                        $item.SubItems[2].Text = "Failed"
                        $item.SubItems[3].Text = "No video files"
                        $item.SubItems[4].Text = "Skipped"
                    }
                })

                # Skip this folder and process the next one
                $global:failCount++
                continue
            }

            # Skip files that already exist
           if (Test-Path $outputFile) {
	    Write-Host "$outputFile exists, no action will be performed"

	    $form.Invoke([Action]{
		$item = $global:itemMap[$folderName]

		if ($null -ne $item) {
		    $item.SubItems[2].Text = "Skipped"
		    $item.SubItems[3].Text = "Existing file"
		    $item.SubItems[4].Text = "Already exists"
		}
	    })

	    continue
	}





	    # ------------------
	    #  Start Job Thread
	    # ------------------

            # Start thread job
            $global:jobs += Start-ThreadJob -Name $folderName -ScriptBlock {
		param(
		    $folderName,
		    $segsPath,
		    $outputFile,
		    $logFile,
		    $runMode,
		    $videoQuality,
		    $encoder, 
		    $encodingProfile,
		    $selectedEncodingProfile,
		    $audioProfile,
		    $selectedAudioProfile,
		    $selectedPresetValue,
		    $ffmpegPath,
		    $mcebuddyCLI,
		    $handBrakeCLI,
		     $rootDir
		)

		$fastStatus     = "Queued"
		$fallbackStatus = "—"
		$status         = "—"   
		$mode   = "fast"
		$log = @()

		Write-Output ([PSCustomObject]@{
		    Folder         = $folderName
		    FastStatus     = $fastStatus
		    FallbackStatus = $fallbackStatus
		    FinalStatus    = $status
		})

		# Build the FFmpeg concat list
		$mylistPath = Join-Path $segsPath "mylist.txt"

		Remove-Item -LiteralPath $mylistPath -ErrorAction SilentlyContinue

		# Find TS files first
		$inputFiles = @(
		    Get-ChildItem -LiteralPath $segsPath -Filter "*.ts" -File `
			-ErrorAction SilentlyContinue |
			Sort-Object Name
		)

		# Use MP4 files if no TS files exist
		if ($inputFiles.Count -eq 0) {
		    $inputFiles = @(
			Get-ChildItem -LiteralPath $segsPath -Filter "*.mp4" -File `
			    -ErrorAction SilentlyContinue |
			    Sort-Object Name
		    )
		}

		# Verify that files were found
		if ($inputFiles.Count -eq 0) {
		    "No TS or MP4 files found - skipping: $folderName" |
			Out-File -FilePath $logFile -Encoding UTF8 -Append

		    return [PSCustomObject]@{
			Folder         = $folderName
			FastStatus     = "Fail"
			FallbackStatus = "—"
			FinalStatus    = "Failed"
		    }
		}

		# Write one entry for each file
		$concatLines = foreach ($file in $inputFiles) {
		    $fullPath = $file.FullName -replace "'", "'\''"
		    "file '$fullPath'"
		}

		[System.IO.File]::WriteAllLines(
		    $mylistPath,
		    [string[]]$concatLines,
		    [System.Text.Encoding]::ASCII
		)

		# Verify that the list was created
		if (-not (Test-Path -LiteralPath $mylistPath) -or
		    (Get-Item -LiteralPath $mylistPath).Length -eq 0) {

		    "Failed to create FFmpeg list: $mylistPath" |
			Out-File -FilePath $logFile -Encoding UTF8 -Append

		    return [PSCustomObject]@{
			Folder         = $folderName
			FastStatus     = "Fail"
			FallbackStatus = "—"
			FinalStatus    = "Failed"
		    }
		}
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

		 # "DEBUG: Encoders -> Video=$videoEncoder, Audio=$audioEncoder, Bitrate=${audioBitrate}k, CRF=$videoQuality" |
		 #   Out-File -FilePath $logFile -Append

		$FFmpegFunctions = Join-Path $rootDir "etc\FFmpegFunctions.ps1"
		. $FFmpegFunctions


		#
		# Profile  = "Copy"	    $Source   = $inputPath
		# Profile  = "Encode"	    $Source   = $inputPath
		# Profile  = "ConcatCopy    $Source  = $myListPath
		# Profile  = "ConcatEncode" $Source   = $myListPath
		#

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

		 # ----------------------
		    # Fast mode = ffmpeg copy
		    # -------------------
		if ($runMode -in @("both","fast")) {

		    "DEBUG: Copy -> args -> $args" |
			Out-File -FilePath $logFile -Append

		    Write-Output ([PSCustomObject]@{
			Folder         = $folderName
			FastStatus     = "Running..."
			FallbackStatus = $fallbackStatus
			FinalStatus    = $status
		    })

		    try {
			# --- FAST CONCAT ---
			$ffmpegOutput = & $encoderPath @args 2>&1 
			$ffmpegOutput | Out-File -FilePath $logFile -Append	    
			$exitCode = $LASTEXITCODE
		    } catch {
			"$($_.Exception.Message)" | Out-File -FilePath $logFile -Encoding UTF8 -Append
			$exitCode = 1
		    }
		    
		    # if ffmpeg copy fails mode = fast {return} mode=both [continue and try to re-encode)
		    
		    if ($exitCode -eq 0 -and (Test-Path $outputFile)) {
			$log | Out-File -FilePath $logFile -Append
			$fastStatus = "Pass"
			$fallbackStatus = "—"
			$status         = "Success"   
			return [PSCustomObject]@{
				    Folder         = $folderName
				    FastStatus     = $fastStatus
				    FallbackStatus = $fallbackStatus
				    FinalStatus    = $status}


		    } else {
			$fastStatus = "Fail"

			# Remux-only mode: do not attempt re-encoding
			if ($runMode -eq "fast") {

			    # Rename partial output only if it exists
			    if (Test-Path $outputFile) {
				$failedPath = [System.IO.Path]::ChangeExtension(
				    $outputFile, $null
				) + "_FAILED.mp4"

				Rename-Item -Path $outputFile `
				    -NewName (Split-Path $failedPath -Leaf) -Force

				$log += "Renamed failed output to $failedPath"
			    }

			    $status = "Failed"
			    $fallbackStatus = "—"

			    $log += "Remux failed. Re-encode skipped because remux-only mode is selected."
			    $log | Out-File -FilePath $logFile -Encoding UTF8 -Append

			    return [PSCustomObject]@{
				Folder         = $folderName
				FastStatus     = $fastStatus
				FallbackStatus = $fallbackStatus
				FinalStatus    = $status
			    }
			}
		    }
		}
		
		
		$fallbackStatus = "Running..."

		# at this point mode is "fallback" or "both"
		Write-Output ([PSCustomObject]@{
		    Folder         = $folderName
		    FastStatus     = $fastStatus
		    FallbackStatus = $fallbackStatus
		    FinalStatus    = $status
		})
		# ----------------------
		# FALLBACK ffmpeg RE-ENCODE
		# ----------------------

		$mode = "fallback"
		$fallbackStatus = "Running..."

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
		    

		"DEBUG: ReEncode -> args -> $args" |
		    Out-File -FilePath $logFile -Append
		    
		try {
		    # $ffmpegOutput = & $ffmpegPath @ffmpegArgsConcatEnc 2>&1
		    $ffmpegOutput = & $encoderPath @args 2>&1 
		    # $ffmpegOutput | Out-File -FilePath $logFile -Encoding UTF8 -Append

		    if ($LASTEXITCODE -eq 0) {
			$status = "Success"
			$fallbackStatus = "Pass"
		    } else {
			if (Test-Path $outputFile) {
			    $failedPath = [System.IO.Path]::ChangeExtension($outputFile, $null) + "_FAILED.mp4"
			    Rename-Item -Path $outputFile -NewName $failedPath -Force
			    $log += " Renamed failed output to $failedPath"
			}
			$status = "Failed"
			$fallbackStatus = "Fail"
			# Emit final result for timer loop & GUI

			[PSCustomObject]@{
			    Folder         = $folderName
			    FastStatus     = $fastStatus
			    FallbackStatus = $fallbackStatus
			    FinalStatus    = $status
			}
			$log | Out-File -FilePath $logFile -Append
			return  # Stop thread immediately on failure
		    }
		}
		catch {
		    "$($_.Exception.Message)" | Out-File -FilePath $logFile -Encoding UTF8 -Append
		    $status = "Failed"
		    $fastStatus = "Fail"
		    [PSCustomObject]@{
			    Folder         = $folderName
			    FastStatus     = $fastStatus
			    FallbackStatus = $fallbackStatus
			    FinalStatus    = $status
			}
		    $log | Out-File -FilePath $logFile -Append
		    return
		}   

		# Return status to timer loop
		[PSCustomObject]@{
		    Folder        = $folderName
		    FastStatus    = $fastStatus
		    FallbackStatus= $fallbackStatus
		    FinalStatus   = $status
		}
		$log | Out-File -FilePath $logFile -Append

            } -ArgumentList $folderName,
			    $segsPath,
			    $outputFile,
			    $logFile,
			    $global:runMode,
			    $global:videoQuality,
			    $global:encoder,
			    $global:encodingProfile,
			    $global:selectedEncodingProfile,
			    $global:audioProfile,
			    $global:selectedAudioProfile,
			    $global:selectedPresetValue,
			    $global:ffmpegPath,
			    $global:mcebuddyCLI,
			    $global:handBrakeCLI,
			    $rootDir

 
	} # end of while jobs

	 # --- Collect finished jobs ---
	$finished = $global:jobs | Where-Object { $_.State -eq 'Completed' }
	foreach ($fj in $finished) {
	    $results = Receive-Job $fj

	    Write-Host "Finished job: $($fj.Name)"
	    Write-Host "Job state: $($fj.State)"
	    Write-Host "Result count: $(@($results).Count)"

	    $results | ForEach-Object {
		Write-Host "Result: Folder=$($_.Folder); Fast=$($_.FastStatus); Fallback=$($_.FallbackStatus); Final=$($_.FinalStatus)"
	    }
	    
	    # assume the last object has the FinalStatus
	    $r = $results[-1]
	    # foreach ($r in $results) {
	    $form.Invoke([Action]{
		$item = $global:itemMap[$r.Folder]
		if ($null -ne $item) {
		    $item.SubItems[2].Text = $r.FastStatus
		    $item.SubItems[3].Text = $r.FallbackStatus
		    $item.SubItems[4].Text = $r.FinalStatus
		}
	    })
	    if ($r.FinalStatus -eq "Success") { $global:successCount++ } else { $global:failCount++ }
	    # }

	    Remove-Job $fj
	    $global:jobs = $global:jobs | Where-Object { $_.Id -ne $fj.Id }
	}

        # Stop timer if done
        if ($global:jobs.Count -eq 0 -and $global:folderQueue.Count -eq 0) {
            $global:timer.Stop()
            Write-Host "Total Success: $($global:successCount)"
            Write-Host "Total Failed : $($global:failCount)"

	    $btnStart.Enabled  = $true
	    $btnCancel.Enabled = $false

	    $form.Invoke([Action]{
		$item = $listView.Items.Add("All Jobs Completed")
		[void]$item.SubItems.Add("Success: $($global:successCount)")
		[void]$item.SubItems.Add("Failed: $($global:failCount)")
		[void]$item.SubItems.Add("Finished")
	    })
	}   

    })  # end of timer event handler

    $global:timer.Start()

}) # End $btnStart


# Use last control to determine needed height
$bottomMostButton = $listView
$neededHeight = $bottomMostButton.Bottom + 50
$form.Height = $neededHeight

# --- Show the form ---
[System.Windows.Forms.Application]::Run($form)
# [System.Windows.Forms.Application]::EnableVisualStyles()
