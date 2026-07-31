param(
    [string]$Encoder
)

Add-Type -AssemblyName 'System.Windows.Forms'
Add-Type -AssemblyName 'System.Drawing'


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

$themeFile = Join-Path $rootDir "data\theme.txt"
$currentMode = Import-ThemeState -themeFile $themeFile

$settings = Import-Settings

if ($settings) {
    $TabloDBpath	    = $settings.TabloDBpath
    $MCEBuddyCLI	    = $settings.MCEBuddyCLI        
    $HandBrakeCLI    = $settings.HandBrakeCLI       
    $FFmpegPath	    = $settings.FFmpegPath  
    $TempMp4Dir	    = $settings.TempMp4Dir 
}


$formHght = 500
$formWidth = 1200

# --- Form ---
$form = New-Object System.Windows.Forms.Form
$form.Font = $global:FontRegular
$form.Text = "Settings for Tablo Video Utilities"
$form.Size = New-Object System.Drawing.Size($formWidth,$formHght)
$form.StartPosition = "CenterScreen"
Set-FormTheme -Form $form -Mode $currentMode

$topStrt = 40
$spacing = 50
$top = $topstrt


$textboxTabloDbPath, $labelTabloDbPath = Add-InputRow $form "Tablo db Path"  $top "textbox"
$textboxTabloDbPath.text = $TabloDBpath

$browseTabloDbPath, $label = Add-InputRow $form ""   $top "browse"
$browseTabloDbPath.Add_Click({
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Title = "Select a file"                # Custom title
    # $dlg.InitialDirectory = Join-Path $rootDir "etc\icons"   # Default folder
    # $dlg.InitialDirectory = [Environment]::GetFolderPath('MyDocuments')  # Default folder
    $dlg.Filter = "db Files (*.db)|*.db|All Files (*.*)|*.*"         # File type filters
    $dlg.FilterIndex = 1                        # Default to first filter
    $dlg.Multiselect = $false                   # Allow only one file
    $dlg.CheckFileExists = $true                # Ensure file exists before returning
    $dlg.CheckPathExists = $true
    $dlg.RestoreDirectory = $true               # Return to last folder next time
    $dlg.DefaultExt = "db"                     # Default extension if none given

    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        # $dlg.FileName gives full path to the selected file
        $textboxTabloDbPath.Text = $dlg.FileName
    }
})


$top = (1*$spacing) + $topstrt

$textboxMCEBuddyCLI, $labelMCEBuddyCLI = Add-InputRow $form "MCEBuddy CLI"  $top "textbox"
$textboxMCEBuddyCLI.text =  $MCEBuddyCLI

$browseMCEBuddyCLI, $label = Add-InputRow $form ""   $top "browse"
$browseMCEBuddyCLI.Add_Click({
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Title = "Select a file"                # Custom title
    # $dlg.InitialDirectory = Join-Path $rootDir "etc\icons"   # Default folder
    # $dlg.InitialDirectory = [Environment]::GetFolderPath('MyDocuments')  # Default folder
    $dlg.Filter = "exe Files (*.exe)|*.exe|All Files (*.*)|*.*"         # File type filters
    $dlg.FilterIndex = 1                        # Default to first filter
    $dlg.Multiselect = $false                   # Allow only one file
    $dlg.CheckFileExists = $true                # Ensure file exists before returning
    $dlg.CheckPathExists = $true
    $dlg.RestoreDirectory = $true               # Return to last folder next time
    $dlg.DefaultExt = "exe"                     # Default extension if none given

    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        # $dlg.FileName gives full path to the selected file
        $textboxMCEBuddyCLI.Text = $dlg.FileName
    }
})

$top = (2*$spacing) + $topstrt

$textboxHandBrakeCLI, $labelHandBrakeCLI = Add-InputRow $form "Handbrake CLI"  $top "textbox"
$textboxHandBrakeCLI.text = $HandBrakeCLI

$browseHandBrakeCLI, $label = Add-InputRow $form ""   $top "browse"
$browseHandBrakeCLI.Add_Click({
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Title = "Select a file"                # Custom title
    # $dlg.InitialDirectory = Join-Path $rootDir "etc\icons"   # Default folder
    # $dlg.InitialDirectory = [Environment]::GetFolderPath('MyDocuments')  # Default folder
    $dlg.Filter = "exe Files (*.exe)|*.exe|All Files (*.*)|*.*"         # File type filters
    $dlg.FilterIndex = 1                        # Default to first filter
    $dlg.Multiselect = $false                   # Allow only one file
    $dlg.CheckFileExists = $true                # Ensure file exists before returning
    $dlg.CheckPathExists = $true
    $dlg.RestoreDirectory = $true               # Return to last folder next time
    $dlg.DefaultExt = "exe"                     # Default extension if none given

    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        # $dlg.FileName gives full path to the selected file
        $textboxHandBrakeCLI.Text = $dlg.FileName
    }
})

$top = (3*$spacing) + $topstrt

$textboxFFmpegPath, $labelFFmpegPath = Add-InputRow $form "FFmpeg Path"  $top "textbox"
$textboxFFmpegPath.text =  $FFmpegPath

$browseFFmpegPath, $label = Add-InputRow $form ""   $top "browse"
$browseFFmpegPath.Add_Click({
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Title = "Select a file"                # Custom title
    # $dlg.InitialDirectory = Join-Path $rootDir "etc\icons"   # Default folder
    # $dlg.InitialDirectory = [Environment]::GetFolderPath('MyDocuments')  # Default folder
    $dlg.Filter = "exe Files (*.exe)|*.exe|All Files (*.*)|*.*"         # File type filters
    $dlg.FilterIndex = 1                        # Default to first filter
    $dlg.Multiselect = $false                   # Allow only one file
    $dlg.CheckFileExists = $true                # Ensure file exists before returning
    $dlg.CheckPathExists = $true
    $dlg.RestoreDirectory = $true               # Return to last folder next time
    $dlg.DefaultExt = "exe"                     # Default extension if none given

    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        # $dlg.FileName gives full path to the selected file
        $textboxFFmpegPath.Text = $dlg.FileName
    }
})

$top = (4*$spacing) + $topstrt

$textboxTempMp4Dir, $labelTempMp4Dir = Add-InputRow $form "FFmpeg Temp mp4"  $top "textbox"
$textboxTempMp4Dir.text =  $TempMp4Dir

$browseTempMp4Dir, $label = Add-InputRow $form ""   $top "browse"
$browseTempMp4Dir.Add_Click({
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    # $dlg.SelectedPath = $rootDir
    # $dlg.SelectedPath = [Environment]::GetFolderPath("MyDocuments")
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
	    $textboxTempMp4Dir.Text = $dlg.SelectedPath
    }
})

$top = (6*$spacing-10) + $topstrt

# --- Start button ---
$btnOK, $null = Add-InputRow $form ""   $top "button"
$btnOK.Text = "OK"
$btnOK.Location = New-Object System.Drawing.Point($global:labelLeft2, $top)
$btnOK.Width = $buttonwidth



# ----------------------
# Button Start Event
# ----------------------
$btnOK.Add_Click({

    $settings = Import-Settings

    $settings.TabloDBpath = $textboxTabloDbPath.text
    $settings.MCEBuddyCLI = $textboxMCEBuddyCLI.Text       
    $settings.HandBrakeCLI  =  $textboxHandBrakeCLI.Text     
    $settings.FFmpegPath  = $textboxFFmpegPath.Text
    $settings.TempMp4Dir = $textboxTempMp4Dir.Text

    Save-Settings $settings 
    $form.Close() 

})




# Use last control to determine needed height
 $bottomMostButton = $btnOK
 $neededHeight = $bottomMostButton.Bottom + 150
 $form.Height = $neededHeight

# --- Show the form ---
[System.Windows.Forms.Application]::Run($form)
# [System.Windows.Forms.Application]::EnableVisualStyles()
