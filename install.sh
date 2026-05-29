#!/bin/bash
# ==============================================================================
# Script: install.sh
# Description: Customization Toolkit for Firefox - Installs AutoConfig loader,
#              Second Sidebar, user.js, and custom chrome files with robust
#              multi-profile support and complete uninstallation logic.
# Author: nhattVim
# Language: English
# ==============================================================================

set -e

# Helper function to check if Firefox is running and warn the user
check_firefox_running() {
    local running=false
    if [[ "$OSTYPE" == "darwin"* ]]; then
        if pgrep -x "firefox" >/dev/null || pgrep -f "Firefox.app" >/dev/null; then
            running=true
        fi
    else
        if pgrep -x "firefox" >/dev/null || pgrep -x "firefox-bin" >/dev/null; then
            running=true
        fi
    fi

    if [ "$running" = true ]; then
        echo -e "\033[1;33m[WARNING] Firefox is currently running!\033[0m"
        echo -e "\033[1;33mPlease close Firefox completely to avoid locked files, caching issues, or write failures.\033[0m"
        read -p "Have you closed Firefox? (Y to continue, N to cancel): " choice
        if [[ ! "$choice" =~ ^[yY] ]]; then
            echo -e "\033[1;31mOperation cancelled by user.\033[0m"
            exit 1
        fi
    fi
}

# Helper function to check if utility is installed
check_requirements() {
    if ! command -v unzip >/dev/null 2>&1; then
        echo -e "\033[1;31m[ERROR] 'unzip' utility is not installed. Please install 'unzip' and try again.\033[0m" >&2
        exit 1
    fi
}

# Helper function to download repositories safely with checkout branches
download_github_repo() {
    local repo_url="$1"
    local out_file="$2"

    local api_url
    api_url=$(echo "$repo_url" | sed 's#https://github.com/#https://api.github.com/repos/#')

    local default_branch=""

    echo " -> Detecting default branch from GitHub API..."

    if command -v curl >/dev/null 2>&1; then
        default_branch=$(curl -fsSL "$api_url" | grep '"default_branch"' | cut -d '"' -f4)
    elif command -v wget >/dev/null 2>&1; then
        default_branch=$(wget -qO- "$api_url" | grep '"default_branch"' | cut -d '"' -f4)
    else
        echo -e "\033[1;31m[ERROR] Neither curl nor wget is installed.\033[0m" >&2
        exit 1
    fi

    # fallback if API fail
    if [[ -z "$default_branch" ]]; then
        echo " -> Could not detect default branch automatically. Falling back to main/master..."
        for branch in main master; do
            echo " -> Attempting branch '$branch'..."
            local zip_url="${repo_url}/archive/refs/heads/${branch}.zip"

            if command -v curl >/dev/null 2>&1; then
                if curl -fsSL -o "$out_file" "$zip_url"; then
                    return 0
                fi
            else
                if wget -q -O "$out_file" "$zip_url"; then
                    return 0
                fi
            fi
        done

        echo -e "\033[1;31m[ERROR] Failed to download repository.\033[0m" >&2
        exit 1
    fi

    echo " -> Default branch detected: $default_branch"

    local zip_url="${repo_url}/archive/refs/heads/${default_branch}.zip"

    if command -v curl >/dev/null 2>&1; then
        curl -fsSL -o "$out_file" "$zip_url"
    else
        wget -q -O "$out_file" "$zip_url"
    fi
}

# Helper function to detect Firefox Installation Directory
get_firefox_install_dir() {
    local ff_dir=""

    # 1. Detect from OS
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS standard path
        local mac_path="/Applications/Firefox.app/Contents/Resources"
        if [[ -d "$mac_path" ]]; then
            ff_dir="$mac_path"
            echo " -> Detected Firefox directory on macOS: $ff_dir" >&2
        fi
    else
        # Linux standard paths
        local linux_paths=(
            "/usr/lib/firefox"
            "/usr/lib64/firefox"
            "/usr/share/firefox"
            "/opt/firefox"
            "/usr/local/lib/firefox"
        )
        for p in "${linux_paths[@]}"; do
            if [[ -d "$p" ]]; then
                ff_dir="$p"
                echo " -> Detected Firefox directory on Linux: $ff_dir" >&2
                break
            fi
        done
    fi

    if [[ -z "$ff_dir" ]]; then
        echo -e "\033[1;33m[WARNING] Could not automatically locate Firefox installation folder.\033[0m" >&2
        read -p "Please enter the Firefox installation path manually (where config.js should be placed): " ff_dir </dev/tty
        ff_dir="${ff_dir%\"}"
        ff_dir="${ff_dir#\"}"
        ff_dir="${ff_dir%\'}"
        ff_dir="${ff_dir#\'}"
        ff_dir="${ff_dir%/}"
        if [[ ! -d "$ff_dir" ]]; then
            echo -e "\033[1;31m[ERROR] Directory does not exist: $ff_dir\033[0m" >&2
            exit 1
        fi
    fi

    echo "$ff_dir"
}

# Helper function to check/create directory with sudo if necessary
mkdir_install_dir() {
    local dir="$1"
    if [[ -d "$dir" ]]; then
        return
    fi
    if [[ -w "$(dirname "$dir")" || -w "$dir" ]]; then
        mkdir -p "$dir"
    else
        echo " -> Creating directory $dir requires administrator privileges (sudo)..."
        sudo mkdir -p "$dir"
    fi
}

# Helper function to copy file with sudo if necessary
copy_to_install_dir() {
    local src="$1"
    local dest="$2"
    if [[ -w "$(dirname "$dest")" || -w "$dest" ]]; then
        cp -f "$src" "$dest"
    else
        echo " -> Copying to $dest requires administrator privileges (sudo)..."
        sudo cp -f "$src" "$dest"
    fi
}

# Helper function to discover and choose Firefox Profile
choose_profile() {
    local ff_dir="$1"
    local firefox_data_dir=""
    local profiles_ini=""

    if [[ "$OSTYPE" == "darwin"* ]]; then
        firefox_data_dir="$HOME/Library/Application Support/Firefox"
    else
        # Linux standard & Flatpak support
        if [[ -d "$HOME/.mozilla/firefox" ]]; then
            firefox_data_dir="$HOME/.mozilla/firefox"
        elif [[ -d "$HOME/.config/mozilla/firefox" ]]; then
            firefox_data_dir="$HOME/.config/mozilla/firefox"
        elif [[ -d "$HOME/.var/app/org.mozilla.firefox/.mozilla/firefox" ]]; then
            firefox_data_dir="$HOME/.var/app/org.mozilla.firefox/.mozilla/firefox"
        fi
    fi

    if [[ -z "$firefox_data_dir" ]]; then
        echo -e "\033[1;33m[WARNING] Could not automatically locate Firefox profile folder.\033[0m" >&2
        read -p "Please enter your profile path manually: " profile_dir </dev/tty
        profile_dir="${profile_dir%\"}"
        profile_dir="${profile_dir#\"}"
        profile_dir="${profile_dir%\'}"
        profile_dir="${profile_dir#\'}"
        profile_dir="${profile_dir%/}"
        if [[ ! -d "$profile_dir" ]]; then
            echo -e "\033[1;31m[ERROR] Directory does not exist: $profile_dir\033[0m" >&2
            exit 1
        fi
        echo "$profile_dir"
        return
    fi

    profiles_ini="$firefox_data_dir/profiles.ini"

    local names=()
    local paths=()
    local is_defaults=()

    # 1. Discover local portable profiles
    if [[ -d "$ff_dir/profile" ]]; then
        names+=("Local Portable / Scoop Profile")
        paths+=("$ff_dir/profile")
        is_defaults+=("1")
    elif [[ -d "$ff_dir/Data/profile" ]]; then
        names+=("Local Portable / Scoop Profile")
        paths+=("$ff_dir/Data/profile")
        is_defaults+=("1")
    fi

    # 2. Parse profiles.ini
    if [[ -f "$profiles_ini" ]]; then
        local current_name=""
        local current_path=""
        local current_is_relative=""
        local current_default=""

        while IFS= read -r line || [[ -n "$line" ]]; do
            line=$(echo "$line" | tr -d '\r' | xargs)
            if [[ "$line" =~ ^\[Profile ]]; then
                if [[ -n "$current_name" && -n "$current_path" ]]; then
                    names+=("$current_name")
                    if [[ "$current_is_relative" == "1" ]]; then
                        paths+=("$firefox_data_dir/$current_path")
                    else
                        paths+=("$current_path")
                    fi
                    is_defaults+=("$current_default")
                fi
                current_name=""
                current_path=""
                current_is_relative=""
                current_default=""
            elif [[ "$line" =~ ^Name= ]]; then
                current_name="${line#Name=}"
            elif [[ "$line" =~ ^Path= ]]; then
                current_path="${line#Path=}"
            elif [[ "$line" =~ ^IsRelative= ]]; then
                current_is_relative="${line#IsRelative=}"
            elif [[ "$line" =~ ^Default= ]]; then
                current_default="${line#Default=}"
            fi
        done <"$profiles_ini"

        # Add last section
        if [[ -n "$current_name" && -n "$current_path" ]]; then
            names+=("$current_name")
            if [[ "$current_is_relative" == "1" ]]; then
                paths+=("$firefox_data_dir/$current_path")
            else
                paths+=("$current_path")
            fi
            is_defaults+=("$current_default")
        fi
    fi

    # 3. Fallback: Check Profiles directory directly if parsing profiles.ini yielded nothing
    if [[ ${#names[@]} -eq 0 ]]; then
        local profiles_folder="$firefox_data_dir/Profiles"
        if [[ -d "$profiles_folder" ]]; then
            for d in "$profiles_folder"/*; do
                if [[ -d "$d" ]]; then
                    local dirname
                    dirname=$(basename "$d")
                    names+=("$dirname")
                    paths+=("$d")
                    if [[ "$dirname" == *".default"* ]]; then
                        is_defaults+=("1")
                    else
                        is_defaults+=("0")
                    fi
                fi
            done
        fi
    fi

    if [[ ${#names[@]} -eq 0 ]]; then
        echo -e "\033[1;33m[WARNING] No Firefox profiles discovered automatically.\033[0m" >&2
        read -p "Please enter your profile path manually: " profile_dir </dev/tty
        profile_dir="${profile_dir%\"}"
        profile_dir="${profile_dir#\"}"
        profile_dir="${profile_dir%\'}"
        profile_dir="${profile_dir#\'}"
        profile_dir="${profile_dir%/}"
        if [[ ! -d "$profile_dir" ]]; then
            echo -e "\033[1;31m[ERROR] Directory does not exist: $profile_dir\033[0m" >&2
            exit 1
        fi
        echo "$profile_dir"
        return
    fi

    echo -e "\nDiscovered Firefox Profiles:" >&2
    for i in "${!names[@]}"; do
        local def_tag=""
        if [[ "${is_defaults[$i]}" == "1" ]]; then
            def_tag=" (Active Default)"
        fi
        echo -e "  [$((i + 1))] Profile '${names[$i]}'$def_tag" >&2
        echo -e "      Path: ${paths[$i]}" >&2
    done
    echo -e "  [$((${#names[@]} + 1))] Enter a custom profile path..." >&2

    local selection=""
    while [[ -z "$selection" ]]; do
        read -p "Select a profile folder (1-$((${#names[@]} + 1))): " input_val </dev/tty
        if [[ "$input_val" =~ ^[0-9]+$ ]]; then
            local idx=$((input_val - 1))
            if [[ $idx -ge 0 && $idx -lt ${#names[@]} ]]; then
                selection="${paths[$idx]}"
            elif [[ $idx -eq ${#names[@]} ]]; then
                read -p "Please enter the custom profile path manually: " custom_path </dev/tty
                custom_path="${custom_path%\"}"
                custom_path="${custom_path#\"}"
                custom_path="${custom_path%\'}"
                custom_path="${custom_path#\'}"
                custom_path="${custom_path%/}"
                if [[ -d "$custom_path" ]]; then
                    selection="$custom_path"
                else
                    echo -e "\033[1;31m[ERROR] Directory does not exist: $custom_path\033[0m" >&2
                fi
            fi
        fi
        if [[ -z "$selection" ]]; then
            echo -e "\033[1;31mInvalid selection. Please try again.\033[0m" >&2
        fi
    done

    echo -e "\n-> Selected Profile Path: $selection" >&2
    echo "$selection"
}

# ==============================================================================
# MAIN PROGRAM
# ==============================================================================

clear
echo "=========================================================="
echo "        FIREFOX CUSTOMIZATION TOOLKIT (UNIX)              "
echo "=========================================================="
echo " 1. Install Customizations (Autoconfig, Sidebar, user.js & chrome)"
echo " 2. Uninstall Customizations (Restore Firefox to original state)"
echo " 3. Exit"
echo "=========================================================="

menu_choice=""
while [[ ! "$menu_choice" =~ ^[1-3]$ ]]; do
    read -p "Enter your choice (1-3): " menu_choice </dev/tty
done

if [ "$menu_choice" = "3" ]; then
    echo "Exiting."
    exit 0
fi

# Requirements & processes check
check_requirements
check_firefox_running

# Detect installation folder
ffDir=$(get_firefox_install_dir | tail -n 1)
ffDir="${ffDir%/}"

# Detect and choose profile
profileDir=$(choose_profile "$ffDir" | tail -n 1)
profileDir="${profileDir%/}"
chromeDir="${profileDir}/chrome"

# ------------------------------------------------------------------------------
# OPTION 1: INSTALL CUSTOMIZATIONS
# ------------------------------------------------------------------------------
if [ "$menu_choice" = "1" ]; then
    echo -e "\n=========================================================="
    echo "               PERFORMING INSTALLATION...                 "
    echo "=========================================================="

    # Ensure chrome dir exists
    mkdir -p "$chromeDir"

    # Setup temp workspace
    tempDir="${chromeDir}/temp_install"
    if [ -d "$tempDir" ]; then
        rm -rf "$tempDir"
    fi
    mkdir -p "$tempDir"

    # 1. Download & Deploy fx-autoconfig
    echo -e "\n[1/4] Installing AutoConfig script loader (fx-autoconfig)..."
    autoconfigZip="${tempDir}/autoconfig.zip"
    autoconfigExtract="${tempDir}/autoconfig_extracted"
    mkdir -p "$autoconfigExtract"

    if ! download_github_repo "https://github.com/MrOtherGuy/fx-autoconfig" "$autoconfigZip"; then
        rm -rf "$tempDir"
        echo "[ERROR] Failed to download fx-autoconfig" >&2
        exit 1
    fi
    unzip -q -o "$autoconfigZip" -d "$autoconfigExtract"

    extractedRoot=$(find "$autoconfigExtract" -maxdepth 1 -mindepth 1 -type d | head -n 1)

    # Copy program files
    mkdir_install_dir "$ffDir/defaults/pref"
    copy_to_install_dir "$extractedRoot/program/config.js" "$ffDir/config.js"
    copy_to_install_dir "$extractedRoot/program/defaults/pref/config-prefs.js" "$ffDir/defaults/pref/config-prefs.js"

    # Copy utils into chrome/utils/
    mkdir -p "$chromeDir/utils"
    cp -rf "$extractedRoot"/profile/chrome/utils/* "$chromeDir/utils/"
    echo "    -> Installed AutoConfig loader successfully."

    # 2. Download & Deploy firefox-second-sidebar
    echo -e "\n[2/4] Installing firefox-second-sidebar..."
    sidebarZip="${tempDir}/sidebar.zip"
    sidebarExtract="${tempDir}/sidebar_extracted"
    mkdir -p "$sidebarExtract"

    if ! download_github_repo "https://github.com/aminought/firefox-second-sidebar" "$sidebarZip"; then
        rm -rf "$tempDir"
        echo "[ERROR] Failed to download firefox-second-sidebar" >&2
        exit 1
    fi
    unzip -q -o "$sidebarZip" -d "$sidebarExtract"

    sidebarRoot=$(find "$sidebarExtract" -maxdepth 1 -mindepth 1 -type d | head -n 1)
    sidebarSrcPath="${sidebarRoot}/src"

    # Ensure JS folder exists
    mkdir -p "$chromeDir/JS"

    # Copy files into chrome/JS/
    cp -f "$sidebarSrcPath/second_sidebar.uc.mjs" "$chromeDir/JS/second_sidebar.uc.mjs"
    cp -rf "$sidebarSrcPath/second_sidebar" "$chromeDir/JS/"
    echo "    -> Installed firefox-second-sidebar into chrome/JS/ successfully."

    # 3. Download & Deploy custom chrome and user.js from nhattVim/firefox
    echo -e "\n[3/4] Fetching custom chrome and user.js from nhattVim/firefox..."
    nhattZip="${tempDir}/nhatt.zip"
    nhattExtract="${tempDir}/nhatt_extracted"
    mkdir -p "$nhattExtract"

    if ! download_github_repo "https://github.com/nhattVim/firefox" "$nhattZip"; then
        rm -rf "$tempDir"
        echo "[ERROR] Failed to download custom configurations from nhattVim/firefox" >&2
        exit 1
    fi
    unzip -q -o "$nhattZip" -d "$nhattExtract"

    nhattRoot=$(find "$nhattExtract" -maxdepth 1 -mindepth 1 -type d | head -n 1)

    # Copy user.js to profile root
    if [ -f "$nhattRoot/src/user.js" ]; then
        cp -f "$nhattRoot/src/user.js" "$profileDir/user.js"
        echo "    -> Deployed user.js to profile root folder."
    fi

    # Copy blurNewTabUrlbar.uc.mjs to chrome/JS/
    if [ -f "$nhattRoot/src/blurNewTabUrlbar.uc.mjs" ]; then
        cp -f "$nhattRoot/src/blurNewTabUrlbar.uc.mjs" "$chromeDir/JS/blurNewTabUrlbar.uc.mjs"
        echo "    -> Deployed blurNewTabUrlbar.uc.mjs to chrome/JS/ successfully."
    fi

    # Copy custom chrome contents to profile chrome/ folder
    if [ -d "$nhattRoot/chrome" ]; then
        cp -rf "$nhattRoot"/chrome/* "$chromeDir/"
        echo "    -> Merged custom chrome files into profile chrome directory."
    fi

    # 4. Cleanup & Cache Clear
    echo -e "\n[4/4] Cleaning up temporary installation files and clearing startup cache..."
    rm -rf "$tempDir"
    echo "    -> Cleaned up temp workspace."

    startupCache="${profileDir}/startupCache"
    if [ -d "$startupCache" ]; then
        rm -rf "$startupCache"
        echo "    -> Cleared Firefox startup cache automatically."
    fi

    # SUCCESS MESSAGE
    echo "=========================================================="
    echo -e "\033[1;32m         INSTALLATION COMPLETED SUCCESSFULLY!           \033[0m"
    echo "=========================================================="
    echo "Next steps to activate your customizations:"
    echo "1. Launch Firefox."
    echo "2. Your persistent custom sidebar will be active immediately!"
    echo "3. Click the '+' button in the sidebar dock to add Zalo, Messenger, etc."
    echo "=========================================================="
fi

# ------------------------------------------------------------------------------
# OPTION 2: UNINSTALL CUSTOMIZATIONS
# ------------------------------------------------------------------------------
if [ "$menu_choice" = "2" ]; then
    echo -e "\n=========================================================="
    echo "              PERFORMING UNINSTALLATION...                "
    echo "=========================================================="

    # 1. Remove AutoConfig program files
    echo "[1/3] Removing AutoConfig loader files..."
    filesToRemove=(
        "$ffDir/config.js"
        "$ffDir/defaults/pref/config-prefs.js"
    )
    for file in "${filesToRemove[@]}"; do
        if [ -f "$file" ]; then
            if [ -w "$file" ]; then
                rm -f "$file"
            else
                echo " -> Removing $file requires administrator privileges (sudo)..."
                sudo rm -f "$file"
            fi
            echo "    -> Removed: $file"
        fi
    done

    # 2. Remove profile custom files
    echo -e "\n[2/3] Removing custom profile modifications..."

    # Remove user.js
    if [ -f "$profileDir/user.js" ]; then
        rm -f "$profileDir/user.js"
        echo "    -> Removed: $profileDir/user.js"
    fi

    # Remove chrome/utils/ folder
    if [ -d "$chromeDir/utils" ]; then
        rm -rf "$chromeDir/utils"
        echo "    -> Removed: $chromeDir/utils"
    fi

    # Remove chrome/components/ folder
    if [ -d "$chromeDir/components" ]; then
        rm -rf "$chromeDir/components"
        echo "    -> Removed: $chromeDir/components"
    fi

    # Remove chrome/icons/ folder
    if [ -d "$chromeDir/icons" ]; then
        rm -rf "$chromeDir/icons"
        echo "    -> Removed: $chromeDir/icons"
    fi

    # Remove chrome/imgs/ folder
    if [ -d "$chromeDir/imgs" ]; then
        rm -rf "$chromeDir/imgs"
        echo "    -> Removed: $chromeDir/imgs"
    fi

    # Remove userChrome.css and userContent.css if they exist
    if [ -f "$chromeDir/userChrome.css" ]; then
        rm -f "$chromeDir/userChrome.css"
        echo "    -> Removed: $chromeDir/userChrome.css"
    fi
    if [ -f "$chromeDir/userContent.css" ]; then
        rm -f "$chromeDir/userContent.css"
        echo "    -> Removed: $chromeDir/userContent.css"
    fi

    # Remove specific JS files and directories in chrome/JS/
    jsDir="${chromeDir}/JS"
    if [ -d "$jsDir" ]; then
        rm -f "$jsDir/second_sidebar.uc.mjs"
        rm -f "$jsDir/blurNewTabUrlbar.uc.mjs"
        rm -f "$jsDir/blurNewTabUrlbar.uc.js"
        rm -rf "$jsDir/second_sidebar"
        echo "    -> Removed specific customization files in: $jsDir"

        # If chrome/JS/ is empty, remove it too
        if [ -z "$(ls -A "$jsDir")" ]; then
            rm -rf "$jsDir"
            echo "    -> Removed empty JS folder: $jsDir"
        fi
    fi

    # 3. Clear startup cache automatically
    echo -e "\n[3/3] Finalizing uninstallation..."
    startupCache="${profileDir}/startupCache"
    if [ -d "$startupCache" ]; then
        rm -rf "$startupCache"
        echo "    -> Cleared Firefox startup cache automatically."
    fi
    echo "    -> Customizations successfully removed."

    # SUCCESS MESSAGE
    echo "=========================================================="
    echo -e "\033[1;32m           UNINSTALLATION COMPLETED SUCCESSFULLY!         \033[0m"
    echo "=========================================================="
    echo "To fully restore your browser state:"
    echo "1. Launch Firefox."
    echo "2. Firefox will restart, completely clean and restored to original."
    echo "=========================================================="
fi
