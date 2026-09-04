Add-Type -AssemblyName 'System.Windows.Forms'
Add-Type -AssemblyName 'System.Drawing'
Import-Module ThreadJob

# Default path fallback for rootDir
if (-not $env:rootDir) {
    $env:rootDir = (Resolve-Path "$PSScriptRoot\..").Path
}
$rootDir = $env:rootDir 


Import-Module (Join-Path $rootDir "etc\includes\UIHelpers.psm1") -Force

$themeFile = Join-Path $rootDir "data\theme.txt"
$currentMode = Import-ThemeState -themeFile $themeFile
$DefaultMaxJobs = "2"
$defaultProfileName =  "High Compression (x265)"
$defaultAudioName =  "Surround Sound ac3"

$videoDirFilePath = Join-Path $rootDir "data\videoconv.txt"
$videoDestFilePath = Join-Path $rootDir "data\videodest.txt"
$videoQualFilePath = Join-Path $rootDir "data\videoquality.txt"
$runModeFilePath   = Join-Path $rootDir "data\runmode.txt"

if (Test-Path -Path $videoDirFilePath) { $DefaultVideoDir = (Get-Content -Path $videoDirFilePath -Raw).Trim() } else { $DefaultVideoDir = "" }
if (Test-Path -Path $videoDestFilePath){ $DefaultDest     = (Get-Content -Path $videoDestFilePath -Raw).Trim() } else { $DefaultDest     = "" }
if (Test-Path -Path $videoQualFilePath){ $DefaultVideoQuality = (Get-Content -Path $videoQualFilePath -Raw).Trim() } else { $DefaultVideoQuality = "23" }


# Preset encoding profiles

# --- Encoding Variables ---
$profiles = @{
    "Fast + Compatible" = @{
        VideoEncoder = "libx264"
        AudioEncoder = "aac"
        AudioBitrate = 128
    }
    "High Compression (x265)" = @{
        VideoEncoder = "libx265"
        AudioEncoder = "aac"
        AudioBitrate = 128
    }
    "Music Quality" = @{
        VideoEncoder = "libx264"
        AudioEncoder = "aac"
        AudioBitrate = 256
    }
    "Voice / Low Bandwidth" = @{
        VideoEncoder = "libx264"
        AudioEncoder = "libopus"
        AudioBitrate = 64
    }
    "Future-Proof (AV1)" = @{
        VideoEncoder = "libaom-av1"
        AudioEncoder = "libopus"
        AudioBitrate = 128
    }
    "GPU Accelerated (NVIDIA H.264)" = @{
        VideoEncoder = "h264_nvenc"
        AudioEncoder = "aac"
        AudioBitrate = 128
    }
}


$audioOverride = @{
    
    "Stereo aac" = @{	
	audioEncoder  = "aac"
	audioChannels = "2"
	audioBitrate  = 128
    }
    "None" = @{}
    "Surround Sound ac3" = @{
	audioEncoder  = "ac3"
	audioChannels = ""
	audioBitrate  = 448
    }
}



# --- Form ---
$form = New-Object System.Windows.Forms.Form
$form.Text = "Re-encode mp4 → mp4 ffmpeg"
$form.Size = New-Object System.Drawing.Size(900,500)
$form.StartPosition = "CenterScreen"
Set-FormTheme -Form $form -Mode $currentMode

$topStrt = 20
$spacing = 40
$top = $topstrt

# --- Folder selection ---
$labelVideoDir = New-Object System.Windows.Forms.Label
$labelVideoDir.Text = "Videos folder:"
$labelVideoDir.Location = New-Object System.Drawing.Point(10,$top)
$labelVideoDir.AutoSize = $true
Set-LabelStyle -Label $labelVideoDir -Mode $currentMode
$form.Controls.Add($labelVideoDir)

$textboxVideoDir = New-Object System.Windows.Forms.TextBox
$textboxVideoDir.Location = New-Object System.Drawing.Point(200,$top)
$textboxVideoDir.Size = New-Object System.Drawing.Size(420,20)
$textboxVideoDir.Text = $DefaultVideoDir
Set-TextboxStyle -Textbox $textboxVideoDir -Mode $currentMode
$form.Controls.Add($textboxVideoDir)

$browseVideoDir = New-Object System.Windows.Forms.Button
$browseVideoDir.Text = "Browse"
$browseVideoDir.Width = 80
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
$labelDest.Location = New-Object System.Drawing.Point(10,$top)
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
$browseDestButton.Width = 80
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
$labelMaxJobs.Text = "Maximum Concurrent Jobs"
$labelMaxJobs.AutoSize = $true
$labelMaxJobs.Left = 10
$labelMaxJobs.Top = $top
$form.Controls.Add($labelMaxJobs)
Set-LabelStyle -Label $labelMaxJobs -Mode $currentMode

$textboxMaxJobs = New-Object Windows.Forms.TextBox
$textboxMaxJobs.Width = 30
$textboxMaxJobs.Left = 200
$textboxMaxJobs.Top = $top
$textboxMaxJobs.Text = $DefaultMaxJobs
$form.Controls.Add($textboxMaxJobs)
Set-TextboxStyle -Textbox $textboxMaxJobs -Mode $currentMode

$top = (3*$spacing-10) + $topstrt

# Seperator
$label = New-Object System.Windows.Forms.Label
$label.Text = "Encoding Parameters  _____________________________________________________________________________________________________________"
# $label.Size = New-Object System.Drawing.Size(850,30)
$label.AutoSize = $true
$label.Left = 10
$label.Top = $top
$form.Controls.Add($label)
Set-LabelStyle -Label $label -Mode $currentMode

$top = (4*$spacing-10) + $topstrt

# Video Quality Label & Textbox
$labelVidQual = New-Object System.Windows.Forms.Label
$labelVidQual.Text = "Video Quality (CRF, 15-30):"
$labelVidQual.AutoSize = $true
$labelVidQual.Left = 10
$labelVidQual.Top = $top
$form.Controls.Add($labelVidQual)
Set-LabelStyle -Label $labelVidQual -Mode $currentMode

$textboxVidQual = New-Object Windows.Forms.TextBox
$textboxVidQual.Width = 30
$textboxVidQual.Left = 200
$textboxVidQual.Top = $top
$textboxVidQual.Text = $DefaultVideoQuality
$form.Controls.Add($textboxVidQual)
Set-TextboxStyle -Textbox $textboxVidQual -Mode $currentMode

$labelProfile = New-Object System.Windows.Forms.Label
$labelProfile.Text = "Video Profile"
$labelProfile.AutoSize = $true
$labelProfile.Left = 330
$labelProfile.Top = $top
$form.Controls.Add($labelProfile)
Set-LabelStyle -Label $labelProfile -Mode $currentMode

$comboProfile = New-Object System.Windows.Forms.ComboBox
$comboProfile.Left = 420
$comboProfile.Top = $top
$comboProfile.Size     = New-Object System.Drawing.Size(200, 30)
$comboProfile.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
$profiles.Keys | ForEach-Object { $comboProfile.Items.Add($_)| Out-Null }
# $comboProfile.SelectedIndex = 0  # Default selection
$comboProfile.SelectedItem = $defaultProfileName
$form.Controls.Add($comboProfile)
Set-comboBoxStyle -comboBox $comboProfile -Mode $currentMode

$top = (5*$spacing-20) + $topstrt

# Label audio override
$labelAudio = New-Object System.Windows.Forms.Label
$labelAudio.Text = "Audio Override"
$labelAudio.AutoSize = $true
$labelAudio.Left = 310
$labelAudio.Top = $top
$form.Controls.Add($labelAudio)
Set-LabelStyle -Label $labelAudio -Mode $currentMode

# ComboBox audio override
$comboBoxAudio = New-Object System.Windows.Forms.ComboBox
$comboBoxAudio.Location = New-Object System.Drawing.Point(420,$top)
$comboBoxAudio.Size = New-Object System.Drawing.Size(200,30)
$comboBoxAudio.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
$audioOverride.Keys | ForEach-Object { $comboBoxAudio.Items.Add($_)| Out-Null }
# $comboBoxAudio.DropDownStyle = 'DropDownList'
# $comboBoxAudio.Items.AddRange($audioEntries)
$comboBoxAudio.SelectedItem = $defaultAudioName
Set-comboBoxStyle -comboBox $comboBoxAudio -Mode $currentMode
$form.Controls.Add($comboBoxAudio)

$top = (6*$spacing-10) + $topstrt

# --- Start button ---
$btnStart = New-Object System.Windows.Forms.Button
$btnStart.Text = "Start Processing"
$btnStart.Location = New-Object System.Drawing.Point(10,$top)
$btnStart.Size = New-Object System.Drawing.Size(150,30)
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

    # --- Read inputs directly from GUI ---
    $videoDir        = $textboxVideoDir.Text.Trim()
    $global:destination = $textboxDest.Text.Trim()
    $global:videoQuality    = $textboxVidQual.Text.Trim()
    $global:maxConcurrentJobs = [int]$textboxMaxJobs.Text

     # Get Encoding Profile delected
    $global:selectedProfile = $comboProfile.SelectedItem
    $global:profile = $profiles[$selectedProfile]
    Write-Host "Using Profile: $selectedProfile"
    Write-Host "Video: $($global:profile.VideoEncoder), Audio: $($global:profile.AudioEncoder) @ $($global:profile.AudioBitrate) kbps"

    # Get audio override selected
    $global:selectedAudio = $comboBoxAudio.SelectedItem
    $global:audiosel =$audioOverride[$selectedAudio]
    Write-Host "Audio Override: $selectedAudio"
    Write-Host "Audio Encoder: $($global:audiosel.audioEncoder), Audio Channels: $($global:audiosel.audioChannels), $($global:audiosel.audioBitrate) kbps"

    # --- Validation ---
    if ([string]::IsNullOrWhiteSpace($videoDir) -or -not (Test-Path $videoDir)) {
        [System.Windows.Forms.MessageBox]::Show(
            "Please select a valid video directory.",
            "Invalid Video Directory",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        )
        $form.DialogResult = [System.Windows.Forms.DialogResult]::None
        return
    }

    if ([string]::IsNullOrWhiteSpace($global:destination)) {
        [System.Windows.Forms.MessageBox]::Show(
            "Please enter a valid destination directory.",
            "Invalid Destination Directory",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        )
        $form.DialogResult = [System.Windows.Forms.DialogResult]::None
        return
    }

    if (-not (Test-Path $global:destination)) {
        try {
            New-Item -ItemType Directory -Path $global:destination -Force | Out-Null
        }
        catch {
            [System.Windows.Forms.MessageBox]::Show(
                "Could not create destination folder:`n$global:destination",
                "Folder Creation Failed",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            )
            $form.DialogResult = [System.Windows.Forms.DialogResult]::None
            return
        }
    }

    if (-not [int]::TryParse($global:videoQuality, [ref]$null) -or
        [int]$global:videoQuality -lt 15 -or [int]$global:videoQuality -gt 30) {
        [System.Windows.Forms.MessageBox]::Show(
            "Please enter a valid Video Quality (CRF) number between 15 and 30.",
            "Invalid Input",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
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


        # Start jobs if slots available
        while (($global:jobs | Where-Object { $_.State -in 'Running','NotStarted' }).Count -lt $global:maxConcurrentJobs -and
               $global:fileQueue.Count -gt 0) {

            $vidfile    = $global:fileQueue.Dequeue()
	    $vidfilename = $vidfile.Name
	    $vidfilePath = $vidfile.FullName

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
		    $profiles,
		    $selectedProfile,
		    $audioOverride,
		    $selectedAudio
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
		# $videoEncoder  = "libx265"
		# $audioEncoder  = "aac"
		# $audioBitrate  = 128

		
		# get video parameters selected by user for ffmpeg encode
		$profile = $profiles[$selectedProfile]
		$videoEncoder  = $profile.VideoEncoder
		$audioEncoder  = $profile.AudioEncoder
		$audioBitrate  = $profile.AudioBitrate

		# see if audio override parameters  video parameters were selected for ffmpeg encode
		$audioChannels = ""
		$audio = $audioOverride[$selectedAudio]

		if ($audio -ne "None") {
		    $audioEncoder  = $audio.audioEncoder
		    $audioChannels = $audio.audioChannels
		    $audioBitrate  = $audio.audioBitrate
		}

		 $ffmpegArgsEncode = @(
		    "-loglevel","error",
		    "-hide_banner", "-y",
		    "-i", $inputPath,
		    "-fflags","+genpts","-reset_timestamps","1",
		    "-c:v",$videoEncoder,
		    "-crf",$videoQuality,
		    "-c:a",$audioEncoder,
		    "-b:a","${audioBitrate}k",
		    $outputFile
		)


		$ffmpegArgsConcatCopy = @(
		    "-loglevel","error",
		    "-hide_banner","-y",
		    "-f","concat","-safe","0",
		    "-i",$mylistPath,
		    "-c","copy",
		    $outputFile
		)

		$ffmpegArgsConcatEnc = @(
		    "-loglevel","error",
		    "-hide_banner","-y",
		    "-f","concat","-safe","0",
		    "-i",$mylistPath,
		    "-fflags","+genpts","-reset_timestamps","1",
		    "-c:v",$videoEncoder,
		    "-crf",$videoQuality,
		    "-c:a",$audioEncoder
		    "-b:a","${audioBitrate}k"
		)
		if ($null -ne $audioChannels) {
		    $ffmpegArgsConcatEnc += @("-ac", $audioChannels)
		}
		$ffmpegArgsConcatEnc += $outputFile

		"DEBUG: Encoders -> Video=$videoEncoder, Audio=$audioEncoder, Bitrate=${audioBitrate}k, CRF=$videoQuality" |
		    Out-File -FilePath $logFile -Append
		  
		  

		Write-Output ([PSCustomObject]@{
		    Folder        = $vidfilename
		    FastStatus    = "Running..."
		    FinalStatus   = "—"
		})

		try {
		    # -- ffmpeg Encode ---
		    $fastStatus = "Running..."

		    $ffmpegOutput = & $ffmpegPath $ffmpegArgsEncode 2>&1
		    $ffmpegOutput | Out-File -FilePath $logFile -Encoding UTF8 -Append

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
			    $global:profiles,
			    $global:selectedProfile,
			    $global:audioOverride,
			    $global:selectedAudio

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

    }) #end of timer event handler

    $global:timer.Start()


}) # End $btnStart


# Use last control to determine needed height
$bottomMostButton = $listView
$neededHeight = $bottomMostButton.Bottom + 50
$form.Height = $neededHeight

# --- Show the form ---
[System.Windows.Forms.Application]::Run($form)
# [System.Windows.Forms.Application]::EnableVisualStyles()
