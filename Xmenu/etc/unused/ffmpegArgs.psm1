$ffmpegArgsEncode = @(
    "-loglevel","error",
    "-hide_banner", "-y",
    "-i","{INPUT}",
    "-fflags","+genpts","-reset_timestamps","1",
    "-c:v",$videoEncoder,
    "-crf",$videoQuality,
    "-c:a",$audioEncoder,
    "-b:a","${audioBitrate}k",
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

$ffmpegArgsConcatCopy = @(
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

$ffmpegArgsCopy = @(
    "-loglevel","error",
    "-hide_banner","-y",
    "-i","{INPUT}",
    "-map","0",
    "-c","copy",
    "{OUTPUT}"
)



$ffmpegArgsConcatEnc = @(
    "-loglevel","error",
    "-hide_banner","-y",
    "-f","concat","-safe","0",
    "-i","{INPUT}",
    "-fflags","+genpts","-reset_timestamps","1",
    "-c:v",$videoEncoder,
    "-crf",$videoQuality,
    "-c:a",$audioEncoder
    "-b:a","${audioBitrate}k"
)
if ($null -ne $audioChannels) {
    $ffmpegArgsConcatEnc += @("-ac", $audioChannels)
}
    $ffmpegArgsConcatEnc += "{OUTPUT}"



$settings = . "$PSScriptRoot\FFmpegSettings.ps1"

$args = $settings.ConcatCopy.Clone()

$args = $args.ForEach{
    $_ -replace '\{INPUT\}', $myListPath `
       -replace '\{OUTPUT\}', $outputFile
}

& $ffmpegPath @args

