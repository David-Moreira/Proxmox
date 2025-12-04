#!/usr/bin/env bash

source <(curl -s https://raw.githubusercontent.com/David-Moreira/Proxmox/main/scripts/misc/build.func)

color

SWAP="/dev/pve/swap none swap sw 0 0"
MODULES="vfio vfio_iommu_type1 vfio_pci vfio_virqfd"
USERNAME="desktop"
PASSWORD="desktop"
SESSION_VALUE="mate"
CRON_JOB='0 7 * * 0 PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin /bin/bash -c "$(wget -qLO - https://github.com/tteck/Proxmox/raw/main/misc/update-lxcs-cron.sh)" >>/var/log/update-lxcs-cron.log 2>/dev/null'
CRON_JOB_TRIM='30 7 * * 0 PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin /bin/bash -c "for ct in \$(pct list | awk \"/^[0-9]/ {print \$1}\"); do pct fstrim \$ct; done" >>/var/log/trim-lxs-cron.log 2>/dev/null'

SET_MODULES=false
SET_INTEL=false
SET_GRAPHICAL_DISPLAY=false

clear

#-----
#Truncate log
msg_info "Truncating install log"
truncate -s 0 new-install.log && command >> new-install.log 2>&1
msg_ok "Truncated install log (new-install.log)"

#-----
#ADD TTECK PROXMOX LXC Cron Updater
msg_info "lxc cron updater"

# Check if the entry already exists
if ! crontab -l -u root | grep -Fxq "$CRON_JOB"; then
    echo "$CRON_JOB" | crontab -u root - >> new-install.log 2>&1
    echo "Added tteck lxc cron updater" >> new-install.log 2>&1
else
    echo "tteck lxc cron updater already exists" >> new-install.log 2>&1
fi

msg_ok "Added tteck lxc cron updater"

#----
#Add LXC FSTrim
msg_info "Adding fstrim for lxc"

if ! crontab -l -u root | grep -Fxq "$CRON_JOB_TRIM"; then
    EXISTING_CRONTAB=$(crontab -l -u root)
    echo "$EXISTING_CRONTAB"$'\n'"$CRON_JOB_TRIM" | crontab -u root - >> new-install.log 2>&1
    echo "Added lxc fstrim" >> new-install.log 2>&1
else
    echo "lxc fstrim already exists" >> new-install.log 2>&1
fi

msg_ok "Added lxc fstrim"

#-----
#Customize uid & gid
msg_info "Customizing sub uid & gid"

FILE_PATH="/etc/subuid"
CONTENT="# container users\nroot:100000:65536\n\n# custom users\nroot:1000:1\nroot:100:1"

echo -e "$CONTENT" | tee "$FILE_PATH" >> new-install.log 2>&1

FILE_PATH="/etc/subgid"
CONTENT="# container-specific groups\nroot:100000:65536\n\n# custom user groups\nroot:1000:1\n\n# default 'users' group 100\nroot:100:1"

echo -e "$CONTENT" | tee "$FILE_PATH" >> new-install.log 2>&1

msg_ok "Added custom sub uid & gid"

#-----
#DISABLE SWAP
msg_info "Disabling swap"

swapoff -a

# Comment out the line in /etc/fstab if it exists
sed -i "s|^$SWAP|# $SWAP|" /etc/fstab

msg_ok "Disabled swap"

#-----
#FSTAB And Default mounts
msg_info "Setting fstab and default mounts"

mountpoints=("/mnt/pve/barracuda" "/mnt/pve/downloads" "/mnt/pve/basic")

for dir in "${mountpoints[@]}"; do
    mkdir -p "$dir"
done

FSTAB="/etc/fstab"

entries=(
"UUID=2b7f9fa5-09f0-4b4f-83d1-d21128d00ee4 /mnt/pve/barracuda ext4 defaults,nofail,x-systemd.device-timeout=1s 0 0"
"UUID=37daabeb-16a1-49bb-8cd7-84b58a736b20 /mnt/pve/downloads  ext4 defaults,nofail,x-systemd.device-timeout=1s 0 0"
"UUID=fe38564d-59a1-457d-8852-563faeb2b45f /mnt/pve/basic      ext4 defaults,nofail,x-systemd.device-timeout=1s 0 0"
)

for entry in "${entries[@]}"; do
    uuid=$(echo "$entry" | awk '{print $1}')

    # If the UUID does not exist in /etc/fstab, append the full line
    if ! grep -q "$uuid" "$FSTAB"; then
        echo "Adding missing entry: $entry"
        echo "$entry" | tee -a "$FSTAB" > /dev/null
    else
        echo "Entry for $uuid already exists – skipping."
    fi
done

msg_ok "Set fstab and default mounts"

#-----
#GRUB
if [ "$SET_INTEL" = true ]; then
    msg_info "Configuring grub for intel iommu"

    GRUB="quiet intel_iommu=on iommu=pt"
    msg_info "Updating grub with: GRUB_CMDLINE_LINUX_DEFAULT=\"$GRUB\""

    sed -i "s/GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT=\"$GRUB\"/" /etc/default/grub
    update-grub >> new-install.log 2>&1

    msg_ok "Updated grub, /etc/default/grub (Don't forget to reboot for the changes to take effect.)"
else
    msg_ok "Skipping grub configuration"
fi

#-----
#MODULES
msg_info "Updating modules"

if [ "$SET_MODULES" = true ]; then

    # Add modules to /etc/modules if not already present
    for module in $MODULES; do
        grep -qxF "$module" /etc/modules || echo "$module" | tee -a /etc/modules >> new-install.log 2>&1
    done

    update-initramfs -u -k all >> new-install.log 2>&1
    
    msg_ok "Modules added to /etc/modules"
else
    msg_ok "Skipping module configuration"
fi

#-----
#VAINFO (Intel Drivers)
msg_info "Installing vainfo"

if [ "$SET_INTEL" = true ]; then

    apt install vainfo -y >> new-install.log 2>&1
    msg_ok "Installed vainfo"

else
    msg_ok "Skipping vainfo installation"
fi


#-----
#ADD USER
msg_info "Add new User: desktop"

if [ "$SET_GRAPHICAL_DISPLAY" = true ]; then
    if id "$USERNAME" &>/dev/null; then
        echo "User $USERNAME already exists" >> new-install.log 2>&1
    else
        # Create the user with the specified password
        useradd -m "$USERNAME"
        echo "$USERNAME:$PASSWORD" | chpasswd
        echo "User $USERNAME created with password $PASSWORD" >> new-install.log 2>&1
    fi

    msg_ok "Added new user: desktop"
else
    msg_ok "Skipping user creation"
fi



#-----
#INSTALL GRAPHICAL DISPLAY
msg_info "Installing graphical display"

if [ "$SET_GRAPHICAL_DISPLAY" = true ]; then

    #apt-get install xfce4 lightdm mate -y >> new-install.log 2>&1
    apt-get install lightdm mate -y >> new-install.log 2>&1

    msg_ok "Installed graphical display"

    #-----
    #SET DEFAULT SESSION
    msg_info "Default session to $SESSION_VALUE"

    if ! grep -q "user-session=$SESSION_VALUE" /etc/lightdm/lightdm.conf && grep -q '^\[Seat:\*\]' /etc/lightdm/lightdm.conf; then
        sed -i "/^\[Seat:\*\]/a user-session=$SESSION_VALUE" /etc/lightdm/lightdm.conf
    fi
    msg_ok "Default session set to $SESSION_VALUE"
else
    msg_ok "Skipping graphical display installation"
fi


#-----
#DISABLE LOCK
msg_info "Disabling screen lock"

if [ "$SET_GRAPHICAL_DISPLAY" = true ]; then

    if [ "$session" = "xfce" ]; then
      HIDDEN="Hidden=true"
      # Add Hidden=true to /etc/xdg/autostart/light-locker.desktop if not already present
      if grep -qxF "$HIDDEN" /etc/xdg/autostart/light-locker.desktop; then
          echo "$HIDDEN already exists in /etc/xdg/autostart/light-locker.desktop" >> new-install.log 2>&1
      else
          echo "$HIDDEN" | tee -a /etc/xdg/autostart/light-locker.desktop >> new-install.log 2>&1
      fi
    else

    mkdir -p /scripts
    FILE_PATH="/scripts/set_screenlock_off.sh"
    CONTENT="#!/bin/bash\n\n# Set the default screensaver lock off\ngsettings set org.mate.screensaver lock-enabled false\n"
    echo -e "$CONTENT" | tee "$FILE_PATH" >> new-install.log 2>&1
    chmod +x "$FILE_PATH"

    FILE_PATH="/etc/xdg/autostart/screenlock.desktop"
    CONTENT="[Desktop Entry]\nName=screenlock\nExec=/scripts/set_screenlock_off.sh\nType=Application"
    echo -e "$CONTENT" | tee "$FILE_PATH" >> new-install.log 2>&1

    fi
    msg_ok "Disabled screen lock"
else
    msg_ok "Skipping screen lock disable"
fi


#-----
#AUTO LOGIN
msg_info "Setting Auto login"
if [ "$SET_GRAPHICAL_DISPLAY" = true ]; then
    # Uncomment the autologin-user line and set the username
    sed -i '/^# *autologin-user=/s/^# *\(autologin-user=\)/\1'$USERNAME'/' /etc/lightdm/lightdm.conf

    msg_ok "Updated auto login user to $USERNAME"
else
    msg_ok "Skipping auto login setup"
fi

#-----
#SET DEFAULT RESOLUTION
msg_info "Setting the default resolution"

if [ "$SET_GRAPHICAL_DISPLAY" = true ]; then

    if [ "$session" = "xfce" ]; then
    CONTENT='<?xml version="1.0" encoding="UTF-8"?>
    <channel name="displays" version="1.0">
      <property name="ActiveProfile" type="string" value="Default"/>
      <property name="Default" type="empty">
        <property name="HDMI-2" type="string" value="Samsung 48&quot;">
          <property name="Active" type="bool" value="true"/>
          <property name="EDID" type="string" value="27fad4939ecd9bf30c36493b8500f3dab1097181"/>
          <property name="Resolution" type="string" value="2560x1440"/>
          <property name="RefreshRate" type="double" value="59.950550105254798"/>
          <property name="Rotation" type="int" value="0"/>
          <property name="Reflection" type="string" value="0"/>
          <property name="Primary" type="bool" value="false"/>
          <property name="Scale" type="empty">
            <property name="X" type="double" value="1"/>
            <property name="Y" type="double" value="1"/>
          </property>
          <property name="Position" type="empty">
            <property name="X" type="int" value="0"/>
            <property name="Y" type="int" value="0"/>
          </property>
        </property>
      </property>
      <property name="Fallback" type="empty">
        <property name="HDMI-2" type="string" value="Samsung 48&quot;">
          <property name="Active" type="bool" value="true"/>
          <property name="EDID" type="string" value="27fad4939ecd9bf30c36493b8500f3dab1097181"/>
          <property name="Resolution" type="string" value="2560x1440"/>
          <property name="RefreshRate" type="double" value="59.950550105254798"/>
          <property name="Rotation" type="int" value="0"/>
          <property name="Reflection" type="string" value="0"/>
          <property name="Primary" type="bool" value="false"/>
          <property name="Scale" type="empty">
            <property name="X" type="double" value="1"/>
            <property name="Y" type="double" value="1"/>
          </property>
          <property name="Position" type="empty">
            <property name="X" type="int" value="0"/>
            <property name="Y" type="int" value="0"/>
          </property>
        </property>
      </property>
      <property name="Notify" type="int" value="0"/>
      <property name="da39a3ee5e6b4b0d3255bfef95601890afd80709" type="string" value="">
        <property name="HDMI-2" type="string" value="Samsung 48&quot;">
          <property name="Active" type="bool" value="true"/>
          <property name="EDID" type="string" value="27fad4939ecd9bf30c36493b8500f3dab1097181"/>
          <property name="Resolution" type="string" value="2560x1440"/>
          <property name="RefreshRate" type="double" value="59.950550105254798"/>
          <property name="Rotation" type="int" value="0"/>
          <property name="Reflection" type="string" value="0"/>
          <property name="Primary" type="bool" value="false"/>
          <property name="Scale" type="empty">
            <property name="X" type="double" value="1"/>
            <property name="Y" type="double" value="1"/>
          </property>
          <property name="Position" type="empty">
            <property name="X" type="int" value="0"/>
            <property name="Y" type="int" value="0"/>
          </property>
        </property>
      </property>
    </channel>'

    # Write the content to displays.xml
    mkdir -p /home/desktop/.config/xfce4/xfconf/xfce-perchannel-xml/
    chown -R desktop:desktop /home/desktop/.config/
    echo -e "$CONTENT" | tee /home/desktop/.config/xfce4/xfconf/xfce-perchannel-xml/displays.xml >> new-install.log 2>&1

    else
    mkdir -p /scripts
    FILE_PATH="/scripts/set_default_resolution.sh"
    CONTENT="#!/bin/bash\n\nmonitor_name=\$(xrandr | grep -w connected | awk '{print \$1}')\nxrandr --output \"\$monitor_name\" --mode 2560x1440\n"
    echo -e "$CONTENT" | tee "$FILE_PATH" >> new-install.log 2>&1
    chmod +x "$FILE_PATH"

    FILE_PATH="/etc/xdg/autostart/resolution.desktop"
    CONTENT="[Desktop Entry]\nName=resolution\nExec=/scripts/set_default_resolution.sh\nType=Application"
    echo -e "$CONTENT" | tee "$FILE_PATH" >> new-install.log 2>&1
    fi

    msg_ok "Default resolution has been set"
else
    msg_ok "Skipping default resolution setup"
fi

#----
#SET DEFAULT AUDIO DEVICE
msg_info "Trying to set Default Audio Device auto start entry"
if [ "$SET_GRAPHICAL_DISPLAY" = true ]; then

    mkdir -p /scripts
    FILE_PATH="/scripts/set_default_audio.sh"
    CONTENT="#!/bin/bash\n\n# Set the default audio sink\npacmd set-default-sink alsa_output.pci-0000_00_1f.3.hdmi-stereo\n"
    echo -e "$CONTENT" | tee "$FILE_PATH" >> new-install.log 2>&1
    chmod +x "$FILE_PATH"

    FILE_PATH="/etc/xdg/autostart/audio.desktop"
    CONTENT="[Desktop Entry]\nName=audio\nExec=/scripts/set_default_audio.sh\nType=Application"
    echo -e "$CONTENT" | tee "$FILE_PATH" >> new-install.log 2>&1

    msg_ok "Added auto start entry to set Default Audio Device"
else
    msg_ok "Skipping Default Audio Device auto start entry"
fi

#-----
#INSTALL SNAP & MOONLIGHT
msg_info "Installing snap & moonlight"
    if [ "$SET_GRAPHICAL_DISPLAY" = true ]; then

    apt install snapd -y >> new-install.log 2>&1
    snap install core >> new-install.log 2>&1
    snap install moonlight >> new-install.log 2>&1

    msg_ok "Installed snap & moonlight"

    #-----
    #AUTO START MOONLIGHT
    msg_info "Creating auto start entry for Moonlight"

    # Define the file path and content
    FILE_PATH="/etc/xdg/autostart/moonlight.desktop"
    CONTENT="[Desktop Entry]\nName=moonlight\nExec=/snap/bin/moonlight\nType=Application"

    # Create the file with the specified content
    echo -e "$CONTENT" | tee "$FILE_PATH" >> new-install.log 2>&1

    msg_ok "Added auto start entry for Moonlight"
else
    msg_ok "Skipping snap & moonlight installation"
fi