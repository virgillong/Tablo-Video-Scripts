Add-Type -AssemblyName 'System.Windows.Forms'
Add-Type -AssemblyName 'System.Drawing'
Import-Module ThreadJob

# Default path fallback for rootDir
if (-not $env:rootDir) {
    $env:rootDir = (Resolve-Path "$PSScriptRoot\..").Path
}
$rootDir = $env:rootDir 


Import-Module (Join-Path $rootDir "etc\includes\UIHelpers.psm1") -Force
Import-Module (Join-Path $rootDir "etc\includes\alert.psm1") -Force

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
	Show-Alert -Message "Invalid size format. Use numeric bytes or format like 400MB."
        
    }
}

$themeFile = Join-Path $rootDir "data\theme.txt"
$currentMode = Import-ThemeState -themeFile $themeFile
$DefaultMaxJobs = "2"
$DefaultSize = "400MB"
$defaultProfileName =  "High Compression (x265)"
$defaultAudioName =  "Surround Sound ac3"
$defaultPresetValue = "Slow (Recommended)"

$videoDirFilePath = Join-Path $rootDir "data\Videos2Encode.txt"
$videoDestFilePath = Join-Path $rootDir "data\videodest.txt"
$videoQualFilePath = Join-Path $rootDir "data\videoquality.txt"
$runModeFilePath   = Join-Path $rootDir "data\runmode.txt"

if (Test-Path -Path $videoDirFilePath) { 
    $DefaultVideoDir = (Get-Content -Path $videoDirFilePath -Raw)
    if (![string]::IsNullOrWhiteSpace($DefaultVideoDir)) {
        $DefaultVideoDir = $DefaultVideoDir.Trim()
    } else { 
	$DefaultVideoDir = "D:\Desktop\Tablo\rec" 
    }   
}
if (Test-Path -Path $videoDestFilePath) { 
    $DefaultDest = (Get-Content -Path $videoDestFilePath -Raw)
    if (![string]::IsNullOrWhiteSpace($DefaultDest)) {
        $DefaultDest = $DefaultDest.Trim()
    } else { 
	$DefaultDest = "" 
    }   
}
if (Test-Path -Path $videoQualFilePath) { 
    $DefaultVideoQuality = (Get-Content -Path $videoQualFilePath -Raw)
    if (![string]::IsNullOrWhiteSpace($DefaultVideoQuality)) {
        $DefaultVideoQuality = $DefaultVideoQuality.Trim()
    } else { 
	$DefaultVideoQuality = "23"
    }   
}
if (Test-Path -Path $runModeFilePath) { 
    $DefaultRunMode = (Get-Content -Path $runModeFilePath -Raw)
    if (![string]::IsNullOrWhiteSpace($DefaultRunMode)) {
        $DefaultRunMode = $DefaultRunMode.Trim()
    } else { 
	$DefaultRunMode = "both"
    }   
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

$labelLeft = 10
$labelLeft2 = 400
$textLeft = 200
$buttonwidth = 150
$buttonHght = 30
$formHght = 500
$formWidth = 900

# --- Form ---
$form = New-Object System.Windows.Forms.Form
$form.Font = $global:FontRegular
$form.Text = "Re-encode mp4 → mp4 Handbrake"
$form.Size = New-Object System.Drawing.Size($formWidth,$formHght)
$form.StartPosition = "CenterScreen"
Set-FormTheme -Form $form -Mode $currentMode

$topStrt = 20
$spacing = 50
$top = $topstrt

# --- Folder selection ---
$labelVideoDir = New-Object System.Windows.Forms.Label
$labelVideoDir.Text = "Videos folder:"
$labelVideoDir.Location = New-Object System.Drawing.Point($labelLeft,$top)
$labelVideoDir.AutoSize = $true
Set-LabelStyle -Label $labelVideoDir -Mode $currentMode
$form.Controls.Add($labelVideoDir)

$textboxVideoDir = New-Object System.Windows.Forms.TextBox
$textboxVideoDir.Location = New-Object System.Drawing.Point($textLeft,$top)
$textboxVideoDir.Size = New-Object System.Drawing.Size(420,20)
$textboxVideoDir.Text = $DefaultVideoDir
Set-TextboxStyle -Textbox $textboxVideoDir -Mode $currentMode
$form.Controls.Add($textboxVideoDir)

$browseVideoDir = New-Object System.Windows.Forms.Button
$browseVideoDir.Text = "Browse"
$browseVideoDir.Size = New-Object System.Drawing.Size($buttonwidth,$buttonHght)
$browseVideoDir.Left = 630
$browseVideoDir.Top = $top-2
$browseVideoDir.Add_Click({
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $textboxVideoDir.Text = $dlg.SelectedPath
    }
})
Set-ButtonStyle -Button $browseVideoDir -Mode $currentMode
$form.Controls.Add($browseVideoDir)

$top = (1*$spacing) + $topstrt

# --- Temp MP4 folder ---
$labelDest = New-Object System.Windows.Forms.Label
$labelDest.Text =  "Destination Folder:"
$labelDest.Location = New-Object System.Drawing.Point($labelLeft,$top)
$labelDest.AutoSize = $true
Set-LabelStyle -Label $labelDest -Mode $currentMode
$form.Controls.Add($labelDest)

$textboxDest = New-Object System.Windows.Forms.TextBox
$textboxDest.Location = New-Object System.Drawing.Point(200,$top)
$textboxDest.Size = New-Object System.Drawing.Size(420,20)
$textboxDest.Text =  $DefaultDest
Set-TextboxStyle -Textbox $textboxDest -Mode $currentMode
$form.Controls.Add($textboxDest)

$browseDestButton = New-Object System.Windows.Forms.Button
$browseDestButton.Text = "Browse"
$browseDestButton.Size = New-Object System.Drawing.Size($buttonwidth,$buttonHght)
$browseDestButton.Left = 630
$browseDestButton.Top = $top-2
$browseDestButton.Add_Click({
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $textboxDest.Text = $dlg.SelectedPath
    }
})
Set-ButtonStyle -Button $browseDestButton -Mode $currentMode
$form.Controls.Add($browseDestButton)

$top = (2*$spacing) + $topstrt

# Maximumconcurrent jobs Label & Textbox
$labelMaxJobs = New-Object Windows.Forms.Label
$labelMaxJobs.Text = "Max Concurrent Jobs"
$labelMaxJobs.AutoSize = $true
$labelMaxJobs.Left = $labelLeft
$labelMaxJobs.Top = $top
$form.Controls.Add($labelMaxJobs)
Set-LabelStyle -Label $labelMaxJobs -Mode $currentMode

$textboxMaxJobs = New-Object Windows.Forms.TextBox
$textboxMaxJobs.Width = 35
$textboxMaxJobs.Left = $textLeft + 10
$textboxMaxJobs.Top = $top
$textboxMaxJobs.Text = $DefaultMaxJobs
$form.Controls.Add($textboxMaxJobs)
Set-TextboxStyle -Textbox $textboxMaxJobs -Mode $currentMode

# Minimum Size Label & Textbox
$labelMinSize = New-Object Windows.Forms.Label
$labelMinSize.Text = "Min Size (e.g., 400MB or 100000000):"
$labelMinSize.AutoSize = $true
$labelMinSize.Left = $labelLeft + 290
$labelMinSize.Top = $top
$form.Controls.Add($labelMinSize)
Set-LabelStyle -Label $labelMinSize -Mode $currentMode

$textboxMinSize = New-Object Windows.Forms.TextBox
$textboxMinSize.Width = 100
$textboxMinSize.Left = $labelLeft2 + 300
$textboxMinSize.Top = $top
$textboxMinSize.Text = $DefaultSize
$form.Controls.Add($textboxMinSize)
Set-TextboxStyle -Textbox $textboxMinSize -Mode $currentMode

$top = (3*$spacing-10) + $topstrt

# Seperator
$label = New-Object System.Windows.Forms.Label
$label.Text = "Encoding Parameters  _____________________________________________________________________________________________________________"
# $label.Size = New-Object System.Drawing.Size(850,30)
$label.AutoSize = $true
$label.Left = $labelLeft
$label.Top = $top
$form.Controls.Add($label)
Set-LabelStyle -Label $label -Mode $currentMode

$top = (4*$spacing-10) + $topstrt

# Video Quality Label & Textbox
$labelVidQual = New-Object System.Windows.Forms.Label
$labelVidQual.Text = "Video Quality (CRF, 15-30):"
$labelVidQual.AutoSize = $true
$labelVidQual.Left = $labelLeft
$labelVidQual.Top = $top
$form.Controls.Add($labelVidQual)
Set-LabelStyle -Label $labelVidQual -Mode $currentMode

$textboxVidQual = New-Object Windows.Forms.TextBox
$textboxVidQual.Width = 30
$textboxVidQual.Left = $textLeft + 60
$textboxVidQual.Top = $top
$textboxVidQual.Text = $DefaultVideoQuality
$form.Controls.Add($textboxVidQual)
Set-TextboxStyle -Textbox $textboxVidQual -Mode $currentMode

$labelProfile = New-Object System.Windows.Forms.Label
$labelProfile.Text = "Video Profile"
$labelProfile.AutoSize = $true
$labelProfile.Left = $labelLeft2
$labelProfile.Top = $top
$form.Controls.Add($labelProfile)
Set-LabelStyle -Label $labelProfile -Mode $currentMode

$comboProfile = New-Object System.Windows.Forms.ComboBox
$comboProfile.Left = $labelLeft2 + 150
$comboProfile.Top = $top
$comboProfile.Size     = New-Object System.Drawing.Size(250, 30)
$comboProfile.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
$comboProfile.Items.AddRange([string[]]$profiles.Keys)
$comboProfile.SelectedItem = $defaultProfileName
$form.Controls.Add($comboProfile)
Set-comboBoxStyle -comboBox $comboProfile -Mode $currentMode

$top = (5*$spacing-20) + $topstrt

# Label encoder preset
$labelPreset = New-Object System.Windows.Forms.Label
$labelPreset.Text = "Encoder Preset"
$labelPreset.AutoSize = $true
$labelPreset.Left = $labelLeft
$labelPreset.Top = $top
$form.Controls.Add($labelPreset)
Set-LabelStyle -Label $labelPreset -Mode $currentMode

# ComboBox audio override
$comboBoxPreset = New-Object System.Windows.Forms.ComboBox
$AudioLeft = $labelLeft + 150
$comboBoxPreset.Location = New-Object System.Drawing.Point($AudioLeft,$top)
$comboBoxPreset.Size = New-Object System.Drawing.Size(230,30)
$comboBoxPreset.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
$comboBoxPreset.Items.AddRange([string[]]$presets.Keys)
$comboBoxPreset.SelectedItem = $defaultPresetValue
Set-comboBoxStyle -comboBox $comboBoxPreset -Mode $currentMode
$form.Controls.Add($comboBoxPreset)


# Label audio override
$labelAudio = New-Object System.Windows.Forms.Label
$labelAudio.Text = "Audio Override"
$labelAudio.AutoSize = $true
$labelAudio.Left = $labelLeft2
$labelAudio.Top = $top
$form.Controls.Add($labelAudio)
Set-LabelStyle -Label $labelAudio -Mode $currentMode

# ComboBox audio override
$comboBoxAudio = New-Object System.Windows.Forms.ComboBox
$AudioLeft = $labelLeft2 + 150
$comboBoxAudio.Location = New-Object System.Drawing.Point($AudioLeft,$top)
$comboBoxAudio.Size = New-Object System.Drawing.Size(250,30)
$comboBoxAudio.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
$comboBoxAudio.Items.AddRange([string[]]$audioOverride.Keys)
$comboBoxAudio.SelectedItem = $defaultAudioName
Set-comboBoxStyle -comboBox $comboBoxAudio -Mode $currentMode
$form.Controls.Add($comboBoxAudio)

$top = (6*$spacing-10) + $topstrt

# --- Start button ---
$btnStart = New-Object System.Windows.Forms.Button
$btnStart.Text = "Start Processing"
$btnStart.Height = $buttonHght
$btnStart.Width = $buttonwidth + 30
$btnStart.Location = New-Object System.Drawing.Point($labelLeft,$top)
Set-ButtonStyle -Button $btnStart -Mode $currentMode
$form.Controls.Add($btnStart)

$top = (7*$spacing-10) + $topstrt

# --- ListView for job status ---
$listView = New-Object System.Windows.Forms.ListView
$listView.Location = New-Object System.Drawing.Point(10,$top)
$listView.Size = New-Object System.Drawing.Size(850,320)
$listView.View = 'Details'
$listView.FullRowSelect = $true
$listView.GridLines = $true
[void]$listView.Columns.Add("Folder",200)
[void]$listView.Columns.Add("Destination MP4",320)
[void]$listView.Columns.Add("Encode Status",120)
[void]$listView.Columns.Add("Final Status",120)
Set-ListViewStyle -ListView $listView -Mode $currentMode
$form.Controls.Add($listView)

$btnStart.DialogResult = [System.Windows.Forms.DialogResult]::OK
$form.AcceptButton = $btnStart

# ----------------------
# Button Start Event
# ----------------------
$btnStart.Add_Click({
    # clear the list view
    $listView.Items.Clear()

    # --- Read inputs directly from GUI ---
    $videoDir        = $textboxVideoDir.Text.Trim()
    $global:destination = $textboxDest.Text.Trim()
    $global:videoQuality    = $textboxVidQual.Text.Trim()
    $global:maxConcurrentJobs = [int]$textboxMaxJobs.Text
    
     # Get Encoding Profile delected
    $global:selectedVideoProfile = $comboProfile.SelectedItem
    $global:VideoProfiles = $profiles[$global:selectedVideoProfile]

    # Get audio override selected
    $global:selectedAudioProfile = $comboBoxAudio.SelectedItem
    $global:audioProfiles =$audioOverride[$global:selectedAudioProfile]

    # Get preset selected
    $global:selectedPresetValue = $presets[$comboBoxPreset.SelectedItem]

    try {
	$global:minFileSizeBytes = Convert-ToBytes $textboxMinSize.Text
    } catch {
	Write-Host "Error: $_"
	return
    }

    Write-Host "Using Profile: $global:selectedProfile"
    Write-Host "Video: $($global:VideoProfiles.VideoEncoder), Audio: $($global:VideoProfiles.AudioEncoder) @ $($global:VideoProfiles.AudioBitrate) kbps"
    Write-Host "Audio Override: $global:selectedAudioProfile "
    Write-Host "Audio Encoder: $($global:selectedAudioProfile.audioEncoder), Audio Channels: $($global:selectedAudioProfile.audioChannels), $($global:selectedAudioProfile.audioBitrate) kbps"
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

    # --- Save input state ---
    Set-Content -Path $videoDirFilePath -Value $videoDir
    Set-Content -Path $videoDestFilePath -Value $global:destination
    Set-Content -Path $videoQualFilePath -Value $global:videoQuality

    # --- Prepare logs directory ---
    $global:logDir = Join-Path $PSScriptRoot "logs"
    if (-not (Test-Path $global:logDir)) {
        New-Item -ItemType Directory -Path $global:logDir | Out-Null
    }

    # --- Initialize global job tracking ---
    $global:itemMap   = @{}
    $global:successCount = 0
    $global:failCount    = 0
    $global:fileQueue  = [System.Collections.Queue]::new()
    $global:jobs         = @()

    # --- Load video files into queue ---
    $videoFiles = Get-ChildItem -Path  $videoDir -Filter *.mp4

    $i = 0
    $total = $videoFiles.Count

    # Write-Host "Queue=$($global:fileQueue.Count)"
    
    foreach ($videoFile in $videoFiles) {
        $global:fileQueue.Enqueue($videoFile)
    }

    # Write-Host "Queue=$($global:fileQueue.Count)"

    
    # --- Start timer for throttled job processing ---
    $global:timer = New-Object System.Windows.Forms.Timer
    $global:timer.Interval = 1000

    # ----------------------
    #  Time Event 
    # ----------------------

    $global:timer.Add_Tick({
	# Write-Host "Queue=$($global:fileQueue.Count), Jobs=$($global:jobs.Count), MaxJobs=$($global:maxConcurrentJobs)"
	# Write-Host "videoQuality: $global:videoQuality"

	$ffmpegPath = "C:\ffmpeg\bin\ffmpeg.exe"

	if (-not (Test-Path $ffmpegPath)) {
	    [System.Windows.Forms.MessageBox]::Show("FFmpeg not found at $ffmpegPath", "Error",
		[System.Windows.Forms.MessageBoxButtons]::OK,
		[System.Windows.Forms.MessageBoxIcon]::Error)
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
			$item.SubItems[3].Text = $r.FinalStatus
		    }
		})
	    }
	}

	$i = 0
	$total = $global:fileQueue.Count

        # Start jobs if slots available
        while (($global:jobs | Where-Object { $_.State -in 'Running','NotStarted' }).Count -lt $global:maxConcurrentJobs -and
	    $global:fileQueue.Count -gt 0) {

            $vidfile    = $global:fileQueue.Dequeue()
	    $vidfilename = $vidfile.Name
	    $vidfilePath = $vidfile.FullName

	    $i++

	    if ($vidfile.Length -lt $global:minFileSizeBytes) {
		Write-Host "[$i/$total] Skipping (too small): $vidfilename"
		$skippedCount++
		continue
	    }

            $outputFile = Join-Path $global:destination "$vidfilename"
            $logFile    = Join-Path $global:logDir "$vidfilename.log"

            # Add row to ListView
            $form.Invoke([Action]{
                $item = $listView.Items.Add($vidfilename)   #Folder
		[void]$item.SubItems.Add($outputFile)	    # Destination
		[void]$item.SubItems.Add("—")	    # Encode status   
                [void]$item.SubItems.Add("—")		    # Final status
                $global:itemMap[$vidfilename] = $item
            })

	    # ------------------
	    #  Start Job Thread
	    # ------------------

            # Start thread job
	    $global:jobs += Start-ThreadJob -Name $vidfilename -ScriptBlock {
		param(
		    $vidfilename,
		    $inputPath,
		    $outputFile,
		    $logFile,
		    $videoQuality,
		    $ffmpegPath, 
		    $videoProfile,
		    $selectedVideoProfile,
		    $audioProfile,
		    $selectedAudioProfile,
		    $selectedPresetValue,
		     $rootDir
	    )

		$fastStatus     = "Queued"
		$status         = "—"
                $mode   = "fast"
		$log = @()

		 Write-Output ([PSCustomObject]@{
		    Folder         = $vidfilename
		    FastStatus     = $fastStatus
		    FinalStatus    = $status
		 })

		# --- Encoding Variables ---

		# get video parameters selected by user for ffmpeg encode
		$videoEncoder  = $videoProfile.Video.HandBrake
		$audioEncoder  = $videoProfile.Audio.HandBrake
		$audioBitrate  = $videoProfile.Audio.Bitrate
		$videoQuality  = $videoProfile.Video.Quality

		# see if audio override parameters  video parameters were selected for ffmpeg encode
		$audioChannels = ""
		
		if ($selectedAudioProfile -ne "None") {
		    $audioEncoder  = $audioProfile.HandBrake
		    $audioChannels = $audioProfile.Channels
		    $audioBitrate  = $audioProfile.Bitrate
		}
		 
		"DEBUG: Encoders -> preset=$selectedPresetValue, Video=$videoEncoder, Audio=$audioEncoder, Bitrate=${audioBitrate}k, Channels=$audioChannels, CRF=$videoQuality" |
		    Out-File -FilePath $logFile -Append
		  
		Write-Output ([PSCustomObject]@{
		    Folder        = $vidfilename
		    FastStatus    = "Running..."
		    FinalStatus   = "—"
		})
		 $handbrake = "HandBrakeCLI"
		
		$FFmpegFunctions = Join-Path $rootDir "etc\FFmpegFunctions.ps1"
		. $FFmpegFunctions

		#
		# Profile  = "Copy"	    $Source   = $inputPath
		# Profile  = "Encode"	    $Source   = $inputPath
		# Profile  = "ConcatCopy    $Source  = $myListPath
		# Profile  = "ConcatEncode" $Source   = $myListPath
		# Profile  = "Handbrake

		$Source   = $inputPath

		$args = Get-FFmpegArguments `
		    -RootDir $rootDir `
		    -Profile "Handbrake" `
		    -InputPath $Source `
		    -OutputPath $outputFile `
		    -VideoEncoder $videoEncoder `
		    -VideoQuality $videoQuality `
		    -AudioEncoder $audioEncoder `
		    -AudioBitrate $audioBitrate `
		    -AudioChannels $audioChannels `
		    -Preset $selectedPresetValue 

		"DEBUG: args -> $args" |
		    Out-File -FilePath $logFile -Append

		try {
		    # -- ffmpeg Encode ---
		    $fastStatus = "Running..."

		    $ffmpegOutput = & $handbrake @args 2>&1
		    # $ffmpegOutput | Out-File -FilePath $logFile -Encoding UTF8 -Append

		    if ($LASTEXITCODE -eq 0) {
			$fastStatus = "Pass"
			$status = "Success"
		    } else {
			$fastStatus = "fail"
			$status = "failed"
		    }

		}
		catch {
		    "$($_.Exception.Message)" | Out-File -FilePath $logFile -Encoding UTF8 -Append
		    $status = "Failed"
		    $fastStatus = "Fail"
		    return
		}
		# Return status to timer loop
		[PSCustomObject]@{
		    Folder        = $vidfilename
		    FastStatus    = $fastStatus
		    FinalStatus   = $status
		}

            } -ArgumentList $vidfilename,
			    $vidfilePath,
			    $outputFile,
			    $logFile,
			    $global:videoQuality,
			    $ffmpegPath,
			    $global:videoProfiles,
			    $global:selectedVideoProfile,
			    $global:audioProfiles,
			    $global:selectedAudioProfile,
			     $global:selectedPresetValue,
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
		    $item.SubItems[3].Text = $r.FinalStatus
		}
	    })
	    if ($r.FinalStatus -eq "Success") { $global:successCount++ } else { $global:failCount++ }
	    # }

	    Remove-Job $fj
	    $global:jobs = $global:jobs | Where-Object { $_.Id -ne $fj.Id }
	}

        # Stop timer if done
        if ($global:jobs.Count -eq 0 -and $global:fileQueue.Count -eq 0) {
            $global:timer.Stop()
            Write-Host "Total Success: $($global:successCount)"
            Write-Host "Total Failed : $($global:failCount)"
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
