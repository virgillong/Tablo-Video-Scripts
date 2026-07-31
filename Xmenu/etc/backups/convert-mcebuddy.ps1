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

# Default path fallback for rootDir
if (-not $env:rootDir) {
    $env:rootDir = (Resolve-Path "$PSScriptRoot\..").Path
}
$rootDir = $env:rootDir 

Import-Module ThreadJob
Import-Module (Join-Path $rootDir "etc\includes\UIHelpers.psm1") -Force

# Optional: warn if not STA (WinForms prefers STA)
try {
    if ([System.Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {
        Write-Warning "This script runs best in STA mode (e.g., 'powershell.exe -STA')."
    }
} catch {}



# ... file paths ---
$videoDirFilePath = Join-Path $rootDir "data\videodir.txt"
$videoDestFilePath = Join-Path $rootDir "data\videoconv.txt"
$videoQualFilePath = Join-Path $rootDir "data\videoquality.txt"
$themeFile = Join-Path $rootDir "data\theme.txt"
$mcebuddyCLI = "C:\Program Files\MCEBuddy2x\MCEBuddy.UserCLI.exe"
$tempMp4Dir  = "\\hpdesktop\videos\Videos\mcebuddy_temp"

$currentMode = Import-ThemeState -themeFile $themeFile
$DefaultmaxConcurrentTemps = 2   # max number of temporary files allowed
$defaultProfileName =  "High Compression (x265)"

$audioEntries = @("None", "Stereo", "Surround")
$defaultAudioName =  "Surround Sound ac3"

# manage temporary files waiting for mcebuddy processing
$global:tempFilesWaiting = 0
$global:maxTempFilesWaiting = 3 

if (Test-Path -Path $videoDirFilePath) { $DefaultVideoDir = (Get-Content -Path $videoDirFilePath -Raw).Trim() } else { $DefaultVideoDir = "D:\Desktop\Tablo\rec" }
if (Test-Path -Path $videoDestFilePath){ $DefaultDest     = (Get-Content -Path $videoDestFilePath -Raw).Trim() } else { $DefaultDest     = "" }
if (Test-Path -Path $videoQualFilePath){ $DefaultVideoQuality = (Get-Content -Path $videoQualFilePath -Raw).Trim() } else { $DefaultVideoQuality = "23" }

# Ensure temp folder exists (UNC ok)
if (-not (Test-Path $tempMp4Dir)) {
    New-Item -Path $tempMp4Dir -ItemType Directory | Out-Null
}


# Check for ffmpeg in PATH
if (-not (Get-Command ffmpeg -ErrorAction SilentlyContinue)) {
    [System.Windows.Forms.MessageBox]::Show("FFmpeg not found. Ensure it is in your PATH.", "Error", "OK", "Error")
    return
}


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


#-------------------
# --- Form ---
#--------------------
$form = New-Object System.Windows.Forms.Form
$form.Text = "Tablo → MP4 → MCEBuddy"
$form.Size = New-Object System.Drawing.Size(850,500)
$form.StartPosition = "CenterScreen"
Set-FormTheme -Form $form -Mode $currentMode

# --- Folder selection ---
$labelVideoDir = New-Object System.Windows.Forms.Label
$labelVideoDir.Text = "Recorded Folders:"
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
$labelTemp = New-Object System.Windows.Forms.Label
$labelTemp.Text = "Temp MP4 Folder:"
$labelTemp.Location = New-Object System.Drawing.Point(10,50)
$labelTemp.AutoSize = $true
Set-LabelStyle -Label $labelTemp -Mode $currentMode
$form.Controls.Add($labelTemp)

$textboxTemp = New-Object System.Windows.Forms.TextBox
$textboxTemp.Location = New-Object System.Drawing.Point(200,45)
$textboxTemp.Size = New-Object System.Drawing.Size(420,20)
$textboxTemp.Text = $DefaultDest
Set-TextboxStyle -Textbox $textboxTemp -Mode $currentMode
$form.Controls.Add($textboxTemp)

$browseTemp = New-Object System.Windows.Forms.Button
$browseTemp.Text = "Browse"
$browseTemp.Width = 80
$browseTemp.Left = 630
$browseTemp.Top = 43
$browseTemp.Add_Click({
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $textboxTemp.Text = $dlg.SelectedPath
    }
})
Set-ButtonStyle -Button $browseTemp -Mode $currentMode
$form.Controls.Add($browseTemp)

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
$textboxMaxJobs.Text = $DefaultmaxConcurrentTemps
$form.Controls.Add($textboxMaxJobs)
Set-TextboxStyle -Textbox $textboxMaxJobs -Mode $currentMode

# Seperator
$label = New-Object System.Windows.Forms.Label
$label.Text = "_________________________________________________ Values used for encoding __________________________________________________"
# $label.Size = New-Object System.Drawing.Size(850,30)
$label.AutoSize = $true
$label.Left = 100
$label.Top = 120
$form.Controls.Add($label)
Set-LabelStyle -Label $label -Mode $currentMode


# Video Quality Label & Textbox
$labelVidQual = New-Object System.Windows.Forms.Label
$labelVidQual.Text = "Video Quality (CRF, 15-30):"
$labelVidQual.AutoSize = $true
$labelVidQual.Left = 10
$labelVidQual.Top = 150
$form.Controls.Add($labelVidQual)
Set-LabelStyle -Label $labelVidQual -Mode $currentMode

$textboxVidQual = New-Object Windows.Forms.TextBox
$textboxVidQual.Width = 30
$textboxVidQual.Left = 200
$textboxVidQual.Top = 150
$textboxVidQual.Text = $DefaultVideoQuality
$form.Controls.Add($textboxVidQual)
Set-TextboxStyle -Textbox $textboxVidQual -Mode $currentMode

$labelProfile = New-Object System.Windows.Forms.Label
$labelProfile.Text = "Video Profile"
$labelProfile.AutoSize = $true
$labelProfile.Left = 330
$labelProfile.Top = 150
$form.Controls.Add($labelProfile)
Set-LabelStyle -Label $labelProfile -Mode $currentMode

$comboProfile = New-Object System.Windows.Forms.ComboBox
$comboProfile.Left = 420
$comboProfile.Top = 150
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
$labelAudio.Top = 180
$form.Controls.Add($labelAudio)
Set-LabelStyle -Label $labelAudio -Mode $currentMode

# ComboBox audio override
$comboBoxAudio = New-Object System.Windows.Forms.ComboBox
$comboBoxAudio.Location = New-Object System.Drawing.Point(420,180)
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
$btnStart.Location = New-Object System.Drawing.Point(10,190)
$btnStart.Size = New-Object System.Drawing.Size(150,30)
Set-ButtonStyle -Button $btnStart -Mode $currentMode
$form.Controls.Add($btnStart)

# --- ListView for job status ---
$listView = New-Object System.Windows.Forms.ListView
$listView.Location = New-Object System.Drawing.Point(10,230)
$listView.Size = New-Object System.Drawing.Size(850,320)
$listView.View = 'Details'
$listView.FullRowSelect = $true
$listView.GridLines = $true
[void]$listView.Columns.Add("Folder",200)
[void]$listView.Columns.Add("Destination MP4",320)
[void]$listView.Columns.Add("Copy Status",90)
[void]$listView.Columns.Add("Encode Status",90)
[void]$listView.Columns.Add("MCEBuddy Status",90)
[void]$listView.Columns.Add("Counter",120) 
Set-ListViewStyle -ListView $listView -Mode $currentMode
$form.Controls.Add($listView)

#----------------------------------
# --- Start button handler ---
#----------------------------------
$btnStart.Add_Click({
    $videoDir   = $textboxVideoDir.Text.Trim()
    $tempMp4UI  = $textboxTemp.Text.Trim()
    $videoQuality    = $textboxVidQual.Text.Trim()
    $global:maxConcurrentTemps = [int]$textboxMaxJobs.Text.Trim()

    # Get Encoding Profile delected
    $selectedProfile = $comboProfile.SelectedItem
    $profile = $profiles[$selectedProfile]
    Write-Host "Using Profile: $selectedProfile"
    Write-Host "Video: $($profile.VideoEncoder), Audio: $($profile.AudioEncoder) @ $($profile.AudioBitrate) kbps"
    
    # Get audio override selected
    $selectedAudio = $comboBoxAudio.SelectedItem
    $audiosel =$audioOverride[$selectedAudio]
    Write-Host "Audio Override: $selectedAudio"
    Write-Host "Audio Encoder: $($audiosel.audioEncoder), Audio Channels: $($audiosel.audioChannels), $($audiosel.audioBitrate) kbps"



    if (-not (Test-Path $tempMp4UI)) {
        try { New-Item -Path $tempMp4UI -ItemType Directory | Out-Null } catch {}
    }

     if (-not [int]::TryParse($videoQuality, [ref]$null) -or
        [int]$videoQuality -lt 15 -or [int]$videoQuality -gt 30) {
        [System.Windows.Forms.MessageBox]::Show(
            "Please enter a valid Video Quality (CRF) number between 15 and 30.",
            "Invalid Input",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
        $form.DialogResult = [System.Windows.Forms.DialogResult]::None
        return
    }

    $ffmpegPath = "C:\ffmpeg\bin\ffmpeg.exe"
    if (-not (Test-Path $ffmpegPath)) {
	[System.Windows.Forms.MessageBox]::Show("FFmpeg not found at $ffmpegPath", "Error",
	    [System.Windows.Forms.MessageBoxButtons]::OK,
	    [System.Windows.Forms.MessageBoxIcon]::Error)
	return
    }

    # --- Prepare logs directory ---
    $global:logDir = Join-Path $PSScriptRoot "logs"
    if (-not (Test-Path $global:logDir)) {
        New-Item -ItemType Directory -Path $global:logDir | Out-Null
    }

    # Start a single background thread to process folders sequentially
    Start-ThreadJob -Name "ProcessFolders" -ScriptBlock {
        param(
            $videoDir,
            $tempMp4Dir,
            $mcebuddyCLI,
            $formRef,
            $listRef,
            [ref]$tempFilesWaitingRef,
	    $maxTempFilesWaiting,
	    $videoQuality,
	    $profiles,
	    $selectedProfile,
	    $audioOverride,
	    $selectedAudio,
	    $logDir,
	    $ffmpegPath
        )
 
        # Ensure engine is running (idempotent)
        try { & $mcebuddyCLI --command=engine --action=start | Out-Null; Start-Sleep -Seconds 2 } catch {}

        Get-ChildItem -Path $videoDir -Directory | ForEach-Object {
            $folder     = $_.FullName
            $folderName = $_.Name
            $segsDir    = Join-Path $folder "segs"
	    $logFile    = Join-Path $global:logDir "$folderName.log"

            if (-not (Test-Path $segsDir)) { return }

            $tsFiles = Get-ChildItem -Path $segsDir -Filter "*.ts" | Sort-Object Name
            if ($tsFiles.Count -eq 0) { return }

	    $mylistPath  = Join-Path $segsDir "concat.txt"
	    $outputFile = Join-Path $tempMp4Dir "$folderName.mp4"

            # Build concat file
            $tsFiles | ForEach-Object { "file '$($_.FullName)'" } | Set-Content -Path $mylistPath -Encoding ASCII

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
		"-f","concat",
		"-safe","0",
		"-i",$mylistPath,
		"-c","copy",
		$outputFile
	    )

	    $ffmpegArgsConcatEnc = @(
		"-loglevel","error",
		"-hide_banner","-y",
		"-f","concat",
		"-safe","0",
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
	    
	    #------------------------------------------------
	    # FFmpeg COPY 
            # capture all output (stdout + stderr) in order
	    # Waits automatically, since this is synchronous
	    #-------------------------------------------------

	    $ffmpegOutput = & $ffmpegPath @ffmpegArgsConcatCopy 2>&1
	    # $ffmpeg = Start-Process -FilePath ffmpeg -ArgumentList $ffmpegArgs -NoNewWindow -Wait -PassThru 2>&1
	    $exitCode = $LASTEXITCODE
	    # this code allows for log files to be produced
	    $ffmpegOutput | Out-File -FilePath $logFile -Encoding UTF8 -Append	    
	 
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
	    # ffmpeg copy failed try re encoding video
	    if ($exitCode -ne 0) {
		# --- Encoding Variables ---
		# $videoEncoder   = "libx265" # "libx264" or "libx265"
		# $audioEncoder   = "aac"     # AAC audio
		# $audioBitrate   = 128       # kbps
		# $videoQuality   = 28        # CRF value, lower = better quality

		$ffmpegFallbackArgs = @(
		    "-hide_banner","-y",
		    "-f","concat","-safe","0",
		    "-i",$mylistPath,
		    "-fflags","+genpts","-reset_timestamps","1",
		    "-c:v",$videoEncoder,
		    "-crf",$videoQuality,
		    "-c:a",$audioEncoder,
		    "-b:a","${audioBitrate}k",
		    $outputFile
		)
		
		$formRef.Invoke([Action]{
		    foreach ($row in $listRef.Items) {
			if ($row.Text -eq $folderName) {
			    $row.SubItems[3].Text = "Converting..."
			    break
			}
		    }
		})
		
		#------------------------------------------------
		# FFmpeg Re-Encode
		# capture all output (stdout + stderr) in order
		# Waits automatically, since this is synchronous
		#------------------------------------------------
		$ffmpegOutput = & $ffmpegPath @ffmpegArgsConcatEnc 2>&1
		$exitCode = $LASTEXITCODE

		# this code allows for log files to be produced
		$ffmpegOutput | Out-File -FilePath $logFile -Encoding UTF8 -Append	    
		# $ffmpegFallback = Start-Process -FilePath ffmpeg -ArgumentList $ffmpegFallbackArgs -NoNewWindow -Wait -PassThru 2>&1

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
		  
		     # Update ListView
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
			}
		    })
		   
		    return
		}
	    }

	    

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
            try {
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
		    $tempMp4UI, 
		    $mcebuddyCLI, 
		    $form, 
		    $listView, 
		    ([ref]$global:tempFilesWaiting), 
		    $global:maxTempFilesWaiting,
		     $videoQuality,
		    $profiles,
		    $selectedProfile,
		    $audioOverride,
		    $selectedAudio,
		    $global:logDir,
		    $ffmpegPath

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
        }
    } catch {
        Write-Warning "Queue polling failed: $_"
    }
})
$timer.Start()


# --- Show the form ---
[System.Windows.Forms.Application]::Run($form)
# [System.Windows.Forms.Application]::EnableVisualStyles()

