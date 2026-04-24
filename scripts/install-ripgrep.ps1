# install-ripgrep.ps1 - Windows ripgrep installer for Magic-CLI

param(
    [switch]$Force = $false
)

# Colors for PowerShell output
function Write-Info {
    param([string]$Message)
    Write-Host "ℹ️  $Message" -ForegroundColor Blue
}

function Write-Success {
    param([string]$Message)
    Write-Host "✅ $Message" -ForegroundColor Green
}

function Write-Warning {
    param([string]$Message)
    Write-Host "⚠️  $Message" -ForegroundColor Yellow
}

function Write-Error {
    param([string]$Message)
    Write-Host "❌ $Message" -ForegroundColor Red
}

# Check if ripgrep is already installed
function Test-Ripgrep {
    try {
        $version = & rg --version 2>$null | Select-Object -First 1
        if ($version) {
            Write-Success "ripgrep already installed: $version"
            return $true
        }
    }
    catch {
        # Command not found
    }
    return $false
}

# Check if running as administrator
function Test-Administrator {
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Install via Chocolatey
function Install-ViaChocolatey {
    Write-Info "Checking for Chocolatey..."
    
    try {
        $chocoVersion = & choco --version 2>$null
        if ($chocoVersion) {
            Write-Info "Using Chocolatey to install ripgrep..."
            & choco install ripgrep -y
            if ($LASTEXITCODE -eq 0) {
                Write-Success "ripgrep installed via Chocolatey"
                return $true
            }
        }
    }
    catch {
        Write-Warning "Chocolatey not found or failed to install ripgrep"
    }
    return $false
}

# Install via Scoop
function Install-ViaScoop {
    Write-Info "Checking for Scoop..."
    
    try {
        $scoopVersion = & scoop --version 2>$null
        if ($scoopVersion) {
            Write-Info "Using Scoop to install ripgrep..."
            & scoop install ripgrep
            if ($LASTEXITCODE -eq 0) {
                Write-Success "ripgrep installed via Scoop"
                return $true
            }
        }
    }
    catch {
        Write-Warning "Scoop not found or failed to install ripgrep"
    }
    return $false
}

# Install via winget
function Install-ViaWinget {
    Write-Info "Checking for winget..."
    
    try {
        $wingetVersion = & winget --version 2>$null
        if ($wingetVersion) {
            Write-Info "Using winget to install ripgrep..."
            & winget install BurntSushi.ripgrep
            if ($LASTEXITCODE -eq 0) {
                Write-Success "ripgrep installed via winget"
                return $true
            }
        }
    }
    catch {
        Write-Warning "winget not found or failed to install ripgrep"
    }
    return $false
}

# Download and install from GitHub releases
function Install-FromGitHub {
    Write-Info "Installing ripgrep from GitHub releases..."
    
    $version = "14.1.1"  # Latest version as of implementation
    $arch = if ([Environment]::Is64BitOperatingSystem) { "x86_64" } else { "i686" }
    $filename = "ripgrep-$version-$arch-pc-windows-msvc.zip"
    $url = "https://github.com/BurntSushi/ripgrep/releases/download/$version/$filename"
    $tempDir = [System.IO.Path]::GetTempPath()
    $downloadPath = Join-Path $tempDir $filename
    $extractPath = Join-Path $tempDir "ripgrep-extract"
    
    try {
        Write-Info "Downloading ripgrep from GitHub: $filename"
        
        # Download the file
        Invoke-WebRequest -Uri $url -OutFile $downloadPath -UseBasicParsing
        
        Write-Info "Extracting ripgrep..."
        
        # Extract the zip file
        if (Test-Path $extractPath) {
            Remove-Item -Path $extractPath -Recurse -Force
        }
        Expand-Archive -Path $downloadPath -DestinationPath $extractPath -Force
        
        # Find the rg.exe file
        $rgExePath = Get-ChildItem -Path $extractPath -Name "rg.exe" -Recurse | Select-Object -First 1
        if (-not $rgExePath) {
            throw "rg.exe not found in the downloaded archive"
        }
        
        $sourceRgPath = Join-Path $extractPath $rgExePath.DirectoryName "rg.exe"
        
        # Try to install to Program Files (requires admin)
        $programFilesPath = "$env:ProgramFiles\ripgrep"
        $userLocalPath = "$env:LOCALAPPDATA\ripgrep"
        
        $installPath = $null
        $addToPath = $false
        
        if (Test-Administrator) {
            Write-Info "Installing ripgrep to Program Files (system-wide)..."
            $installPath = $programFilesPath
        } else {
            Write-Info "Installing ripgrep to user directory..."
            $installPath = $userLocalPath
        }
        
        # Create installation directory
        if (-not (Test-Path $installPath)) {
            New-Item -Path $installPath -ItemType Directory -Force | Out-Null
        }
        
        # Copy rg.exe to installation directory
        $targetRgPath = Join-Path $installPath "rg.exe"
        Copy-Item -Path $sourceRgPath -Destination $targetRgPath -Force
        
        # Add to PATH if not already there
        $currentPath = [Environment]::GetEnvironmentVariable("PATH", [EnvironmentVariableTarget]::User)
        if ($currentPath -notlike "*$installPath*") {
            Write-Info "Adding ripgrep to PATH..."
            $newPath = "$currentPath;$installPath"
            [Environment]::SetEnvironmentVariable("PATH", $newPath, [EnvironmentVariableTarget]::User)
            $addToPath = $true
        }
        
        # Clean up
        Remove-Item -Path $downloadPath -Force -ErrorAction SilentlyContinue
        Remove-Item -Path $extractPath -Recurse -Force -ErrorAction SilentlyContinue
        
        Write-Success "ripgrep installed to: $installPath"
        if ($addToPath) {
            Write-Warning "PATH updated. Please restart your terminal/PowerShell for changes to take effect."
        }
        
        return $true
    }
    catch {
        Write-Error "Failed to install from GitHub: $($_.Exception.Message)"
        return $false
    }
}

# Test ripgrep installation
function Test-RipgrepInstallation {
    Write-Info "Testing ripgrep installation..."
    
    # Refresh PATH for current session
    $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", [EnvironmentVariableTarget]::Machine) + ";" + [System.Environment]::GetEnvironmentVariable("PATH", [EnvironmentVariableTarget]::User)
    
    try {
        $version = & rg --version 2>$null | Select-Object -First 1
        if ($version) {
            Write-Success "ripgrep is working correctly!"
            Write-Info "Version: $version"
            Write-Info "Magic-CLI will now use ripgrep for 10x+ faster search performance! 🚀"
            return $true
        }
    }
    catch {
        Write-Error "ripgrep installation failed or not working properly"
        Write-Info "You may need to restart your terminal/PowerShell and try running 'rg --version'"
        return $false
    }
}

# Main installation flow
function Install-Ripgrep {
    Write-Host "🔍 Magic-CLI Ripgrep Installer for Windows" -ForegroundColor Cyan
    Write-Host "=========================================" -ForegroundColor Cyan
    Write-Host ""
    
    # Check if already installed
    if ((Test-Ripgrep) -and (-not $Force)) {
        Write-Info "Magic-CLI is already optimized with ripgrep! 🚀"
        Write-Info "Use -Force parameter to reinstall if needed."
        return
    }
    
    Write-Info "Installing ripgrep for Magic-CLI performance boost..."
    
    # Try different installation methods in order of preference
    $installed = $false
    
    # Method 1: winget (most reliable for Windows 10/11)
    if (-not $installed) {
        $installed = Install-ViaWinget
    }
    
    # Method 2: Chocolatey
    if (-not $installed) {
        $installed = Install-ViaChocolatey
    }
    
    # Method 3: Scoop
    if (-not $installed) {
        $installed = Install-ViaScoop
    }
    
    # Method 4: Direct download from GitHub
    if (-not $installed) {
        $installed = Install-FromGitHub
    }
    
    if ($installed) {
        Test-RipgrepInstallation
        Write-Host ""
        Write-Success "🎉 Installation complete!"
        Write-Info "Magic-CLI will now automatically use ripgrep for faster search."
        Write-Info "No additional configuration needed - just run Magic-CLI as usual!"
        
        if (-not (Test-Administrator)) {
            Write-Warning "Note: You may need to restart your terminal/PowerShell for PATH changes to take effect."
        }
    } else {
        Write-Error "Failed to install ripgrep using all available methods."
        Write-Info "Please try installing manually:"
        Write-Info "1. Visit: https://github.com/BurntSushi/ripgrep/releases"
        Write-Info "2. Download the Windows binary"
        Write-Info "3. Add it to your PATH"
        Write-Info ""
        Write-Info "Or install via package manager:"
        Write-Info "- Chocolatey: choco install ripgrep"
        Write-Info "- Scoop: scoop install ripgrep"
        Write-Info "- winget: winget install BurntSushi.ripgrep"
    }
}

# Run the installer
Install-Ripgrep