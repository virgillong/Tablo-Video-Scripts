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
        \
    }
}

$themeFile = Join-Path $rootDir "data\theme.txt"
$currentMode = Import-ThemeState -themeFile $themeFile
$DefaultMaxJobs = "2"
$DefaultSize = "400MB"
$defaultProfileName =  "High Compression (x265)"
$defaultAudioName =  "Surround Sound ac3"
$videoDirFilePath = Join-Path $rootDir "data\Videos2Merge.txt"
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

$labelLeft = 10
$labelLeft2 = 350
$textLeft = 200
$buttonwidth = 150
$buttonHght = 30
$formHght = 500
$formWidth = 900

# --- Form ---
$form = New-Object System.Windows.Forms.Form
$form.Font = $global:FontRegular
$form.Text = "Join video files ts → mp4  ffmpeg"
$form.Size = New-Object System.Drawing.Size(900,500)
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
$textboxDest.Location = New-Object System.Drawing.Point($textLeft,$top)
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

# --- Run Mode Label ---
$labelrunMode = New-Object Windows.Forms.Label
$labelrunMode.Text = "Run Mode=Concat+:"
$labelrunMode.AutoSize = $true
$labelrunMode.Left = $labelLeft2-75
$labelrunMode.Top = $top
$form.Controls.Add($labelrunMode)
Set-LabelStyle -Label $labelrunMode -Mode $currentMode

# --- Run Mode ComboBox (Display → Value Map) ---
$comboBox = New-Object System.Windows.Forms.ComboBox
$comboBox.Left = $labelLeft2 + 110
$comboBox.Top = $top
$comboBox.Size = New-Object System.Drawing.Size(300,30)
$form.Controls.Add($combobox)
$comboBox.DropDownStyle = 'DropDownList'

# Map friendly names to internal values
$runModeDisplayMap = @{ 
    "Re-encode Only"		    = "fallback"
    "Remux/Re-encode on failure"    = "both"
    "Remux Only"		    = "fast" 
}

# Populate ComboBox with friendly names (convert Keys to array of strings)
$comboBox.Items.AddRange(@($runModeDisplayMap.Keys))
# Set initial selection based on stored DefaultRunMode
$comboBox.Text = ($runModeDisplayMap.Keys | Where-Object { $runModeDisplayMap[$_] -eq $DefaultRunMode })
Set-comboBoxStyle -comboBox $comboBox -Mode $currentMode

$top = (3*$spacing-10) + $topstrt

# Seperator
$label = New-Object System.Windows.Forms.Label
$label.Text = "Encoding Parameters  _______________________________________________________________________________"
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
$btnStart.Height = $buttonHght
$btnStart.Width = $buttonwidth + 30
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
    # clear the list view
    $listView.Items.Clear()

    # --- Read inputs directly from GUI ---
    $videoDir        = $textboxVideoDir.Text.Trim()
    $global:destination = $textboxDest.Text.Trim()
    $global:videoQuality    = $textboxVidQual.Text.Trim()
    $global:maxConcurrentJobs = [int]$textboxMaxJobs.Text
    $global:runMode         = $runModeDisplayMap[$comboBox.Text]

    # Get Encoding Profile delected
    $global:selectedVideoProfile = $comboProfile.SelectedItem
    $global:VideoProfiles = $profiles[$selectedVideoProfile]

    # Get audio override selected
    $global:selectedAudioProfile = $comboBoxAudio.SelectedItem
    $global:audioProfiles =$audioOverride[$selectedAudioProfile]

    # try {
    #	$global:minFileSizeBytes = Convert-ToBytes $textboxMinSize.Text
    # } catch {
    #	Write-Host "Error: $_"
    #	return
    # }

    Write-Host "Using Profile: $global:selectedProfile"
    Write-Host "Video: $($global:VideoProfiles.VideoEncoder), Audio: $($global:VideoProfiles.AudioEncoder) @ $($global:VideoProfiles.AudioBitrate) kbps"
    Write-Host "Audio Override: $global:selectedAudioProfile "
    Write-Host "Audio Encoder: $($global:selectedAudioProfile.audioEncoder), Audio Channels: $($global:selectedAudioProfile.audioChannels), $($global:selectedAudioProfile.audioBitrate) kbps"
    Write-Host "Min File Size: $global:minFileSizeBytes bytes"

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

	  Write-Host "im in the for each before the while loop"
        # Start jobs if slots available
        while (($global:jobs | Where-Object { $_.State -in 'Running','NotStarted' }).Count -lt $global:maxConcurrentJobs -and
               $global:folderQueue.Count -gt 0) {

	       Write-Host "im in the while loop"

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
		    $videoProfiles,
		    $selectedVideoProfile,
		    $audioProfiles,
		    $selectedAudioProfile,
		     $rootDir
		)
		"DEBUG: Encoders -> IM IN THE JOB" |
		    Out-File -FilePath $logFile -Append
		
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
		$videoEncoder  = $videoProfiles.VideoEncoder
		$audioEncoder  = $videoProfiles.AudioEncoder
		$audioBitrate  = $videoProfiles.AudioBitrate

		# see if audio override parameters  video parameters were selected for ffmpeg encode
		$audioChannels = ""

		if ($selectedAudioProfile -ne "None") {
		    $audioEncoder  = $audioProfiles.audioEncoder
		    $audioChannels = $audioProfiles.audioChannels
		    $audioBitrate  = $audioProfiles.audioBitrate
		}

		"DEBUG: Encoders -> Video=$videoEncoder, Audio=$audioEncoder, Bitrate=${audioBitrate}k, CRF=$videoQuality" |
		    Out-File -FilePath $logFile -Append
		
		$FFmpegFunctions = Join-Path $rootDir "etc\FFmpegFunctions.ps1"
		. $FFmpegFunctions


		#
		# Profile  = "Copy"	    $Source   = $inputPath
		# Profile  = "Encode"	    $Source   = $inputPath
		# Profile  = "ConcatCopy    $Source  = $myListPath
		# Profile  = "ConcatEncode" $Source   = $myListPath
		#

		$Source   = $myListPath

		$args = Get-FFmpegArguments `
		    -RootDir $rootDir `
		    -Profile "ConcatCopy" `
		    -InputPath $Source `
		    -OutputPath $outputFile `
		    -VideoEncoder $videoEncoder `
		    -VideoQuality $videoQuality `
		    -AudioEncoder $audioEncoder `
		    -AudioBitrate $audioBitrate

		

		

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

		    switch ($encoder) {
			"Handbrake" {
			    $encoderPath = "C:\Program Files\HandBrake\HandBrakeCLI.exe" 
			}
			"FFmpeg" {
			    $encoderPath = "C:\ffmpeg\bin\ffmpeg.exe" 
			}
		    }		 
		    if (-not (Test-Path $encoderPath)) {
			return
		    }

		    "DEBUG: Encoders -> args=$args, encoderpath=$encoderPath " |
		    Out-File -FilePath $logFile -Append
		  
		    try {
			# --- FAST CONCAT ---
			    # $ffmpegOutput = & $ffmpegPath @ffmpegArgsConcatCopy 2>&1
			     $ffmpegOutput = & $encoderPath @args 2>&1 
			    $ffmpegOutput = & $ffmpegPath @args 2>&1
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

		$args = Get-FFmpegArguments `
		    -RootDir $rootDir `
		    -Profile "ConcatEncode" `
		    -InputPath $Source `
		    -OutputPath $outputFile `
		    -VideoEncoder $videoEncoder `
		    -VideoQuality $videoQuality `
		    -AudioEncoder $audioEncoder `
		    -AudioBitrate $audioBitrate

		try {
		    # $ffmpegOutput = & $ffmpegPath @ffmpegArgsConcatEnc 2>&1
		     $ffmpegOutput = & $ffmpegPath @args 2>&1
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
			    $ffmpegPath,

			    $global:videoProfiles,
			    $global:selectedVideoProfile,
			    $global:audioProfiles,
			    $global:selectedAudioProfile,
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
