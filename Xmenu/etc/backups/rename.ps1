# CONFIGURATION
# $videoDir = "D:\Desktop\Tablo Video Capture\rec1"
# $dbPath = "D:\Desktop\Tablo Video Capture\Tablo.db"
# $dryRun = $true  # Set to $false to actually rename folders


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

$DefaultdbPath = "D:\Desktop\Tablo\Tablo.db"
$videoDirFilePath = Join-Path $rootDir "data\videodir.txt"

if (Test-Path -Path $videoDirFilePath) {
    $DefaultVideoDir = (Get-Content -Path $videoDirFilePath -Raw).Trim()
} else {
    $DefaultVideoDir = "D:\Desktop\Tablo\rec"
}

$form = New-Object Windows.Forms.Form
$form.Text = "Convert Tablo files to MP4 - Rename Video Directory"
$form.Width = 520
$form.Height = 340
$form.StartPosition = 'CenterScreen'
$form.TopMost = $true
Set-FormTheme -Form $form -Mode $currentMode

# --- Video Directory Label ---
$labelVideoDir = New-Object Windows.Forms.Label
$labelVideoDir.Text = "Video Directory:"
$labelVideoDir.AutoSize = $true
$labelVideoDir.Left = 10
$labelVideoDir.Top = 20
Set-LabelStyle -Label $labelVideoDir -Mode $currentMode

# --- Video Directory TextBox ---
$textboxVideoDir = New-Object Windows.Forms.TextBox
$textboxVideoDir.Width = 350
$textboxVideoDir.Left = 10
$textboxVideoDir.Top = 40
$textboxVideoDir.Text = $DefaultVideoDir
Set-TextboxStyle -Textbox $textboxVideoDir -Mode $currentMode

# --- Video Directory Browse Button ---
$browseVideoDirButton = New-Object Windows.Forms.Button
$browseVideoDirButton.Text = "Browse"
$browseVideoDirButton.Width = 80
$browseVideoDirButton.Left = 370
$browseVideoDirButton.Top = 38
$browseVideoDirButton.Add_Click({
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.SelectedPath = $textboxVideoDir.Text
    $dialog.Description = "Select Video Directory"
    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $textboxVideoDir.Text = $dialog.SelectedPath
    }
})
Set-ButtonStyle -Button $browseVideoDirButton -Mode $currentMode

# --- dbPath Label ---
$labeldbPath = New-Object Windows.Forms.Label
$labeldbPath.Text = "Path to Tablo.db"
$labeldbPath.AutoSize = $true
$labeldbPath.Left = 10
$labeldbPath.Top = 80
Set-LabelStyle -Label $labeldbPath -Mode $currentMode

# --- dpPath TextBox ---
$textboxdbPath = New-Object Windows.Forms.TextBox
$textboxdbPath.Width = 350
$textboxdbPath.Left = 10
$textboxdbPath.Top = 100
$textboxdbPath.Text = $DefaultdbPath
Set-TextboxStyle -Textbox $textboxdbPath -Mode $currentMode

# --- dbPath Browse Button ---
$browsedbPathButton = New-Object Windows.Forms.Button
$browsedbPathButton.Text = "Browse"
$browsedbPathButton.Width = 80
$browsedbPathButton.Left = 370
$browsedbPathButton.Top = 98
$browsedbPathButton.Add_Click({

    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    # $dlg.InitialDirectory = Join-Path $rootDir "data"
    $dlg.Filter = "db Files (*.db)|*.db|All files (*.*)|*.*"

    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
	 $textboxdbPath.Text = $dlg.FileName
    } 
})
Set-ButtonStyle -Button $browsedbPathButton -Mode $currentMode

# --- OK Button ---
$okButton = New-Object Windows.Forms.Button
$okButton.Text = "OK"
$okButton.Width = 80
$okButton.Left = 200
$okButton.Top = 260
$okButton.Add_Click({ $form.Close() })
Set-ButtonStyle -Button $okButton -Mode $currentMode


#New checkbox for dry run
$checkbox = New-Object Windows.Forms.CheckBox
$checkbox.Text = "Dry Run"
$checkbox.Left = 10
$checkbox.Top = 140
$checkbox.AutoSize = $true
$checkbox.checked = $true
Set-CheckboxStyle -Checkbox $checkbox -Mode $currentMode

#New checkbox for remove leading articles from title
$checkboxTitle = New-Object Windows.Forms.CheckBox
$checkboxTitle.Text = "Remove leading article from Title"
$checkboxTitle.Left = 10
$checkboxTitle.Top = 180
$checkboxTitle.AutoSize = $true
Set-CheckboxStyle -Checkbox $checkboxTitle -Mode $currentMode

#New checkbox for remove articles from episode title
$checkboxEp = New-Object Windows.Forms.CheckBox
$checkboxEp.Text = "Remove leading article from episode title"
$checkboxEp.Left = 10
$checkboxEp.Top = 220
$checkboxEp.AutoSize = $true
Set-CheckboxStyle -Checkbox $checkboxEp -Mode $currentMode




# --- Add Controls ---
$form.Controls.AddRange(@(
    $labelVideoDir, $textboxVideoDir, $browseVideoDirButton,
    $labeldbPath, $textboxdbPath, $browsedbPathButton,
    $checkbox, $checkboxTitle, $checkboxEp, $okButton

))

$checkbox.Add_CheckedChanged({
    if  ($checkbox.Checked){
	$dryRun = $true  # Set to $false to actually rename folders
	Write-Host "Dry Run turned on"

    } else {
	$dryRun = $false  
	 Write-Host "Dry Run turned off"
    }

})

$okButton.DialogResult = [System.Windows.Forms.DialogResult]::OK

# To also allow pressing Enter to trigger the OK button:
$form.AcceptButton = $okButton

$dialogResult = $form.ShowDialog()


if ($dialogResult -ne [System.Windows.Forms.DialogResult]::OK) {
    return
}

# --- Validate inputs ---
if ([string]::IsNullOrWhiteSpace($textboxVideoDir.Text) -or -not (Test-Path $textboxVideoDir.Text)) {
    Write-Host "Invalid video directory: $textboxVideoDir.Text."
    return
}
if ([string]::IsNullOrWhiteSpace($textboxdbPath.Text) -or -not (Test-Path $textboxdbPath.Text)) {
    Write-Host "Invalid Tablo database directory."
    return
}

if  ($checkbox.Checked){
    $dryRun = $true  # Set to $false to actually rename folders
} else {
    $dryRun = $false 
}

if  ($checkboxTitle.Checked){
    $remArticleTitle = $true  # Set to $false to actually rename folders
} else {
    $remArticleTitle = $false 
}
if  ($checkboxEp.Checked){
    $remArticleEp = $true  # Set to $false to actually rename folders
} else {
    $remArticleEp = $false 
}

$videoDir = $textboxVideoDir.Text
$dbPath = $textboxdbPath.Text

# $dirPath = Split-Path -Path $videoDirFilePath
# if (-not (Test-Path $dirPath)) {
#     New-Item -ItemType Directory -Path $dirPath -Force
# }

Write-Host "Video directory selected: $videoDir"
Write-Host "Database Path selected: $dbPath"
if ($dryRun) {
    Write-Host "Dry Run is On"
} else {
    Write-Host "Dry Run is Off"
}

 Write-Host "videoDirFilePath: $videoDirFilePath"
 Set-Content -Path $videoDirFilePath -Value $videoDir

pause

# Function to sanitize folder names
function Sanitize-FileName($name) {
    $invalid = [System.IO.Path]::GetInvalidFileNameChars()
    foreach ($char in $invalid) {
        $name = $name -replace [Regex]::Escape($char), ''
    }
    return $name.Trim()
}

# Build ODBC connection string
$connectionString = "Driver=SQLite3 ODBC Driver;Database=$dbPath;"
try {
    $connection = New-Object System.Data.Odbc.OdbcConnection($connectionString)
    $connection.Open()
} catch {
    Write-Error "❌ Failed to connect to SQLite DB. Make sure the SQLite ODBC driver is installed: https://www.ch-werner.de/sqliteodbc/"
    exit 1
}

# SQL query
$sql = @"
SELECT ID, title, seasonNum, episodeNum, episodeTitle
FROM Recording
WHERE recordingID > 0
  AND (DateDeleted IS NULL OR LENGTH(DateDeleted) < 1)
ORDER BY title;
"@


# Create command
$command = $connection.CreateCommand()
$command.CommandText = $sql
$reader = $command.ExecuteReader()

# Process each row
while ($reader.Read()) {
    $id = $reader["ID"]
    $title = $reader["title"]
    $season = "{0:D2}" -f [int]$reader["seasonNum"]
    $episode = "{0:D2}" -f [int]$reader["episodeNum"]
    $epTitle = $reader["episodeTitle"]

    $cleanTitle = $title
    $cleanEpTitle = $epTitle

    # Optional: Remove leading article from title and/or episode title

    if ($remArticleTitle){
	$cleanTitle = [Regex]::Replace($title, '^(The|A|An)\s+', '', 'IgnoreCase')
	$cleanTitle = [Regex]::Replace($cleanTitle, '\bTheory\b\s*', '', 'IgnoreCase')
    }
    if ($remArticleEp){
	$cleanEpTitle = [Regex]::Replace($epTitle, '^(The|A|An)\s+', '', 'IgnoreCase')
	
    }



    # Build final string: Title sXXeYY CleanTitle
    $newNamePart = "{0} s{1}e{2} {3}" -f $cleanTitle, $season, $episode, $cleanEpTitle


    $safeName = Sanitize-FileName $newNamePart

    $oldPath = Join-Path $videoDir $id
    $newPath = Join-Path $videoDir $safeName

    if (Test-Path $oldPath) {
	try {
	    # Determine final new name (with suffix if needed)
	    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($safeName)
	    $ext      = [System.IO.Path]::GetExtension($safeName)
	    $dir      = [System.IO.Path]::GetDirectoryName($newPath)

	    $finalName = $safeName
	    $counter   = 1

	    # Increment suffix until unique file/folder name is found
	    while (Test-Path (Join-Path $dir $finalName)) {
		$finalName = "$baseName ($counter)$ext"
		$counter++
	    }

	    if ($dryRun) {
		Write-Host "[DRY-RUN] Would rename '$id' → '$finalName'"
	    } else {
		Rename-Item -Path $oldPath -NewName $finalName
		Write-Host "✅ Renamed '$id' → '$finalName'"
	    }
	}
	catch {
	    Write-Warning "⚠️ Failed to rename '$id': $_"
	}
    }
    else {
	Write-Warning "⚠️ Folder not found for ID: $id"
    }


}

$reader.Close()
$connection.Close()