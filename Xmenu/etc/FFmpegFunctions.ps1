
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
        $AudioChannels,
        $Preset
    )

    $settings = . (Join-Path $RootDir "etc\FFmpegSettings.ps1")

    foreach ($arg in $settings.$Profile) {

        switch ($arg) {

            "{INPUT}"          { $InputPath }

            "{OUTPUT}"         { $OutputPath }

            "{VIDEO_ENCODER}"  { $VideoEncoder }

            "{CRF}"            { $VideoQuality }

            "{AUDIO_ENCODER}"  { $AudioEncoder }

            "{AUDIO_BITRATE}"  { $AudioBitrate }

	    "{AUDIO_BITRATE_K}" { "${AudioBitrate}k" }

            "{PRESET}"         { $Preset }

            "{AUDIO_CHANNELS}" {
                if ($AudioChannels) {
                    "-ac"
                    "$AudioChannels"
                }
            }
	    
	    "{MIXDOWN}" {
		if ($AudioChannels) {
		    switch ($AudioChannels) {
			1 { "--mixdown"; "mono" }
			2 { "--mixdown"; "stereo" }
			6 { "--mixdown"; "5point1" }
			8 { "--mixdown"; "7point1" }
			default { "--mixdown"; "stereo" }
		    }
		}
	    }

            default { $arg }
        }
    }
}