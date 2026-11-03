# claude-readguard – Startmenü-Verknüpfung für die Fenster-App unter Windows.
# Experimentell: Der Hook selbst braucht Git Bash und jq (siehe README).
# Aufruf:  powershell -ExecutionPolicy Bypass -File install.ps1

$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
$App  = Join-Path $Here "readguard-app.py"

$Py = (Get-Command pythonw.exe -ErrorAction SilentlyContinue).Source
if (-not $Py) { $Py = (Get-Command python.exe -ErrorAction SilentlyContinue).Source }
if (-not $Py) {
    Write-Host "FEHLER: Python wurde nicht gefunden. Bitte von https://www.python.org installieren (mit 'Add to PATH')."
    exit 1
}

$Menu = [Environment]::GetFolderPath("Programs")
$Lnk  = Join-Path $Menu "Readguard.lnk"
$Shell = New-Object -ComObject WScript.Shell
$S = $Shell.CreateShortcut($Lnk)
$S.TargetPath       = $Py
$S.Arguments        = "`"$App`""
$S.WorkingDirectory = $Here
$S.Description      = "Zeigt, welche Dateien Claude Code gelesen hat"
$S.Save()
Write-Host "Startmenü-Eintrag angelegt: $Lnk"

$Bash = Get-Command bash.exe -ErrorAction SilentlyContinue
if ($Bash) {
    Write-Host "Git Bash gefunden. Hook einrichten mit:  bash install.sh   (braucht jq)"
} else {
    Write-Host "Hinweis: Git Bash fehlt. Ohne Git Bash und jq läuft der Hook nicht, die App zeigt dann ein leeres Log."
}
