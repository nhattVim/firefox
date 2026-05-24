# ==============================================================================
# Script: install_sidebar.ps1
# Description: Customization Toolkit for Firefox - Installs AutoConfig loader,
#              Second Sidebar, user.js, and custom chrome files with robust
#              multi-profile support and complete uninstallation logic.
# Author: nhattVim
# Language: English
# ==============================================================================

$ErrorActionPreference = "Stop"

# Helper function to check if Firefox is running and warn the user
function Check-FirefoxRunning {
    if (Get-Process firefox -ErrorAction SilentlyContinue) {
        Write-Host "[WARNING] Firefox is currently running!" -ForegroundColor Yellow
        Write-Host "Please close Firefox completely to avoid locked files, caching issues, or write failures." -ForegroundColor Yellow
        $choice = Read-Host "Have you closed Firefox? (Y to continue, N to cancel)"
        if ($choice -notmatch "^[yY]") {
            Write-Host "Operation cancelled by user." -ForegroundColor Red
            exit
        }
    }
}

# Helper function to download repositories safely with fallback branches (main/master)
function Download-GitHubRepo {
    param (
        [string]$repoUrl,
        [string]$outFile
    )
    $branches = @("main", "master")
    $success = $false
    
    foreach ($branch in $branches) {
        $zipUrl = "$repoUrl/archive/refs/heads/$branch.zip"
        try {
            Write-Host " -> Attempting to download from branch '$branch'..." -ForegroundColor Gray
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13
            Invoke-WebRequest -Uri $zipUrl -OutFile $outFile -ErrorAction Stop -TimeoutSec 30
            $success = $true
            break
        } catch {
            # Try the next branch
        }
    }
    
    if (-not $success) {
        throw "Failed to download from $repoUrl. Please check your network connection or Proxy!"
    }
}

# Helper function to detect Firefox Installation Directory ($ffDir)
function Get-FirefoxInstallDir {
    $ffDir = $null
    
    # 1. Detect from active process
    $ffProcess = Get-Process firefox -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($ffProcess) {
        $ffPath = $ffProcess.Path
        if ($ffPath) {
            $ffDir = Split-Path -Path $ffPath
            Write-Host " -> Detected Firefox directory from active process: $ffDir" -ForegroundColor Green
        }
    }
    
    # 2. Detect from Registry
    if (-not $ffDir) {
        $regPaths = @(
            "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\firefox.exe",
            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\firefox.exe"
        )
        foreach ($regPath in $regPaths) {
            if (Test-Path $regPath) {
                $ffPath = (Get-ItemProperty -Path $regPath -Name "(Default)" -ErrorAction SilentlyContinue)."(Default)"
                if ($ffPath) {
                    $ffDir = Split-Path -Path $ffPath
                    Write-Host " -> Detected Firefox directory from Registry: $ffDir" -ForegroundColor Green
                    break
                }
            }
        }
    }
    
    # 3. Check common installation directories (including Scoop)
    if (-not $ffDir) {
        $commonPaths = @(
            "$env:USERPROFILE\scoop\apps\firefox\current",
            "${env:ProgramFiles}\Mozilla Firefox",
            "${env:ProgramFiles(x86)}\Mozilla Firefox",
            "$env:LOCALAPPDATA\Mozilla Firefox"
        )
        foreach ($path in $commonPaths) {
            if (Test-Path "$path\firefox.exe") {
                $ffDir = $path
                Write-Host " -> Detected Firefox directory in common paths: $ffDir" -ForegroundColor Green
                break
            }
        }
    }
    
    if (-not $ffDir) {
        Write-Host "[WARNING] Could not automatically locate Firefox installation folder." -ForegroundColor Yellow
        $ffDir = Read-Host "Please enter the Firefox installation path manually (where firefox.exe is located)"
        $ffDir = $ffDir.Trim('"').Trim("'")
        if (-not (Test-Path "$ffDir\firefox.exe")) {
            throw "firefox.exe not found at specified directory: $ffDir"
        }
    }
    
    return $ffDir
}

# Helper function to discover all Firefox profiles
function Get-FirefoxProfiles {
    param (
        [string]$ffDir
    )
    $profiles = @()
    
    # 1. Discover local portable profiles (Scoop, PortableApps, etc.)
    $portablePaths = @(
        "$ffDir\profile",
        "$ffDir\Data\profile",
        "$ffDir\Data\Profiles"
    )
    foreach ($p in $portablePaths) {
        if (Test-Path $p) {
            $profiles += [PSCustomObject]@{
                Name = "Local Portable / Scoop Profile"
                Path = $p
                IsDefault = $true
            }
        }
    }
    
    # 2. Discover standard profiles from profiles.ini using robust parser
    $profilesIni = "$env:APPDATA\Mozilla\Firefox\profiles.ini"
    if (Test-Path $profilesIni) {
        $ini = Get-Content $profilesIni
        $sections = @()
        $current = @{}
        
        foreach ($line in $ini) {
            if ($line -match "^\[Profile") {
                if ($current.Count -gt 0) {
                    $sections += [PSCustomObject]$current
                }
                $current = @{}
            } elseif ($line -match "^[^=]+=") {
                $parts = $line.Split("=", 2)
                $current[$parts[0]] = $parts[1]
            }
        }
        if ($current.Count -gt 0) {
            $sections += [PSCustomObject]$current
        }
        
        foreach ($sec in $sections) {
            if ($sec.Path) {
                $relPath = $sec.Path.Replace("/", "\")
                $fullPath = $null
                if ($sec.IsRelative -eq "1") {
                    $fullPath = Join-Path -Path "$env:APPDATA\Mozilla\Firefox" -ChildPath $relPath
                } else {
                    $fullPath = $relPath
                }
                
                if (Test-Path $fullPath) {
                    $profiles += [PSCustomObject]@{
                        Name = $sec.Name
                        Path = $fullPath
                        IsDefault = ($sec.Default -eq "1")
                    }
                }
            }
        }
    }
    
    # 3. Check raw profiles directory if profiles.ini parser found nothing
    if ($profiles.Count -eq 0) {
        $profilesFolder = "$env:APPDATA\Mozilla\Firefox\Profiles"
        if (Test-Path $profilesFolder) {
            $subDirs = Get-ChildItem -Path $profilesFolder -Directory
            foreach ($dir in $subDirs) {
                $profiles += [PSCustomObject]@{
                    Name = $dir.Name
                    Path = $dir.FullName
                    IsDefault = ($dir.Name -like "*.default*")
                }
            }
        }
    }
    
    return $profiles
}

# Helper function to check write permissions
function Test-WritePermission {
    param([string]$path)
    if (-not (Test-Path $path)) { return $false }
    try {
        $testFile = Join-Path $path "permtest_$([Guid]::NewGuid().Guid).tmp"
        [System.IO.File]::WriteAllText($testFile, "test")
        Remove-Item $testFile -ErrorAction SilentlyContinue
        return $true
    } catch {
        return $false
    }
}

# Helper function to prompt user to choose a profile
function Choose-Profile {
    param (
        [array]$profiles
    )
    
    Write-Host "`nDiscovered Firefox Profiles:" -ForegroundColor Yellow
    for ($i = 0; $i -lt $profiles.Count; $i++) {
        $p = $profiles[$i]
        $prefix = "[$($i+1)]"
        $defaultTag = if ($p.IsDefault) { " (Active Default)" } else { "" }
        Write-Host "  $prefix Profile '$($p.Name)'$defaultTag" -ForegroundColor Gray
        Write-Host "      Path: $($p.Path)" -ForegroundColor DarkGray
    }
    Write-Host "  [$($profiles.Count + 1)] Enter a custom profile path..." -ForegroundColor Gray
    
    $selection = $null
    while ($null -eq $selection) {
        $inputVal = Read-Host "`nSelect a profile folder (1-$($profiles.Count + 1))"
        if ($inputVal -match "^\d+$") {
            $index = [int]$inputVal - 1
            if ($index -ge 0 -and $index -lt $profiles.Count) {
                $selection = $profiles[$index].Path
            } elseif ($index -eq $profiles.Count) {
                $customPath = Read-Host "Please enter the custom profile path manually"
                $customPath = $customPath.Trim('"').Trim("'")
                if (Test-Path $customPath) {
                    $selection = $customPath
                } else {
                    Write-Host "[ERROR] Directory does not exist: $customPath" -ForegroundColor Red
                }
            }
        }
        if ($null -eq $selection) {
            Write-Host "Invalid selection. Please try again." -ForegroundColor Red
        }
    }
    
    Write-Host "`n-> Selected Profile Path: $selection" -ForegroundColor Green
    return $selection
}

# ==============================================================================
# MENU & DISPATCH
# ==============================================================================

Clear-Host
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "        FIREFOX CUSTOMIZATION TOOLKIT (ENGLISH)           " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host " 1. Install Customizations (Autoconfig, Sidebar, user.js & chrome)" -ForegroundColor Gray
Write-Host " 2. Uninstall Customizations (Restore Firefox to original state)" -ForegroundColor Gray
Write-Host " 3. Exit" -ForegroundColor Gray
Write-Host "==========================================================" -ForegroundColor Cyan

$menuChoice = $null
while ($menuChoice -notmatch "^[1-3]$") {
    $menuChoice = Read-Host "Enter your choice (1-3)"
}

if ($menuChoice -eq "3") {
    Write-Host "Exiting." -ForegroundColor Yellow
    exit
}

# Warn user if Firefox is open
Check-FirefoxRunning

# Detect installation folder
$ffDir = Get-FirefoxInstallDir
$ffDir = $ffDir.TrimEnd('\')

# Detect and choose profile
$profiles = Get-FirefoxProfiles -ffDir $ffDir
if ($profiles.Count -eq 0) {
    Write-Host "[WARNING] No Firefox profiles discovered automatically." -ForegroundColor Yellow
    $profileDir = Read-Host "Please enter your profile path manually"
    $profileDir = $profileDir.Trim('"').Trim("'").TrimEnd('\')
    if (-not (Test-Path $profileDir)) {
        throw "Specified profile folder does not exist: $profileDir"
    }
} else {
    $profileDir = Choose-Profile -profiles $profiles
    $profileDir = $profileDir.TrimEnd('\')
}

# Check Admin permissions if writing/deleting in $ffDir requires it
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin -and -not (Test-WritePermission $ffDir)) {
    Write-Host "`n[INFO] Write access to Firefox installation directory ($ffDir) is protected." -ForegroundColor Yellow
    Write-Host "Self-elevating to Administrator..." -ForegroundColor Yellow
    Start-Sleep -Seconds 1
    
    $args = "-NoProfile -ExecutionPolicy Bypass"
    if ($PSCommandPath) {
        $args += " -File `"$PSCommandPath`""
    } else {
        # Running via iex
        $args += " -Command `"irm https://raw.githubusercontent.com/nhattVim/firefox/refs/heads/main/install.ps1 | iex`""
    }
    Start-Process powershell -ArgumentList $args -Verb RunAs
    exit
}

$chromeDir = Join-Path -Path $profileDir -ChildPath "chrome"

# ------------------------------------------------------------------------------
# OPTION 1: INSTALL CUSTOMIZATIONS
# ------------------------------------------------------------------------------
if ($menuChoice -eq "1") {
    Write-Host "`n==========================================================" -ForegroundColor Cyan
    Write-Host "               PERFORMING INSTALLATION...                 " -ForegroundColor Cyan
    Write-Host "==========================================================" -ForegroundColor Cyan

    # Ensure chrome dir exists
    if (-not (Test-Path $chromeDir)) {
        New-Item -ItemType Directory -Path $chromeDir | Out-Null
    }

    # Setup temp workspace inside chrome folder
    $tempDir = Join-Path -Path $chromeDir -ChildPath "temp_install"
    if (Test-Path $tempDir) {
        Remove-Item -Path $tempDir -Recurse -Force
    }
    New-Item -ItemType Directory -Path $tempDir | Out-Null

    # 1. Download & Deploy fx-autoconfig
    Write-Host "`n[1/4] Installing AutoConfig script loader (fx-autoconfig)..." -ForegroundColor Yellow
    $autoconfigZip = Join-Path -Path $tempDir -ChildPath "autoconfig.zip"
    $autoconfigExtract = Join-Path -Path $tempDir -ChildPath "autoconfig_extracted"

    try {
        Download-GitHubRepo -repoUrl "https://github.com/MrOtherGuy/fx-autoconfig" -outFile $autoconfigZip
        Expand-Archive -Path $autoconfigZip -DestinationPath $autoconfigExtract -Force
    } catch {
        Remove-Item -Path $tempDir -Recurse -Force
        throw "Failed to download or extract fx-autoconfig: $_"
    }

    $extractedRoot = Get-ChildItem -Path $autoconfigExtract -Directory | Select-Object -First 1
    $extractedPath = $extractedRoot.FullName

    # Copy program files
    Copy-Item -Path "$extractedPath\program\config.js" -Destination "$ffDir\config.js" -Force
    
    $prefDestDir = "$ffDir\defaults\pref"
    if (-not (Test-Path $prefDestDir)) {
        New-Item -ItemType Directory -Path $prefDestDir | Out-Null
    }
    Copy-Item -Path "$extractedPath\program\defaults\pref\config-prefs.js" -Destination "$prefDestDir\config-prefs.js" -Force

    # Copy utils into chrome/utils/
    $utilsDestDir = Join-Path -Path $chromeDir -ChildPath "utils"
    if (-not (Test-Path $utilsDestDir)) {
        New-Item -ItemType Directory -Path $utilsDestDir | Out-Null
    }
    Copy-Item -Path "$extractedPath\profile\chrome\utils\*" -Destination $utilsDestDir -Recurse -Force
    Write-Host "    -> Installed AutoConfig loader successfully." -ForegroundColor Green

    # 2. Download & Deploy firefox-second-sidebar
    Write-Host "`n[2/4] Installing firefox-second-sidebar..." -ForegroundColor Yellow
    $sidebarZip = Join-Path -Path $tempDir -ChildPath "sidebar.zip"
    $sidebarExtract = Join-Path -Path $tempDir -ChildPath "sidebar_extracted"

    try {
        Download-GitHubRepo -repoUrl "https://github.com/aminought/firefox-second-sidebar" -outFile $sidebarZip
        Expand-Archive -Path $sidebarZip -DestinationPath $sidebarExtract -Force
    } catch {
        Remove-Item -Path $tempDir -Recurse -Force
        throw "Failed to download or extract firefox-second-sidebar: $_"
    }

    $sidebarRoot = Get-ChildItem -Path $sidebarExtract -Directory | Select-Object -First 1
    $sidebarSrcPath = Join-Path -Path $sidebarRoot.FullName -ChildPath "src"

    # Ensure JS folder exists
    $jsDestDir = Join-Path -Path $chromeDir -ChildPath "JS"
    if (-not (Test-Path $jsDestDir)) {
        New-Item -ItemType Directory -Path $jsDestDir | Out-Null
    }

    # Copy files into chrome/JS/
    Copy-Item -Path "$sidebarSrcPath\second_sidebar.uc.mjs" -Destination "$jsDestDir\second_sidebar.uc.mjs" -Force
    Copy-Item -Path "$sidebarSrcPath\second_sidebar" -Destination $jsDestDir -Recurse -Force
    Write-Host "    -> Installed firefox-second-sidebar into chrome\JS\ successfully." -ForegroundColor Green

    # 3. Download & Deploy custom chrome and user.js from nhattVim/firefox
    Write-Host "`n[3/4] Fetching custom chrome and user.js from nhattVim/firefox..." -ForegroundColor Yellow
    $nhattZip = Join-Path -Path $tempDir -ChildPath "nhatt.zip"
    $nhattExtract = Join-Path -Path $tempDir -ChildPath "nhatt_extracted"

    try {
        Download-GitHubRepo -repoUrl "https://github.com/nhattVim/firefox" -outFile $nhattZip
        Expand-Archive -Path $nhattZip -DestinationPath $nhattExtract -Force
    } catch {
        Remove-Item -Path $tempDir -Recurse -Force
        throw "Failed to download or extract from nhattVim/firefox: $_"
    }

    $nhattRoot = Get-ChildItem -Path $nhattExtract -Directory | Select-Object -First 1
    $nhattPath = $nhattRoot.FullName

    # Copy user.js to profile root
    if (Test-Path "$nhattPath\src\user.js") {
        Copy-Item -Path "$nhattPath\src\user.js" -Destination "$profileDir\user.js" -Force
        Write-Host "    -> Deployed user.js to profile root folder." -ForegroundColor Green
    }

    # Copy blurNewTabUrlbar.uc.mjs to chrome/JS/ folder
    if (Test-Path "$nhattPath\src\blurNewTabUrlbar.uc.mjs") {
        Copy-Item -Path "$nhattPath\src\blurNewTabUrlbar.uc.mjs" -Destination $jsDestDir -Force
        Write-Host "    -> Deployed blurNewTabUrlbar.uc.mjs to chrome\JS\ successfully." -ForegroundColor Green
    }

    # Copy custom chrome contents to profile chrome/ folder
    if (Test-Path "$nhattPath\chrome") {
        Copy-Item -Path "$nhattPath\chrome\*" -Destination $chromeDir -Recurse -Force
        Write-Host "    -> Merged custom chrome files into profile chrome directory." -ForegroundColor Green
    }

    # 4. Cleanup & Cache Clear
    Write-Host "`n[4/4] Cleaning up temporary files and clearing startup cache..." -ForegroundColor Yellow
    Remove-Item -Path $tempDir -Recurse -Force
    Write-Host "    -> Cleaned up temp workspace." -ForegroundColor Green
    
    $startupCache = Join-Path $profileDir "startupCache"
    if (Test-Path $startupCache) {
        Remove-Item $startupCache -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "    -> Cleared Firefox startup cache automatically." -ForegroundColor Green
    }

    # SUCCESS MESSAGE
    Write-Host "`n==========================================================" -ForegroundColor Cyan
    Write-Host "            INSTALLATION COMPLETED SUCCESSFULLY!          " -ForegroundColor Green
    Write-Host "==========================================================" -ForegroundColor Cyan
    Write-Host "Next steps to activate your customizations:" -ForegroundColor Yellow
    Write-Host "1. Launch Firefox."
    Write-Host "2. Your persistent custom sidebar will be active immediately!"
    Write-Host "3. Click the '+' button in the sidebar dock to add Zalo, Messenger, etc."
    Write-Host "==========================================================" -ForegroundColor Cyan
}

# ------------------------------------------------------------------------------
# OPTION 2: UNINSTALL CUSTOMIZATIONS
# ------------------------------------------------------------------------------
elseif ($menuChoice -eq "2") {
    Write-Host "`n==========================================================" -ForegroundColor Cyan
    Write-Host "              PERFORMING UNINSTALLATION...                " -ForegroundColor Cyan
    Write-Host "==========================================================" -ForegroundColor Cyan

    # 1. Remove AutoConfig program files
    Write-Host "[1/3] Removing AutoConfig loader files..." -ForegroundColor Yellow
    $filesToRemove = @(
        "$ffDir\config.js",
        "$ffDir\defaults\pref\config-prefs.js"
    )
    foreach ($file in $filesToRemove) {
        if (Test-Path $file) {
            Remove-Item -Path $file -Force
            Write-Host "    -> Removed: $file" -ForegroundColor Gray
        }
    }

    # 2. Remove profile custom files
    Write-Host "`n[2/3] Removing custom profile modifications..." -ForegroundColor Yellow
    
    # Remove user.js
    $userJsFile = "$profileDir\user.js"
    if (Test-Path $userJsFile) {
        Remove-Item -Path $userJsFile -Force
        Write-Host "    -> Removed: $userJsFile" -ForegroundColor Gray
    }

    # Remove chrome/utils/ folder
    $utilsDir = Join-Path -Path $chromeDir -ChildPath "utils"
    if (Test-Path $utilsDir) {
        Remove-Item -Path $utilsDir -Recurse -Force
        Write-Host "    -> Removed: $utilsDir" -ForegroundColor Gray
    }

    # Remove chrome/components/ folder (created by the split layout tool)
    $componentsDir = Join-Path -Path $chromeDir -ChildPath "components"
    if (Test-Path $componentsDir) {
        Remove-Item -Path $componentsDir -Recurse -Force
        Write-Host "    -> Removed: $componentsDir" -ForegroundColor Gray
    }

    # Remove chrome/icons/ folder
    $iconsDir = Join-Path -Path $chromeDir -ChildPath "icons"
    if (Test-Path $iconsDir) {
        Remove-Item -Path $iconsDir -Recurse -Force
        Write-Host "    -> Removed: $iconsDir" -ForegroundColor Gray
    }

    # Remove chrome/imgs/ folder
    $imgsDir = Join-Path -Path $chromeDir -ChildPath "imgs"
    if (Test-Path $imgsDir) {
        Remove-Item -Path $imgsDir -Recurse -Force
        Write-Host "    -> Removed: $imgsDir" -ForegroundColor Gray
    }

    # Remove userChrome.css and userContent.css if they exist
    $userChromeFile = Join-Path -Path $chromeDir -ChildPath "userChrome.css"
    if (Test-Path $userChromeFile) {
        Remove-Item -Path $userChromeFile -Force
        Write-Host "    -> Removed: $userChromeFile" -ForegroundColor Gray
    }
    $userContentFile = Join-Path -Path $chromeDir -ChildPath "userContent.css"
    if (Test-Path $userContentFile) {
        Remove-Item -Path $userContentFile -Force
        Write-Host "    -> Removed: $userContentFile" -ForegroundColor Gray
    }

    # Remove specific JS files and directories in chrome/JS/
    $jsDir = Join-Path -Path $chromeDir -ChildPath "JS"
    if (Test-Path $jsDir) {
        $filesToRemove = @(
            "second_sidebar.uc.mjs",
            "blurNewTabUrlbar.uc.mjs",
            "blurNewTabUrlbar.uc.js"
        )
        foreach ($file in $filesToRemove) {
            $filePath = Join-Path -Path $jsDir -ChildPath $file
            if (Test-Path $filePath) {
                Remove-Item -Path $filePath -Force
                Write-Host "    -> Removed: $filePath" -ForegroundColor Gray
            }
        }
        
        $sidebarDir = Join-Path -Path $jsDir -ChildPath "second_sidebar"
        if (Test-Path $sidebarDir) {
            Remove-Item -Path $sidebarDir -Recurse -Force
            Write-Host "    -> Removed: $sidebarDir" -ForegroundColor Gray
        }

        # If chrome/JS/ is empty, remove it too
        $jsContents = Get-ChildItem -Path $jsDir
        if ($null -eq $jsContents -or $jsContents.Count -eq 0) {
            Remove-Item -Path $jsDir -Force
            Write-Host "    -> Removed empty JS folder: $jsDir" -ForegroundColor Gray
        }
    }

    # 3. Clear startup cache automatically
    Write-Host "`n[3/3] Finalizing uninstallation..." -ForegroundColor Yellow
    $startupCache = Join-Path $profileDir "startupCache"
    if (Test-Path $startupCache) {
        Remove-Item $startupCache -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "    -> Cleared Firefox startup cache automatically." -ForegroundColor Green
    }
    Write-Host "    -> Customizations successfully removed." -ForegroundColor Green

    # SUCCESS MESSAGE
    Write-Host "`n==========================================================" -ForegroundColor Cyan
    Write-Host "           UNINSTALLATION COMPLETED SUCCESSFULLY!         " -ForegroundColor Green
    Write-Host "==========================================================" -ForegroundColor Cyan
    Write-Host "To fully restore your browser state:" -ForegroundColor Yellow
    Write-Host "1. Launch Firefox."
    Write-Host "2. Firefox will restart, completely clean and restored to original."
    Write-Host "==========================================================" -ForegroundColor Cyan
}
