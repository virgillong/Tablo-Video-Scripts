
function Get-FFmpegArguments {
    param(
        $RootDir,
        $Profile,
        $InputPath,
        $OutputPath,
        $VideoEncoder,
        $VideoQuality,
        $AudioEncoder,
        $AudioBitrate,
	$Preset
    )

    $settings = . (Join-Path $RootDir "etc\FFmpegSettings.ps1")

    $settings.$Profile.ForEach{

        $_ `
            -replace '\{INPUT\}',          $InputPath `
            -replace '\{OUTPUT\}',         $OutputPath `
            -replace '\{VIDEO_ENCODER\}',  $VideoEncoder `
            -replace '\{CRF\}',            $VideoQuality `
            -replace '\{AUDIO_ENCODER\}',  $AudioEncoder `
            -replace '\{AUDIO_BITRATE\}',  $AudioBitrate `
	    -replace '\{PRESET\}',  $Preset
    }
}