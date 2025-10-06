#!/bin/sh

# Function to create a partition
create_partition() {
    # Launch disk partitioning tool
    cfdisk
}

# Function to select and format a partition
select_and_format_partition() {
    # Fetch partition details: device name, size, mount point, and format as dialog checklist input
    partitions=$(lsblk -nlp -o NAME,SIZE,MOUNTPOINT,TYPE | grep 'part' | awk '{print $1, $2, "off"}')

    # Display a checklist dialog to allow the user to select a partition
    dialog --title "Select a partition to format" --checklist "Choose a partition:" 20 70 12 ${partitions} 2> /tmp/partition_selection.txt
    selected_partition=$(< /tmp/partition_selection.txt)
    rm -f /tmp/partition_selection.txt

    # Check if the user selected a partition
    if [ -z "$selected_partition" ]; then
        echo "No partition selected."
        return
    fi

    # Proceed to format the selected partition
    format_partition "$selected_partition"
}

# Function to format a partition with chosen file system
format_partition() {
    local PARTITION=$1
    local FS_TYPE

    # Offer a choice of file systems
    FS_TYPE=$(dialog --menu "Choose the file system type for formatting:" 15 50 6 \
        "ext4" "ext4 - The Fourth Extended FileSystem" \
        "ntfs" "NTFS - New Technology File System" \
        "vfat" "VFAT - FAT32 with long filenames" \
        "exfat" "exFAT - Extended File Allocation Table" \
        "btrfs" "Btrfs - B-Tree File System" \
        "xfs" "XFS - X File System" \
        2>&1 >/dev/tty)

    # Verify that the file system type is selected
    if [ -z "$FS_TYPE" ]; then
        dialog --msgbox "No file system selected." 6 40
        return
    fi

    # Confirm before formatting
    dialog --yesno "Are you sure you want to format $PARTITION as $FS_TYPE? This will erase all data on the partition." 7 60
    if [ $? -ne 0 ]; then
        dialog --msgbox "Formatting canceled." 6 40
        return
    fi

    # Attempt to format the partition
    if ! mkfs -t $FS_TYPE $PARTITION; then
        dialog --msgbox "Failed to format $PARTITION as $FS_TYPE." 6 50
        return
    fi
    dialog --msgbox "$PARTITION formatted as $FS_TYPE." 6 40
}

# Function to mount a partition
mount_partition() {
    # Fetch partition details: device name and size
    readarray -t partitions < <(lsblk -nlp -o NAME,SIZE,TYPE | awk '/part/ {print $1, $2}')

    # Ensure that the partitions are available
    if [ ${#partitions[@]} -eq 0 ]; then
        dialog --msgbox "No unmounted partitions found." 6 40
        exit 1
    fi

    # Use an array to store the partition options for the dialog command
    options=()
    for partition_info in "${partitions[@]}"; do
        name=$(awk '{print $1}' <<< "$partition_info")
        size=$(awk '{print $2}' <<< "$partition_info")
        options+=("$name" "$size")
    done

    # Display a menu dialog to allow the user to select a partition
    PARTITION=$(dialog --menu "Choose a partition to mount:" 20 60 10 "${options[@]}" 3>&1 1>&2 2>&3)
    clear

    # If no partition was chosen, return
    if [ -z "$PARTITION" ]; then
        echo "No partition selected or canceled."
        exit 1
    fi

    # Prompt for the mount point
    MOUNT_POINT=$(dialog --inputbox "Enter the mount point (e.g., /mnt or /newroot):" 10 50 3>&1 1>&2 2>&3)
    clear

    # Check if the user exited the dialog or didn't enter a mount point
    if [ -z "$MOUNT_POINT" ]; then
        echo "No mount point entered or canceled."
        exit 1
    fi

    # Ensure the mount point exists or create it
    if [ ! -d "$MOUNT_POINT" ]; then
        mkdir -p "$MOUNT_POINT"
        if [ $? -ne 0 ]; then
            dialog --msgbox "Failed to create mount point $MOUNT_POINT." 6 50
            exit 1
        fi
    fi

    # Attempt to mount the partition
    if ! mount "$PARTITION" "$MOUNT_POINT"; then
        dialog --msgbox "Failed to mount $PARTITION on $MOUNT_POINT. Check that the partition and mount point are correct." 6 50
    else
        dialog --msgbox "$PARTITION successfully mounted to $MOUNT_POINT." 6 40
    fi
}

# Function to check if the system is UEFI or BIOS
check_uefi_or_bios() {
    if [ -d "/sys/firmware/efi/" ]; then
        dialog --msgbox "The system is UEFI." 6 25
    else
        dialog --msgbox "The system is BIOS." 6 25
    fi
}

# Function to start installation process
start_installation() {
    # Check if required commands are available
    for cmd in pacman curl tar chmod; do
        if ! command -v "$cmd" >/dev/null; then
            dialog --title "Error" --msgbox "Command $cmd is not installed. Please install it and try again." 6 50
            return
        fi
    done

    # Install necessary packages
    dialog --infobox "Installing tar, curl, and xz packages..." 3 40
    if ! pacman -Sy --noconfirm tar curl xz; then
        dialog --title "Error" --msgbox "Failed to install packages. Check your network connection or package manager settings." 6 50
        return
    fi

    # Download KISS chroot tarball
    dialog --infobox "Downloading KISS chroot tarball..." 3 40
    if ! curl --output kiss.xz --fail https://codeberg.org/kiss-community/repo/releases/download/24.06.14/kiss-chroot-24.06.14-2.tar.xz; then
        dialog --title "Error" --msgbox "Failed to download the KISS chroot tarball. Check your internet connection." 6 50
        return
    fi

    # Extracting the KISS chroot tarball
    dialog --infobox "Extracting the KISS chroot tarball to /mnt..." 3 50
    if ! tar xf kiss.xz -C /mnt; then
        dialog --title "Error" --msgbox "Failed to extract the tarball. Check the file integrity and destination permissions." 6 50
        return
    fi

    # Setting up Kiss
    dialog --infobox "Setting up Kiss" 3 50
    if ! chmod u+s /mnt/usr/bin/busybox-suid; then
        dialog --title "Error" --msgbox "Failed to set permissions for busybox-suid." 6 50
        return
    fi

    dialog --title "Installation Complete" --msgbox "KISS chroot environment has been successfully installed and set up on /mnt." 6 50
}

# Global variables for destination directory and environment choice
DESTINATION=""
ENVIRONMENT=""

# Function to clone specific repositories with user-specified destination
repo_input() {
    # Check if git is installed
    if ! command -v git &>/dev/null; then
        dialog --msgbox "Git is not installed. Please install git and try again." 6 50
        return
    fi

    # Use dialog to create a directory selection menu
    DESTINATION=$(dialog --stdout --title "Select Clone Directory" --dselect "/" 14 60)

    # Check if the user exited the dialog or didn't enter a destination
    if [ -z "$DESTINATION" ]; then
        dialog --msgbox "No destination entered. Exiting the repository cloning process." 6 50
        return
    fi

    # Ensure the destination directory exists
    if ! mkdir -p "$DESTINATION" 2>/dev/null; then
        dialog --msgbox "Failed to create or access the directory. Check permissions or path validity." 6 50
        return
    fi

    # Function to handle cloning and provide user feedback
    clone_repo() {
        local repo_url=$1
        local repo_path=$2
        local repo_name=$(basename "$repo_path")

        # Inform the user about the cloning process
        dialog --infobox "Cloning $repo_name repository to $repo_path..." 5 70
        # Perform the actual clone operation
        if ! git clone "$repo_url" "$repo_path" 2>/dev/null; then
            dialog --msgbox "Failed to clone $repo_name. Check your internet connection or repository URL." 6 60
            return 1
        fi
    }

    # Prompt the user to select Wayland, Xorg, or Both
    dialog --menu "Select the environment you want to set up:" 15 50 3 \
        1 "Wayland" \
        2 "Xorg" \
        3 "Both" 2>choice.txt

    choice=$(<choice.txt)
    rm -f choice.txt

    ENVIRONMENT="$choice"

    if [ "$choice" == "1" ]; then
        # Perform cloning operations for Wayland
        if ! (clone_repo https://github.com/kiss-community/repo "$DESTINATION/repo" &&
            clone_repo https://github.com/kiss-community/community "$DESTINATION/community"); then
            dialog --msgbox "Some repositories failed to clone. Please check the error messages." 6 50
            return
        fi
        # Inform the user of successful cloning for Wayland
        dialog --msgbox "Repositories cloned successfully:\n- $DESTINATION/repo\n- $DESTINATION/community" 10 50
    elif [ "$choice" == "2" ]; then
        # Perform cloning operations for Xorg
        if ! (clone_repo https://github.com/kiss-community/repo "$DESTINATION/repo" &&
            clone_repo https://github.com/kiss-community/community "$DESTINATION/community" &&
            clone_repo https://github.com/ehawkvu/kiss-xorg "$DESTINATION/xorg" &&
            clone_repo https://github.com/hovercats/kiss-dumpsterfire "$DESTINATION/fire"); then
            dialog --msgbox "Some repositories failed to clone. Please check the error messages." 6 50
            return
        fi
        # Inform the user of successful cloning for Xorg
        dialog --msgbox "Repositories cloned successfully:\n- $DESTINATION/repo\n- $DESTINATION/community\n- $DESTINATION/xorg\n- $DESTINATION/fire" 10 50
    elif [ "$choice" == "3" ]; then
        # Perform cloning operations for Both Wayland and Xorg
        if ! (clone_repo https://github.com/kiss-community/repo "$DESTINATION/repo" &&
            clone_repo https://github.com/kiss-community/community "$DESTINATION/community" &&
            clone_repo https://github.com/ehawkvu/kiss-xorg "$DESTINATION/xorg" &&
            clone_repo https://github.com/hovercats/kiss-dumpsterfire "$DESTINATION/fire"); then
            dialog --msgbox "Some repositories failed to clone. Please check the error messages." 6 50
            return
        fi
        # Inform the user of successful cloning for Both
        dialog --msgbox "Repositories cloned successfully:\n- $DESTINATION/repo\n- $DESTINATION/community\n- $DESTINATION/xorg\n- $DESTINATION/fire" 10 50
    else
        dialog --msgbox "Invalid choice. Exiting." 5 40
        exit 1
    fi
}

# Create Profile containing path to repo for Kiss package manager
create_profile() {
    DEST=$(dialog --stdout --title "Profile Directory" --fselect "/" 14 60)
    if [ -z "$DEST" ]; then
        dialog --title "Error" --msgbox "No directory entered. Exiting." 5 40
        return
    fi

    KISS_PROFILE_DEST="{$DEST}"
    if [[ "$DEST" == /mnt* ]]; then
        KISS_PROFILE_DEST="${DEST#/mnt}"
    fi
    PROFILE_FILE="$DEST/profile"

    KISS_PATH_DEST="${DESTINATION}"
    if [[ "$DESTINATION" == /mnt* ]]; then
        KISS_PATH_DEST="${DESTINATION#/mnt}"
    fi

    if [ ! -d "$(dirname "$PROFILE_FILE")" ]; then
        mkdir -p "$(dirname "$PROFILE_FILE")"
        if [ $? -ne 0 ]; then
            dialog --title "Error" --msgbox "Failed to create directory. Exiting." 5 50
            return
        fi
    fi

    JOBS=$(dialog --stdout --title "Number of Jobs" --inputbox "Enter the number of parallel jobs for make (default: nproc):" 8 50 "$(nproc)")
    if [ -z "$JOBS" ]; then
        JOBS=$(nproc)
    fi

    if ! touch "$PROFILE_FILE"; then
        dialog --title "Error" --msgbox "Unable to create profile file. Check permissions." 5 60
        return
    fi

    dialog --infobox "Creating profile at $PROFILE_FILE..." 3 50
    sleep 2

    # Select -march flag
    MARCH=$(dialog --stdout --title "Architecture" --menu "Choose your architecture:" 10 50 2 \
        1 "x86-64 (default)" \
        2 "Enter custom architecture")

    case $MARCH in
        1) MARCH="x86-64" ;;
        2) MARCH=$(dialog --stdout --title "Custom Architecture" --inputbox "Enter custom architecture (e.g., armv7):" 8 50)
    esac

    # Select -mtune flag
    MTUNE=$(dialog --stdout --title "Tuning" --menu "Choose processor tuning preference:" 10 50 2 \
        1 "native (default)" \
        2 "generic")

    case $MTUNE in
        1) MTUNE="native" ;;
        2) MTUNE="generic" ;;
    esac

    # Ask user for their preference on CFLAGS
    CFLAG_OPTION=$(dialog --stdout --title "Optimization Level" --menu "Choose the optimization level for compilation:" 15 50 3 \
        1 "Optimize for size (-Os)" \
        2 "Optimize for speed (-O2)" \
        3 "Other (specify)")

    case $CFLAG_OPTION in
        1) CFLAGS="-march=$MARCH -mtune=$MTUNE -pipe -Os" ;;
        2) CFLAGS="-march=$MARCH -mtune=$MTUNE -pipe -O2" ;;
        3) 
            CUSTOM_OPT=$(dialog --stdout --title "Custom Optimization" --inputbox "Enter custom optimization flag (e.g., -O3):" 8 50)
            CFLAGS="-march=$MARCH -mtune=$MTUNE -pipe $CUSTOM_OPT"
            ;;
    esac

    case $ENVIRONMENT in
        1) # Wayland
            cat > "$PROFILE_FILE" <<EOF
# KISS Path Configuration
export KISS_PATH="$KISS_PATH_DEST/repo/core"
KISS_PATH="\$KISS_PATH:$KISS_PATH_DEST/repo/extra"
KISS_PATH="\$KISS_PATH:$KISS_PATH_DEST/repo/wayland"
KISS_PATH="\$KISS_PATH:$KISS_PATH_DEST/community/community"

# Build Flags
export CFLAGS="$CFLAGS"
export CXXFLAGS="$CFLAGS"
export MAKEFLAGS="-j$JOBS"
export SAMUFLAGS="-j$JOBS"
EOF
        ;;
        2) # Xorg
            cat > "$PROFILE_FILE" <<EOF
# KISS Path Configuration
export KISS_PATH="$KISS_PATH_DEST/repo/core"
KISS_PATH="\$KISS_PATH:$KISS_PATH_DEST/xorg/extra"
KISS_PATH="\$KISS_PATH:$KISS_PATH_DEST/xorg/xorg"
KISS_PATH="\$KISS_PATH:$KISS_PATH_DEST/xorg/community"
KISS_PATH="\$KISS_PATH:$KISS_PATH_DEST/fire/xorg"
KISS_PATH="\$KISS_PATH:$KISS_PATH_DEST/repo/extra"
KISS_PATH="\$KISS_PATH:$KISS_PATH_DEST/community/community"

# Build Flags
export CFLAGS="$CFLAGS"
export CXXFLAGS="$CFLAGS"
export MAKEFLAGS="-j$JOBS"
export SAMUFLAGS="-j$JOBS"
EOF
        ;;
        3) # Both
            cat > "$PROFILE_FILE" <<EOF
# KISS Path Configuration
export KISS_PATH="$KISS_PATH_DEST/repo/core"
KISS_PATH="\$KISS_PATH:$KISS_PATH_DEST/xorg/extra"
KISS_PATH="\$KISS_PATH:$KISS_PATH_DEST/xorg/xorg"
KISS_PATH="\$KISS_PATH:$KISS_PATH_DEST/xorg/community"
KISS_PATH="\$KISS_PATH:$KISS_PATH_DEST/fire/xorg"
KISS_PATH="\$KISS_PATH:$KISS_PATH_DEST/repo/extra"
KISS_PATH="\$KISS_PATH:$KISS_PATH_DEST/repo/wayland"
KISS_PATH="\$KISS_PATH:$KISS_PATH_DEST/community/community"

# Build Flags
export CFLAGS="$CFLAGS"
export CXXFLAGS="$CFLAGS"
export MAKEFLAGS="-j$JOBS"
export SAMUFLAGS="-j$JOBS"
EOF
        ;;
        *)
            dialog --title "Error" --msgbox "Invalid environment choice. Exiting." 5 50
            return
        ;;
    esac


    dialog --title "Profile Created" --msgbox "Profile created successfully at $PROFILE_FILE" 6 50
}

# Main Menu
main_menu() {
    keep_running=true
    while $keep_running; do
        exec 3>&1;
        SELECTION=$(dialog --cancel-label "Exit" --clear --title "Main Menu" --menu "Choose an option:" 20 60 8 \
            1 "Check if UEFI or BIOS" \
            2 "Create Partition" \
            3 "Format Disk" \
            4 "Mount Partition" \
            5 "Start Installation" \
            6 "Clone Repositories" \
            7 "Create Profile" \
            2>&1 1>&3)
        exit_status=$?
        exec 3>&-;

        if [ $exit_status -eq 1 ]; then  # User pressed 'Exit'
            dialog --msgbox "Exiting script." 5 30
            keep_running=false
            continue
        fi

        case $SELECTION in
            1) check_uefi_or_bios ;;
            2) create_partition ;;
            3) select_and_format_partition ;;
            4) mount_partition ;;
            5) start_installation ;;
            6) repo_input ;;
            7) create_profile ;;
            *) dialog --msgbox "Invalid option or cancelled. Please select a valid option." 6 30 ;;
        esac
    done
}

# Start the script by calling main menu
main_menu
