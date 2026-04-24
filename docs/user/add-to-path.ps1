Write-Host "Adding directory to PATH..."

$dir = Split-Path -Parent $MyInvocation.MyCommand.Path
Write-Host "Directory: $dir"

$currentPath = [Environment]::GetEnvironmentVariable("PATH", "User")
if ($currentPath -notlike "*$dir*") {
    $newPath = $currentPath + ";" + $dir
    [Environment]::SetEnvironmentVariable("PATH", $newPath, "User")
    Write-Host "Successfully added to PATH!"
} else {
    Write-Host "Directory already in PATH"
}

Write-Host "Restart command prompt to use magic-cli"
Read-Host "Press Enter to continue"