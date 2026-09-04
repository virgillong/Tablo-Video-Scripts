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
$videoDirFilePath = Join-Path $rootDir "data\videodir.txt"
$videoDestFilePath = Join-Path $rootDir "data\videoconv.txt"
$videoQualFilePath = Join-Path $rootDir "data\videoquality.txt"
$runModeFilePath   = Join-Path $rootDir "data\runmode.txt"

if (Test-Path -Path $videoDirFilePath) { $DefaultVideoDir = (Get-Content -Path $videoDirFilePath -Raw).Trim() } else { $DefaultVideoDir = "D:\Desktop\Tablo\rec" }
if (Test-Path -Path $videoDestFilePath){ $DefaultDest     = (Get-Content -Path $videoDestFilePath -Raw).Trim() } else { $DefaultDest     = "" }
if (Test-Path -Path $videoQualFilePath){ $DefaultVideoQuality = (Get-Content -Path $videoQualFilePath -Raw).Trim() } else { $DefaultVideoQuality = "23" }
if (Test-Path -Path $runModeFilePath)  { $DefaultRunMode = (Get-Content -Path $runModeFilePath   -Raw).Trim() } else { $DefaultRunMode   = "both" }


$audioEntries = @("None", "Stereo", "Surround")

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
$form.Text = "Tablo → MP4 → MCEBuddy"
$form.Size = New-Object System.Drawing.Size(850,500)
$form.StartPosition = "CenterScreen"
Set-FormTheme -Form $form -Mode $currentMode

# --- Folder selection ---
$labelVideoDir = New-Object System.Windows.Forms.Label
$labelVideoDir.Text = "Folder containing Video Folders:"
$labelVideoDir.Location = New-Object System.Drawing.Point(10,10)
$labelVideoDir.AutoSize = $true
Set-LabelStyle -Label $labelVideoDir -Mode $currentMode
$form.Controls.Add($labelVideoDir)

$textboxVideoDir = New-Object System.Windows.Forms.TextBox
$textboxVideoDir.Location = New-Object System.Drawing.Point(200,10)
$textboxVideoDir.Size = New-Object System.Drawing.Size(420,20)
$textboxVideoDir.Text = $DefaultVideoDir
Set-TextboxStyle -Textbox $textboxVideoDir -Mode $currentMode
$form.Controls.Add($textboxVideoDir)

$browseVideoDir = New-Object System.Windows.Forms.Button
$browseVideoDir.Text = "Browse"
$browseVideoDir.Width = 80
$browseVideoDir.Left = 630
$browseVideoDir.Top = 8
$browseVideoDir.Add_Click({
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $textboxVideoDir.Text = $dlg.SelectedPath
    }
})
Set-ButtonStyle -Button $browseVideoDir -Mode $currentMode
$form.Controls.Add($browseVideoDir)

# --- Temp MP4 folder ---
$labelDest = New-Object System.Windows.Forms.Label
$labelDest.Text =  "Destination Folder:"
$labelDest.Location = New-Object System.Drawing.Point(10,50)
$labelDest.AutoSize = $true
Set-LabelStyle -Label $labelDest -Mode $currentMode
$form.Controls.Add($labelDest)

$textboxDest = New-Object System.Windows.Forms.TextBox
$textboxDest.Location = New-Object System.Drawing.Point(200,45)
$textboxDest.Size = New-Object System.Drawing.Size(420,20)
$textboxDest.Text =  $DefaultDest
Set-TextboxStyle -Textbox $textboxDest -Mode $currentMode
$form.Controls.Add($textboxDest)

$browseDestButton = New-Object System.Windows.Forms.Button
$browseDestButton.Text = "Browse"
$browseDestButton.Width = 80
$browseDestButton.Left = 630
$browseDestButton.Top = 43
$browseDestButton.Add_Click({
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $textboxDest.Text = $dlg.SelectedPath
    }
})
Set-ButtonStyle -Button $browseDestButton -Mode $currentMode
$form.Controls.Add($browseDestButton)

# Maximumconcurrent jobs Label & Textbox
$labelMaxJobs = New-Object Windows.Forms.Label
$labelMaxJobs.Text = "Maximum Concurrent Jobs"
$labelMaxJobs.AutoSize = $true
$labelMaxJobs.Left = 10
$labelMaxJobs.Top = 90
$form.Controls.Add($labelMaxJobs)
Set-LabelStyle -Label $labelMaxJobs -Mode $currentMode

$textboxMaxJobs = New-Object Windows.Forms.TextBox
$textboxMaxJobs.Width = 30
$textboxMaxJobs.Left = 200
$textboxMaxJobs.Top = 90
$textboxMaxJobs.Text = $DefaultMaxJobs
$form.Controls.Add($textboxMaxJobs)
Set-TextboxStyle -Textbox $textboxMaxJobs -Mode $currentMode

# --- Run Mode Label ---
$labelrunMode = New-Object Windows.Forms.Label
$labelrunMode.Text = "Run Mode:"
$labelrunMode.AutoSize = $true
$labelrunMode.Left = 330
$labelrunMode.Top = 90
$form.Controls.Add($labelrunMode)
Set-LabelStyle -Label $labelrunMode -Mode $currentMode

# --- Run Mode ComboBox (Display → Value Map) ---
$comboBox = New-Object System.Windows.Forms.ComboBox
$comboBox.Left = 420
$comboBox.Top = 90
$comboBox.Size = New-Object System.Drawing.Size(200,30)
$comboBox.AutoSize = $true
$form.Controls.Add($combobox)
$comboBox.DropDownStyle = 'DropDownList'

# Map friendly names to internal values
$runModeDisplayMap = @{ 
    "Re-encode Only"		    = "fallback"
    "Copy/Re-encode on failure"	    = "both"
    "Copy video files"		    = "fast" 
}

# Populate ComboBox with friendly names (convert Keys to array of strings)
$comboBox.Items.AddRange(@($runModeDisplayMap.Keys))
# Set initial selection based on stored DefaultRunMode
$comboBox.Text = ($runModeDisplayMap.Keys | Where-Object { $runModeDisplayMap[$_] -eq $DefaultRunMode })
Set-comboBoxStyle -comboBox $comboBox -Mode $currentMode


# Seperator
$label = New-Object System.Windows.Forms.Label
$label.Text = "_________________________________________________ Values used for encoding __________________________________________________"
# $label.Size = New-Object System.Drawing.Size(850,30)
$label.AutoSize = $true
$label.Left = 70
$label.Top = 140
$form.Controls.Add($label)
Set-LabelStyle -Label $label -Mode $currentMode


# Video Quality Label & Textbox
$labelVidQual = New-Object System.Windows.Forms.Label
$labelVidQual.Text = "Video Quality (CRF, 15-30):"
$labelVidQual.AutoSize = $true
$labelVidQual.Left = 10
$labelVidQual.Top = 180
$form.Controls.Add($labelVidQual)
Set-LabelStyle -Label $labelVidQual -Mode $currentMode

$textboxVidQual = New-Object Windows.Forms.TextBox
$textboxVidQual.Width = 30
$textboxVidQual.Left = 200
$textboxVidQual.Top = 180
$textboxVidQual.Text = $DefaultVideoQuality
$form.Controls.Add($textboxVidQual)
Set-TextboxStyle -Textbox $textboxVidQual -Mode $currentMode

$labelProfile = New-Object System.Windows.Forms.Label
$labelProfile.Text = "Video Profile"
$labelProfile.AutoSize = $true
$labelProfile.Left = 330
$labelProfile.Top = 180
$form.Controls.Add($labelProfile)
Set-LabelStyle -Label $labelProfile -Mode $currentMode

$comboProfile = New-Object System.Windows.Forms.ComboBox
$comboProfile.Left = 420
$comboProfile.Top = 180
$comboProfile.Size     = New-Object System.Drawing.Size(200, 30)
$comboProfile.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
$profiles.Keys | ForEach-Object { $comboProfile.Items.Add($_)| Out-Null }
# $comboProfile.SelectedIndex = 0  # Default selection
$comboProfile.SelectedItem = $defaultProfileName
$form.Controls.Add($comboProfile)
Set-comboBoxStyle -comboBox $comboProfile -Mode $currentMode


# Label audio override
$labelAudio = New-Object System.Windows.Forms.Label
$labelAudio.Text = "Audio Override:"
$labelAudio.AutoSize = $true
$labelAudio.Left = 330
$labelAudio.Top = 210
$form.Controls.Add($labelAudio)
Set-LabelStyle -Label $labelAudio -Mode $currentMode

# ComboBox audio override
$comboBoxAudio = New-Object System.Windows.Forms.ComboBox
$comboBoxAudio.Location = New-Object System.Drawing.Point(420,210)
$comboBoxAudio.Size = New-Object System.Drawing.Size(200,30)
$comboBoxAudio.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
$audioOverride.Keys | ForEach-Object { $comboBoxAudio.Items.Add($_)| Out-Null }
# $comboBoxAudio.DropDownStyle = 'DropDownList'
# $comboBoxAudio.Items.AddRange($audioEntries)
$comboBoxAudio.SelectedItem = $defaultAudioName
Set-comboBoxStyle -comboBox $comboBoxAudio -Mode $currentMode
$form.Controls.Add($comboBoxAudio)

# --- Start button ---
$btnStart = New-Object System.Windows.Forms.Button
$btnStart.Text = "Start Processing"
$btnStart.Location = New-Object System.Drawing.Point(10,240)
$btnStart.Size = New-Object System.Drawing.Size(150,30)
Set-ButtonStyle -Button $btnStart -Mode $currentMode
$form.Controls.Add($btnStart)


# --- ListView for job status ---
$listView = New-Object System.Windows.Forms.ListView
$listView.Location = New-Object System.Drawing.Point(10,300)
$listView.Size = New-Object System.Drawing.Size(850,320)
$listView.View = 'Details'
$listView.FullRowSelect = $true
$listView.GridLines = $true
[void]$listView.Columns.Add("Folder",200)
[void]$listView.Columns.Add("Destination MP4",320)
[void]$listView.Columns.Add("Copy Status",90)
[void]$listView.Columns.Add("Encode Status",90)
[void]$listView.Columns.Add("Final Status",90)
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
    $global:runMode         = $runModeDisplayMap[$comboBox.Text]


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
    Set-Content -Path $runModeFilePath -Value $global:runMode

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
    foreach ($folder in $videoFolders) {
        $global:folderQueue.Enqueue($folder)
    }

    # --- Start timer for throttled job processing ---
    $global:timer = New-Object System.Windows.Forms.Timer
    $global:timer.Interval = 1000

# ----------------------
#  Time Event 
# ----------------------

    $global:timer.Add_Tick({

        # Write-Host "Queue=$($global:folderQueue.Count), Jobs=$($global:jobs.Count), MaxJobs=$($global:maxConcurrentJobs)"
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
			$item.SubItems[3].Text = $r.FallbackStatus
			$item.SubItems[4].Text = $r.FinalStatus
		    }
		})
	    }
}


        # Start jobs if slots available
        while (($global:jobs | Where-Object { $_.State -in 'Running','NotStarted' }).Count -lt $global:maxConcurrentJobs -and
               $global:folderQueue.Count -gt 0) {

	    $folder     = $global:folderQueue.Dequeue()
            $folderName = $folder.Name
            $folderPath = $folder.FullName
            $segsPath   = Join-Path $folderPath "segs"
            $outputFile = Join-Path $global:destination "$folderName.mp4"
            $logFile    = Join-Path $global:logDir "$folderName.log"

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
	    if (Test-Path $outputFile) { continue }


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
			$ffmpegPath,
			$profiles,
			$selectedProfile,
			$audioOverride,
			$selectedAudio
		)

		# "DEBUG: Encoders -> Video=$videoEncoder, Audio=$audioEncoder, Bitrate=${audioBitrate}k, CRF=$videoQuality" |
		# Out-File -FilePath $logFile -Append
		
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
		  

		 # ----------------------
		    # Fast mode = ffmpeg copy
		    # -------------------
		if ($runMode -in @("both","fast")) {

		    Write-Output ([PSCustomObject]@{
			Folder         = $folderName
			FastStatus     = "Running..."
			FallbackStatus = $fallbackStatus
			FinalStatus    = $status
		    })


		    try {
			# --- FAST CONCAT ---
			    $ffmpegOutput = & $ffmpegPath @ffmpegArgsConcatCopy 2>&1
			    $ffmpegOutput | Out-File -FilePath $logFile -Encoding UTF8 -Append	    
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

		try {

		    $ffmpegOutput = & $ffmpegPath @ffmpegArgsConcatEnc 2>&1
		    $ffmpegOutput | Out-File -FilePath $logFile -Encoding UTF8 -Append

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
			    $ffmpegPath,
			    $global:profiles,
			    $global:selectedProfile,
			    $global:audioOverride,
			    $global:selectedAudio

	} # end of while jobs loop

 



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
        }

    })

    $global:timer.Start()


}) # End $btnStart


# Use last control to determine needed height
$bottomMostButton = $listView
$neededHeight = $bottomMostButton.Bottom + 50
$form.Height = $neededHeight

# --- Show the form ---
[System.Windows.Forms.Application]::Run($form)
# [System.Windows.Forms.Application]::EnableVisualStyles()
