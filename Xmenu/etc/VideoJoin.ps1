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


$top = (3*$spacing-10) + $topstrt

# Seperator
# $null , $label  = Add-InputRow $form "Encoding Parameters   __________________________________________________________________________________"   $top "$null"

# Seperator
$CheckboxEnc, $label = Add-InputRow $form "" $top "checkbox"
$CheckboxEnc.text = "FFmpeg Encoding Parameters _________________________________________________________"

$top = (4*$spacing-10) + $topstrt

# Video Quality Label & Textbox
$textboxVidQual , $labelVidQual  = Add-InputRow $form "Video Quality (CRF, 15-30):"   $top "textbox"
$textboxVidQual.Width = 30
$textboxVidQual.Left = $global:labelLeft  + $labelVidQual.Width
$textboxVidQual.Text = $DefaultVideoQuality

# Video Profile
$comboProfile , $labelProfile  = Add-InputRow $form "Video Profile:"   $top "combobox"
$labelProfile.Left = $global:labelLeft2
$comboProfile.Left = $global:labelLeft2 + $labelProfile.Width
$comboProfile.Size     = New-Object System.Drawing.Size(250, 30)
$comboProfile.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
$comboProfile.Items.AddRange([string[]]$profiles.Keys)
$comboProfile.SelectedItem = $DefaultProfileName

$top = (5*$spacing-20) + $topstrt

# Label encoder preset
$comboBoxPreset , $labelPreset  = Add-InputRow $form  "Encoder Preset:"   $top "combobox"
$comboBoxPreset.Left = $global:labelLeft + $labelPreset.Width
$comboBoxPreset.Size = New-Object System.Drawing.Size(230,30)
$comboBoxPreset.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
$comboBoxPreset.Items.AddRange([string[]]$presets.Keys)
$comboBoxPreset.SelectedItem = $DefaultPresetValue

# Label audio override
$comboBoxAudio , $labelAudio  = Add-InputRow $form  "Audio Override:"   $top "combobox"
$labelAudio.Left = $global:labelLeft2
$comboBoxAudio.Left = $global:labelLeft2 + $labelAudio.Width
$comboBoxAudio.Size = New-Object System.Drawing.Size(250,30)
$comboBoxAudio.Items.AddRange([string[]]$audioOverride.Keys)
$comboBoxAudio.SelectedItem = $DefaultAudioName


$top = (7*$spacing-10) + $topstrt

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

if ($comboBoxRunMode.Text -eq "Remux Only") {
    $label.Visible = $false
    $labelVidQual.Visible = $textboxVidQual.Visible = $false
    $labelProfile.Visible = $comboProfile.Visible = $false
    $labelPreset.Visible = $comboBoxPreset.Visible = $false
    $labelAudio.Visible =  $comboBoxAudio.Visible = $false
    $top = (4*$spacing-10) + $topstrt
    $btnStart.Location = New-Object System.Drawing.Point($labelLeft,$top)
    $top = (5*$spacing-10) + $topstrt
    $listView.Location = New-Object System.Drawing.Point(10,$top)
    $btnCancel.Top = $top
}

# ------------------------------------------------------------------------
# EncParamDisplay
# Displays encoding parameters based upon $CheckboxEnc.Checked
# =========================================================================
function EncParamDisplay {

    param(
	[boolean]$isVisible
    )
   
    # $isVisible = $CheckboxEnc.Checked
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

#
# set startup display items
#

if ($comboBoxRunMode.SelectedItem -eq "Remux Only") {
    $CheckboxEnc.Visible = $false
     EncParamDisplay -isVisible $false
} else {
    $CheckboxEnc.Visible = $true
    EncParamDisplay -isVisible $true
}

EncParamDisplay -isVisible $CheckboxEnc.Checked



#
# comboBoxRunMode.Add_SelectedIndexChanged
#
#
$comboBoxRunMode.Add_SelectedIndexChanged({
    switch ($comboBoxRunMode.SelectedItem) {

	"Remux Only" {
	    $CheckboxEnc.Visible = $false
	    EncParamDisplay -isVisible $false
	}
	    
	default {
	    $CheckboxEnc.Visible = $true
	    EncParamDisplay -isVisible $true
        }
    }
})

#
# CheckboxEnc.Add_CheckedChanged
#
#
$CheckboxEnc.Add_CheckedChanged({
    EncParamDisplay -isVisible $CheckboxEnc.Checked
    
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
    $global:videoQuality	= $textboxVidQual.Text.Trim()
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

    if (-not [int]::TryParse($global:videoQuality, [ref]$null) -or
        [int]$global:videoQuality -lt 15 -or [int]$global:videoQuality -gt 30) {
	Show-Alert -Title "Invalid Input"-Message "Please enter a valid Video Quality (CRF) number between 15 and 30."
        $form.DialogResult = [System.Windows.Forms.DialogResult]::None
        return
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
	    $tsFiles = Get-ChildItem -Path $segsPath -Filter "*.ts" -File | Sort-Object Name
	    if ($tsFiles.Count -gt 0) {
		$videoFiles = $tsFiles
	    } else {
		$mp4Files = Get-ChildItem -Path $segsPath -Filter "*.mp4" -File | Sort-Object Name
		if ($mp4Files.Count -gt 0) {
		    $videoFiles = $mp4Files
		} else {
		    continue  # no valid files, skip this folder
		}
	    }
	    if (Test-Path $outputFile) {
		Write-Host " "
		Write-Host $outputFile exists, no action will be performed 
		continue 
	    }

            # Add row to ListView
            $form.Invoke([Action]{
                $item = $listView.Items.Add($folderName)
		[void]$item.SubItems.Add($outputFile)
		[void]$item.SubItems.Add("—")	    # Fast status   
                [void]$item.SubItems.Add("—")	    # Fallback status
		[void]$item.SubItems.Add("—")	    # Final col
                $global:itemMap[$folderName] = $item
		
            })

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

		# Write file list for ffmpeg concat
		$mylistPath = Join-Path $segsPath "mylist.txt"
		Remove-Item -Path $mylistPath -ErrorAction SilentlyContinue

		# Get-ChildItem $segsPath -Filter "*.ts" | Sort-Object Name |
                 #   ForEach-Object { "file '$($_.Name)'" | Out-File -FilePath $mylistPath -Encoding ASCII -Append }

		$tsFiles = Get-ChildItem -Path $segsPath -Filter "*.ts" -File | Sort-Object Name
		if ($tsFiles.Count -gt 0) {
		    $videoFiles = $tsFiles
		} else {
		    $mp4Files = Get-ChildItem -Path $segsPath -Filter "*.mp4" -File | Sort-Object Name
		    if ($mp4Files.Count -gt 0) {
			$videoFiles = $mp4Files
		    }
		}
		$videoFiles | ForEach-Object {
		    "file '$($_.Name)'" | Out-File -FilePath $mylistPath -Encoding ASCII -Append
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
			# $ffmpegOutput | Out-File -FilePath $logFile -Encoding UTF8 -Append	    
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
			# Only rename failed output if we're in fast-only mode
			if ($runMode -eq "fast" -and (Test-Path $outputFile)) {
			    $failedPath = [System.IO.Path]::ChangeExtension($outputFile, $null) + "_FAILED.mp4"
			    Rename-Item -Path $outputFile -NewName $failedPath -Force
			    $log += " Renamed failed output to $failedPath"
			    $log | Out-File -FilePath $logFile -Append
			    $status         = "Failed"  
			    return [PSCustomObject]@{
					Folder         = $folderName
					FastStatus     = $fastStatus
					FallbackStatus = $fallbackStatus
					FinalStatus    = $status}
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
