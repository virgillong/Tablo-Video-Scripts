@{

    ##################################################################
    # Re-encode a single media file.
    #
    # -i $inputPath
    #    Reads one input media file (TS, MP4, MKV, etc.).
    # -preset 
    #    speed vs. compression doesn't override things like CRF or audio bitrate.
    # -fflags +genpts
    #    Generates missing presentation timestamps when needed.
    #
    # -reset_timestamps 1
    #    Resets timestamps so the output starts at zero.
    #
    # -c:v $videoEncoder
    #    Re-encodes the video using the selected codec
    #    (for example: libx264 or libx265).
    #
    # -crf $videoQuality
    #    Uses Constant Rate Factor to control video quality.
    #    Lower values = higher quality / larger files.
    #    Higher values = lower quality / smaller files.
    #
    # -c:a $audioEncoder
    #    Re-encodes the audio using the selected codec.
    #
    # -b:a ${audioBitrate}k
    #    Sets the target audio bitrate.
    #
    # Produces a newly encoded output file using the selected
    # video and audio encoding settings.
    ##################################################################
    #  $ffmpegArgsEncode

    Encode = @(
	"-loglevel","error",
	"-hide_banner","-y",
	"-i","{INPUT}",
	"-fflags","+genpts","-reset_timestamps","1",
	"-c:v","{VIDEO_ENCODER}",
	"-preset", "{PRESET}",
	"-crf","{CRF}",
	"-c:a","{AUDIO_ENCODER}",
	"-b:a","{AUDIO_BITRATE_K}",
	"{AUDIO_CHANNELS}",
	"{OUTPUT}"
    )
    ##################################################################
    # -f concat → The input is a concat list file, not a media file.
    # -safe 0 → Allow absolute paths in the list file.
    # -i $mylistPath → Read a text file that looks like:
    #    file 'segment001.ts'
    #    file 'segment002.ts'
    #    file 'segment003.ts'
    # FFmpeg stitches all of those files together into one output without re-encoding
    # $ffmpegArgsConcatCopy

    ConcatCopy = @(
	"-loglevel","error",
	"-hide_banner","-y",
	"-f","concat","-safe","0",
	"-i","{INPUT}",
	"-c","copy",
	"{OUTPUT}"
    )

    # $inputPath = "movie.ts" or $inputPath = "movie.mp4"
    # It copies one media file into another container.
    # The additional option -map 0 means: Copy every stream from the input.
    #  That includes: video,audio,subtitles,attachments,chapters,metadata,streams

    Copy = @(
	"-loglevel","error",
	"-hide_banner","-y",
	"-i","{INPUT}",
	"-map","0",
	"-c","copy",
	"{OUTPUT}"
    )

    ##################################################################
    # Concatenate multiple media segments and re-encode them.
    #
    # -f concat
    #    Treats the input as an FFmpeg concat list.
    #
    # -safe 0
    #    Allows absolute paths in the concat list file.
    #
    # -i $mylistPath
    #    Reads a text file containing a list of media segments,
    #    for example:
    #       file 'segment001.ts'
    #       file 'segment002.ts'
    #       file 'segment003.ts'
    #
    # FFmpeg joins all listed segments into one continuous stream
    # and re-encodes the result.
    #
    # -fflags +genpts
    #    Generates missing presentation timestamps.
    #
    # -reset_timestamps 1
    #    Starts the output timeline at zero.
    #
    # -c:v $videoEncoder
    #    Re-encodes the video using the selected codec.
    #
    # -crf $videoQuality
    #    Controls video quality using Constant Rate Factor.
    #
    # -c:a $audioEncoder
    #    Re-encodes the audio using the selected codec.
    #
    # -b:a ${audioBitrate}k
    #    Sets the audio bitrate.
    #
    # -ac $audioChannels (optional)
    #    Forces the output to the specified number of audio channels
    #    (for example, 2 for stereo).
    #
    # Produces a single encoded output file containing all input
    # segments joined together.
    ##################################################################
    # $ffmpegArgsConcatEnc

    ConcatEncode = @(
	"-loglevel","error",
	"-hide_banner","-y",
	"-f","concat",
	"-safe","0",
	"-i","{INPUT}",
	"-fflags","+genpts","-reset_timestamps","1",
	"-c:v","{VIDEO_ENCODER}",
	"-preset", "{PRESET}",
	"-crf","{CRF}",
	"-c:a","{AUDIO_ENCODER}",
	"-b:a","{AUDIO_BITRATE_K}",
	"{AUDIO_CHANNELS}",
	"{OUTPUT}"
    )

# Option		     Meaning
# -e		    Video encoder, such as x264 or x265.
# --encoder-preset  Adjust video encoding settings for a particular speed/efficiency tradeoff
# -q		    Constant quality value.
# -E		    Audio encoder, such as aac.
# -B		    Audio bitrate in kbps.
# {MIXDOWN}	    Optional mixdown argument.

    HandBrake = @(
	"--input", "{INPUT}",
	"--output", "{OUTPUT}",
	"-e", "{VIDEO_ENCODER}",  
	"--encoder-preset", "{PRESET}",	# Preset
	"-q", "{CRF}",			# Quality (CRF-like)
	"-E", "{AUDIO_ENCODER}",	# Audio encoder
	"-B", "{AUDIO_BITRATE}",	# Audio bitrate kbps
	"{MIXDOWN}"
    )
}
