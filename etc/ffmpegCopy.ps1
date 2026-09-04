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
# Convert-ToBytes
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
$global:CancelProcessing = $false
$global:tempFilesWaiting = 0
$global:maxTempFilesWaiting = 3 

$settings = Import-Settings

if ($settings) {
    $global:MCEBuddyCLI	    = $settings.MCEBuddyCLI        
    $global:HandBrakeCLI    = $settings.HandBrakeCLI       
    $global:FFmpegPath	    = $settings.FFmpegPath             
    $DefaultVideoDir	    = $settings.VideoDir
    # $global:tempMp4Di	    = $settings.TempMp4Dir
    $DefaultDest            = $settings.Destination
    # $DefaultVideoQuality  = $settings.VideoQuality
    # $DefaultProfileName   = $settings.ProfileName
    # $DefaultRunMode	    = $settings.RunMode
    $DefaultMaxJobs	    = $settings.MaxJobs
    # $DefaultSize          = $settings.MinSize
    # $DefaultAudioName	    = $settings.AudioOverride
    # $DefaultPresetValue   = $settings.Preset  
}

# if ([string]::IsNullOrWhiteSpace($DefaultSize)) {
#     $DefaultSize = "400MB"
#   }   

if ([string]::IsNullOrWhiteSpace($DefaultVideoDir)) {
    $DefaultVideoDir = "D:\Desktop\Tablo\rec" 
}

# if ([string]::IsNullOrWhiteSpace($DefaultVideoQuality)) {
#	$DefaultVideoQuality = "23"
#   }   

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
$form.Text = "mkv → mp4 using ffmpeg copy"
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
Set-TextboxStyle -Textbox $textboxDest -Mode $currentMode
$form.Controls.Add($textboxDest)

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

$top = (4*$spacing) + $topstrt

# --- Start button ---
$btnStart = New-Object System.Windows.Forms.Button
$btnStart.Text = "Start Processing"
$btnStart.Height = $buttonHght
$btnStart.Width = $buttonwidth + 30
$btnStart.Location = New-Object System.Drawing.Point($labelLeft,$top)
Set-ButtonStyle -Button $btnStart -Mode $currentMode
$form.Controls.Add($btnStart)



# --- Cancel button ---
$btnCancel = New-Object System.Windows.Forms.Button
$btnCancel.Text = "Cancel Processing"
$btnCancel.Height = $buttonHght
$btnCancel.Width = $buttonwidth + 30
$btnCancel.Left = $labelLeft + 650
$btnCancel.Top = $top
Set-ButtonStyle -Button $btnCancel -Mode $currentMode
$form.Controls.Add($btnCancel)
 $btnCancel.Enabled = $false

$top = (5*$spacing-10) + $topstrt

# --- ListView for job status ---
$listView = New-Object System.Windows.Forms.ListView
$listView.Location = New-Object System.Drawing.Point($global:labelLeft,$top)
$listView.Size = New-Object System.Drawing.Size($formWidth,$listViewHght)
$listView.View = 'Details'
$listView.FullRowSelect = $true
$listView.GridLines = $true
[void]$listView.Columns.Add("Folder",420)
[void]$listView.Columns.Add("Destination MP4",420)
[void]$listView.Columns.Add("Encode Status",140)
[void]$listView.Columns.Add("Final Status",140)
Set-ListViewStyle -ListView $listView -Mode $currentMode
$form.Controls.Add($listView)

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
    $global:fileQueue.Clear()

    $btnStart.Enabled  = $true
    $btnCancel.Enabled = $false
    # stop timer
    $timer.Stop()

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
    $global:maxConcurrentJobs	= [int]$textboxMaxJobs.Text
    
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
   $settings = Import-Settings

    $settings.VideoDir      = $videoDir
    $settings.Destination   = $global:destination
    $settings.MaxJobs       = $global:maxConcurrentJobs

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
    $global:fileQueue  = [System.Collections.Queue]::new()
    $global:jobs         = @()

    # --- Load video files into queue ---
    $videoFiles = Get-ChildItem -Path $videoDir -Filter *.mkv
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

	    $outputFile = Join-Path $global:destination (
		[System.IO.Path]::GetFileNameWithoutExtension($vidfilename) + ".mp4"
	    )
           
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
		    $ffmpegPath, 
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
		  
		Write-Output ([PSCustomObject]@{
		    Folder        = $vidfilename
		    FastStatus    = "Running..."
		    FinalStatus   = "—"
		})

		$FFmpegFunctions = Join-Path $rootDir "etc\FFmpegFunctions.ps1"
		. $FFmpegFunctions

		#
		# Profile  = "Copy"	    $Source   = $inputPath
		# Profile  = "Encode"	    $Source   = $inputPath
		# Profile  = "ConcatCopy    $Source  = $myListPath
		# Profile  = "ConcatEncode" $Source   = $myListPath
		#

		$Source   = $inputPath

		$args = Get-FFmpegArguments `
		    -RootDir $rootDir `
		    -Profile "Copy" `
		    -InputPath $Source `
		    -OutputPath $outputFile 


		try {
		    # -- MKV -> MP4 container conversion (no re-encode) ---
		    $fastStatus = "Running..."

		    # $ffmpegOutput = & $ffmpegPath $ffmpegArgsCopy 2>&1
		    $ffmpegOutput = & $ffmpegPath @args 2>&1
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
			    $global:ffmpegPath,
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
