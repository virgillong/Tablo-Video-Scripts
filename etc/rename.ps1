# CONFIGURATION
# $videoDir = "D:\Desktop\Tablo Video Capture\rec1"
# $dbPath = "D:\Desktop\Tablo Video Capture\Tablo.db"
# $dryRun = $true  # Set to $false to actually rename folders


Add-Type -AssemblyName 'System.Windows.Forms'
Add-Type -AssemblyName 'System.Drawing'
Import-Module Microsoft.PowerShell.ThreadJob

# Default path fallback for rootDir
if (-not $env:rootDir) {
    $env:rootDir = (Resolve-Path "$PSScriptRoot\..").Path
}
$rootDir = $env:rootDir 

Import-Module (Join-Path $rootDir "etc\includes\UIHelpers.psm1") -Force
Import-Module (Join-Path $rootDir "etc\includes\alert.psm1") -Force
Import-Module (Join-Path $rootDir "etc\includes\settings.psm1") -Force


$themeFile = Join-Path $rootDir "data\theme.txt"
$currentMode = Import-ThemeState -themeFile $themeFile

$settings = Import-Settings

if ($settings) {        
    $DefaultVideoDir	    = $settings.SEGvideoDir
    $DefaultdbPath	    = $settings.TabloDBpath
}

if ([string]::IsNullOrWhiteSpace($videoDirFilePath)) {
    $videoDirFilePath = "D:\Desktop\Tablo\rec" 
}   

$labelLeft = 10
$labelLeft2 = 350
$textLeft = 200
$buttonwidth = 150
$buttonHght = 30
$formHght = 500
$formWidth = 900

$form = New-Object Windows.Forms.Form
$form.Font = $global:FontRegular
$form.Text = "Convert Tablo files to MP4 - Rename Video Directory"
$form.Size = New-Object System.Drawing.Size($formWidth,$formHght)
$form.StartPosition = 'CenterScreen'
$form.TopMost = $true
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

# --- dbPath Label ---
$labeldbPath = New-Object Windows.Forms.Label
$labeldbPath.Text = "Path to Tablo.db"
$labeldbPath.AutoSize = $true
$labeldbPath.Left = $labelLeft
$labeldbPath.Top = $top
Set-LabelStyle -Label $labeldbPath -Mode $currentMode

# --- dpPath TextBox ---
$textboxdbPath = New-Object Windows.Forms.TextBox
$textboxdbPath.Size = New-Object System.Drawing.Size(420,20)
$textboxdbPath.Left = $textLeft
$textboxdbPath.Top = $top
$textboxdbPath.Text = $DefaultdbPath
Set-TextboxStyle -Textbox $textboxdbPath -Mode $currentMode

# --- dbPath Browse Button ---
$browsedbPathButton = New-Object Windows.Forms.Button
$browsedbPathButton.Text = "Browse"
$browsedbPathButton.Size = New-Object System.Drawing.Size($buttonwidth,$buttonHght)
$browsedbPathButton.Left = 630
$browsedbPathButton.Top = $top-2
$browsedbPathButton.Add_Click({

    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    # $dlg.InitialDirectory = Join-Path $rootDir "data"
    $dlg.Filter = "db Files (*.db)|*.db|All files (*.*)|*.*"

    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
	 $textboxdbPath.Text = $dlg.FileName
    } 
})
Set-ButtonStyle -Button $browsedbPathButton -Mode $currentMode

$top = (2*$spacing) + $topstrt

#New checkbox for dry run
$checkbox = New-Object Windows.Forms.CheckBox
$checkbox.Text = "Dry Run"
$checkbox.Left = $labelLeft
$checkbox.Top = $top
$checkbox.AutoSize = $true
$checkbox.checked = $true
Set-CheckboxStyle -Checkbox $checkbox -Mode $currentMode

$top = (3*$spacing) + $topstrt

#New checkbox for remove leading articles from title
$checkboxTitle = New-Object Windows.Forms.CheckBox
$checkboxTitle.Text = "Remove leading article from Title"
$checkboxTitle.Left = $labelLeft
$checkboxTitle.Top = $top
$checkboxTitle.AutoSize = $true
Set-CheckboxStyle -Checkbox $checkboxTitle -Mode $currentMode

$top = (4*$spacing) + $topstrt

#New checkbox for remove articles from episode title
$checkboxEp = New-Object Windows.Forms.CheckBox
$checkboxEp.Text = "Remove leading article from episode title"
$checkboxEp.Left = $labelLeft
$checkboxEp.Top = $top
$checkboxEp.AutoSize = $true
Set-CheckboxStyle -Checkbox $checkboxEp -Mode $currentMode

$top = (6*$spacing) + $topstrt

# --- OK Button ---
$okButton = New-Object Windows.Forms.Button
$okButton.Text = "OK"
$okButton.Size = New-Object System.Drawing.Size($buttonwidth,$buttonHght)
$okButton.Left = ($formWidth/2)-$buttonwidth
$okButton.Top = $top
$okButton.Add_Click({ $form.Close() })
Set-ButtonStyle -Button $okButton -Mode $currentMode



# --- Add Controls ---
$form.Controls.AddRange(@(
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

Write-Host "Video directory selected: $videoDir"
Write-Host "Database Path selected: $dbPath"
if ($dryRun) {
    Write-Host "Dry Run is On"
} else {
    Write-Host "Dry Run is Off"
}

$settings = Import-Settings

$settings.SEGvideoDir	= $videoDir
$settings.TabloDBpath	= $dbPath

Save-Settings $settings 




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
    Show-Alert -Title "Invalid Configuration" -Message "Failed to connect to SQLite DB. Make sure the SQLite ODBC driver is installed: https://www.ch-werner.de/sqliteodbc/"
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