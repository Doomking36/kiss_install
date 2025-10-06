#!/bin/sh

# Update Kiss
kiss_update() {
    # Update the system's package list
    yes | kiss u
    # Upgrade all installed packages
    yes | kiss U

    # Notify completion
    dialog --msgbox "System update complete." 6 60
}

# Install Kiss packages
kiss_install() {
    # Present the user with BIOS or UEFI options
    exec 3>&1
    while true; do
        SYSTEM_TYPE=$(dialog --menu "Select your system type:" 10 50 2 \
            1 "BIOS" \
            2 "UEFI" \
            2>&1 1>&3)
        case $SYSTEM_TYPE in
            1 | 2) break;;
            *) dialog --msgbox "Invalid selection. Please choose 1 for BIOS or 2 for UEFI." 5 50 ;;
        esac
    done
    exec 3>&-

    # Set default package list based on the system type
    PACKAGE_LIST="baseinit grub e2fsprogs ncurses libelf sqlite libudev-zero util-linux"
    [ "$SYSTEM_TYPE" -eq 2 ] && PACKAGE_LIST="$PACKAGE_LIST efibootmgr dosfstools"

    # Ask the user for additional packages to install, showing default packages
    exec 3>&1
    ADDITIONAL_PACKAGES=$(dialog --inputbox "Current default packages are: $PACKAGE_LIST\nEnter additional packages to install separated by spaces (optional):" 12 70 2>&1 1>&3)
    exec 3>&-

    # Append additional packages if provided
    if [ -n "$ADDITIONAL_PACKAGES" ]; then
        PACKAGE_LIST="$PACKAGE_LIST $ADDITIONAL_PACKAGES"
    fi

    # Confirm installation
    dialog --yesno "Confirm installation of the following packages:\n$PACKAGE_LIST" 10 60
    if [ $? -ne 0 ]; then
        dialog --msgbox "Installation aborted." 5 30
        return
    fi

    # Build and install the packages one at a time
    for package in $PACKAGE_LIST; do
        if ! yes | kiss b "$package"; then
            dialog --msgbox "Building failed for $package. Please check the logs." 5 50
            return
        fi
        if ! yes | kiss i "$package"; then
            dialog --msgbox "Installation failed for $package. Please check the logs." 5 50
            return
        fi
    done

    # Notify completion
    dialog --msgbox "Installation of packages complete: $PACKAGE_LIST" 6 60

    # Check if doas is installed before configuring doas.conf
    if command -v doas >/dev/null; then
        # Configure doas.conf
        echo "permit persist :wheel" >> /etc/doas.conf
        echo "permit nopass root" >> /etc/doas.conf
        echo "permit nopass :wheel cmd env" >> /etc/doas.conf
        echo "permit nopass :wheel cmd poweroff" >> /etc/doas.conf
        echo "permit nopass :wheel cmd reboot" >> /etc/doas.conf
        echo "permit nopass :wheel cmd dhcpcd" >> /etc/doas.conf
    else
        dialog --msgbox "doas not installed, skipping configuration." 5 50
    fi
}



# Browse linux kernel using elinks
fetch_linux_kernel() {
    # Check if elinks is installed
    if ! command -v elinks &>/dev/null; then
        dialog --msgbox "Elinks is not installed. Please install elinks and try again." 6 50
        return
    fi

    # Check if dialog is installed
    if ! command -v dialog &>/dev/null; then
        echo "Dialog is not installed. Please install dialog and try again."
        return
    fi

    # Prompt the user to visit the kernel website using elinks
    dialog --yesno "Would you like to open elinks to browse and download Linux kernel?" 7 60
    response=$?
    case $response in
        0) 
            dialog --msgbox "Use elinks to browse to 'https://www.kernel.org/' and download the desired kernel version. The downloaded file will be saved to the current directory." 8 70
            elinks https://www.kernel.org/
            ;;
        1) 
            dialog --msgbox "Operation canceled." 6 50
            ;;
        255) 
            dialog --msgbox "Operation canceled." 6 50
            ;;
    esac
}


# Essential kernel configuration
essential_kernel_config() {
    # Check if dialog is installed
    if ! command -v dialog &>/dev/null; then
        echo "Dialog is not installed. Please install dialog and try again."
        return
    fi

    # Ask for the path to the kernel .config file
    exec 3>&1
    CONFIG_PATH=$(dialog --inputbox "Enter the path to the kernel .config file:" 10 60 2>&1 1>&3)
    exec 3>&-

    if [ -z "$CONFIG_PATH" ]; then
        dialog --msgbox "No path entered. Aborting configuration." 5 50
        return
    fi

    if [ ! -f "$CONFIG_PATH" ]; then
        dialog --msgbox "The specified .config file does not exist. Aborting configuration." 6 50
        return
    fi

    # Confirm the modification of the .config file
    dialog --yesno "Are you sure you want to modify the .config file at $CONFIG_PATH with the essential kernel configurations?" 7 60
    if [ $? -ne 0 ]; then
        dialog --msgbox "Kernel configuration modification aborted." 5 50
        return
    fi

    # Append the configuration settings to the .config file
    cat <<EOL >> $CONFIG_PATH
CONFIG_64BIT=y
CONFIG_ACPI=y
CONFIG_EFI=y
CONFIG_FB=y
CONFIG_FB_EFI=y
CONFIG_FB_SIMPLE=y
CONFIG_SMP=y
CONFIG_X86_MPARSE=n
CONFIG_NR_CPUS=4
CONFIG_SCHED_CLUSTER=n
CONFIG_SCHED_MC=n
CONFIG_X86_MSR=y
CONFIG_X86_CPUID=y
CONFIG_X86_KERNEL_IBT=n
CONFIG_X86_INTEL_MEMORY_PROTECTION_KEYS=n
CONFIG_X86_MCE=y
CONFIG_X86_MCE_INTEL=y
CONFIG_PERF_EVENTS_INTEL_UNCORE=y
CONFIG_PREF_EVENTS_INTEL_RAPL=y
CONFIG_PREF_EVENTS_INTEL_CSTATE=y
CONFIG_DRM=y
CONFIG_DRM_SIMPLEDRM=y
CONFIG_PCI=y
CONFIG_DRM_TTM=y
CONFIG_DRM_TTM_HELPER=y
CONFIG_SOUND=y
CONFIG_SND=y
CONFIG_SND_TIMER=y
CONFIG_SND_SUPPORT_OLD_API=n
CONFIG_SND_CTL_FAST_LOOKUP=n
CONFIG_BLOCK=y
CONFIG_EXT4_FS=y
CONFIG_USB_SUPPORT=y
CONFIG_USB=y
CONFIG_USB_HID=y
CONFIG_RFKILL=y
CONFIG_ETHERNET=y
CONFIG_E1000=y
CONFIG_DRM_I915=y
CONFIG_PCI_MSI=y
CONFIG_VMD=y
CONFIG_INPUT_MOUSE=y
CONFIG_INPUT_KEYBOARD=y
CONFIG_USER_NS=y
CONFIG_FUSE_FS=y
CONFIG_KVM=y
CONFIG_KVM_INTEL=y
CONFIG_KVM_AMD=y
EOL

    if [ $? -eq 0 ]; then
        dialog --msgbox "Kernel configuration updated successfully." 5 50
    else
        dialog --msgbox "Failed to update the kernel configuration." 5 50
    fi
}


# Function to get hostname
get_hostname() {
    # Prompt the user for a new hostname
    exec 3>&1;
    HOSTNAME=$(dialog --inputbox "Enter your desired hostname:" 10 50 2>&1 1>&3);
    exec 3>&-;

    # Check if the hostname was provided
    if [ -z "$HOSTNAME" ]; then
        dialog --msgbox "No hostname entered. Operation cancelled." 5 50
        return
    fi

    # Write the hostname to /etc/hostname
    echo "$HOSTNAME" > /etc/hostname

    # Update /etc/hosts
    echo "127.0.0.1 $HOSTNAME.localdomain $HOSTNAME" > /etc/hosts
    echo "::1 $HOSTNAME.localdomain $HOSTNAME ip6-localhost" >> /etc/hosts

    dialog --msgbox "Hostname set to $HOSTNAME and updated in /etc/hostname and /etc/hosts." 6 60
}



# Function to set root password
set_root_password() {
    # Use file descriptor 3 to capture dialog output
    exec 3>&1;

    # Get root password from user input
    ROOT_PASSWORD=$(dialog --insecure --passwordbox "Enter root password:" 10 50 2>&1 1>&3);
    exec 3>&-;

    # Check if password was entered
    if [ -z "$ROOT_PASSWORD" ]; then
        dialog --msgbox "No password entered, exiting." 6 30
        return
    fi

    # Set the root password
    echo "root:$ROOT_PASSWORD" | chpasswd

    # Confirm password change
    if [ $? -eq 0 ]; then
        dialog --msgbox "Root password set successfully." 6 30
    else
        dialog --msgbox "Failed to set root password." 6 30
    fi
}


# Function to add a user
add_user() {
    # Use file descriptor 3 to capture dialog output
    exec 3>&1

    # Get username from user input
    USERNAME=$(dialog --inputbox "Enter new username:" 10 50 2>&1 1>&3)
    if [ -z "$USERNAME" ]; then
        # If no username is entered, exit
        dialog --msgbox "No username entered, exiting." 6 30
        exec 3>&-
        return
    fi

    # Get home directory from user input
    HOME_DIR=$(dialog --inputbox "Enter home directory for $USERNAME or leave blank for default:" 10 50 2>&1 1>&3)

    # Get password from user input
    USER_PASSWORD=$(dialog --insecure --passwordbox "Enter password for $USERNAME:" 10 50 2>&1 1>&3)
    if [ -z "$USER_PASSWORD" ]; then
        # If no password is entered, exit
        dialog --msgbox "No password entered, exiting." 6 30
        exec 3>&-
        return
    fi

    # Choose groups from a checklist
    GROUPS=$(dialog --separate-output --checklist "Select groups to add $USERNAME to:" 15 50 5 \
        "users" "General users group" off \
        "audio" "Access to audio devices" off \
        "video" "Access to video devices" off \
        "input" "Access to input devices" off \
        "wheel" "Administrative group" on 2>&1 1>&3)
    if [ -z "$GROUPS" ]; then
        # If no group is selected, proceed with no group
        dialog --msgbox "No group selected, user will not be added to any specific groups." 6 50
    fi

    # Close file descriptor 3
    exec 3>&-

    # Add the user and optionally specify home directory
    if [ -z "$HOME_DIR" ]; then
        adduser "$USERNAME"
    else
        adduser -h "$HOME_DIR" "$USERNAME"
    fi

    # Add user to selected groups
    for GROUP in $GROUPS; do
        addgroup "$USERNAME" "$GROUP"
    done

    if [ $? -eq 0 ]; then
        # Set the user's password
        echo "$USERNAME:$USER_PASSWORD" | chpasswd
        # Confirm user addition
        dialog --msgbox "User $USERNAME added to selected groups and home directory set" 6 50
    else
        # Handle error in user addition
        dialog --msgbox "Failed to add user $USERNAME" 6 30
    fi
}




# Function to generate fstab
genfstab() {
    # Ensure the script is run as root
    if [ "$(id -u)" != "0" ]; then
        dialog --msgbox "This script must be run as root." 5 50
        return
    fi

    # Display downloading message
    dialog --infobox "Downloading genfstab script..." 3 50
    sleep 2  # Pause to ensure the user sees the message

    # Download the genfstab script
    if curl -fLO https://github.com/cemkeylan/genfstab/raw/master/genfstab; then
        # Make the script executable
        chmod +x genfstab

        # Execute the script to append to /etc/fstab
        dialog --infobox "Generating and updating /etc/fstab..." 3 50
        sleep 2  # Pause to ensure the user sees the message

        if ./genfstab -U / >> /etc/fstab; then
            # Clean up by removing the script
            rm -rf genfstab

            # Show final message
            dialog --msgbox "fstab generated and updated successfully." 5 50
        else
            rm -rf genfstab
            dialog --msgbox "Failed to generate fstab. Please check your system configuration." 5 60
        fi
    else
        dialog --msgbox "Failed to download genfstab. Check your internet connection or URL." 5 60
    fi
}


# Install Grub on either BIOS or UEFI system
grub_install() {
    # Ask for the partition to run tune2fs
    exec 3>&1
    TUNE_DEVICE=$(dialog --inputbox "Enter the device partition for tune2fs (e.g., sda1, sda2, etc.):" 10 60 2>&1 1>&3)
    exec 3>&-

    if [ -z "$TUNE_DEVICE" ]; then
        dialog --msgbox "No device entered for tune2fs. Aborting installation." 5 50
        return
    fi

    # Execute the tune2fs command
    tune2fs -O ^metadata_csum_seed /dev/$TUNE_DEVICE
    if [ $? -ne 0 ]; then
        dialog --msgbox "Failed to run tune2fs on /dev/$TUNE_DEVICE. Aborting installation." 6 50
        return
    fi

    # Add the GRUB_DISABLE_OS_PROBER setting to /etc/default/grub
    echo GRUB_DISABLE_OS_PROBER=false >> /etc/default/grub

    # Present the user with BIOS or UEFI options
    exec 3>&1
    SYSTEM_TYPE=$(dialog --menu "Select the system type for GRUB installation:" 10 50 2 \
    1 "BIOS" \
    2 "UEFI" \
    2>&1 1>&3)
    exec 3>&-

    # Ensure a selection was made
    if [ -z "$SYSTEM_TYPE" ]; then
        dialog --msgbox "No system type selected. Aborting installation." 5 50
        return
    fi

    # Ask for the partition device
    exec 3>&1
    DEVICE=$(dialog --inputbox "Enter the device partition (e.g., /dev/sda for BIOS or /dev/nvme0n1p1 for UEFI):" 10 60 2>&1 1>&3)
    exec 3>&-

    if [ -z "$DEVICE" ]; then
        dialog --msgbox "No device entered. Aborting installation." 5 50
        return
    fi

    # Confirmation dialog
    dialog --yesno "Are you sure you want to install GRUB on $DEVICE?" 6 40
    if [ $? -ne 0 ]; then
        dialog --msgbox "GRUB installation aborted." 5 40
        return
    fi

    # Execute commands based on the system type
    if [ "$SYSTEM_TYPE" == "1" ]; then
        # BIOS system type
        grub-install --target=i386-pc $DEVICE
        grub-mkconfig -o /boot/grub/grub.cfg
        dialog --msgbox "GRUB installed successfully for BIOS on $DEVICE." 6 50
    elif [ "$SYSTEM_TYPE" == "2" ]; then
        # UEFI system type
        grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=kiss
        grub-mkconfig -o /boot/grub/grub.cfg
        dialog --msgbox "GRUB installed successfully for UEFI on $DEVICE." 6 50
    else
        dialog --msgbox "Invalid system type selection." 5 40
    fi
}



# Main Menu
main_menu() {
    keep_running=true
    while $keep_running; do
        exec 3>&1;
        SELECTION=$(dialog --clear --title "Main Menu" --menu "Choose an option:" 20 60 10 \
            1 "Update Kiss" \
            2 "Install Kiss Packages" \
            3 "Fetch Linux Kernel" \
            4 "Essential Linux Kernel Config" \
            5 "Set Hostname" \
            6 "Set Root Password" \
            7 "Add User" \
            8 "Generate Fstab" \
            9 "Install Grub" \
            2>&1 1>&3)
        exit_status=$?
        exec 3>&-;

        if [ $exit_status -eq 1 ]; then  # User pressed 'Exit'
            dialog --msgbox "Exiting script." 5 30
            keep_running=false
            continue
        fi

        case $SELECTION in
            1) kiss_update ;;
            2) kiss_install ;;
            3) fetch_linux_kernel ;;
            4) essential_kernel_config ;;
            5) get_hostname ;;
            6) set_root_password ;;
            7) add_user ;;
            8) genfstab ;;
            9) grub_install ;;
            *) dialog --msgbox "Invalid option or cancelled. Please select a valid option." 6 30 ;;
        esac
    done
}

# Start the script by calling main menu
main_menu
