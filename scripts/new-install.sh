#!/usr/bin/env bash

source <(curl -s https://raw.githubusercontent.com/David-Moreira/Proxmox/main/scripts/misc/build.func)

color

#-----
#Truncate log
msg_info "Truncating install log"
truncate -s 0 new-install.log && command >> new-install.log 2>&1
msg_ok "Truncated install log (new-install.log)"

#-----
#ADD TTECK PROXMOX LXC Cron Updater
msg_info "Adding tteck lxc cron updater"
# Define the cron job entry
CRON_JOB='0 7 * * 0 PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin /bin/bash -c "$(wget -qLO - https://github.com/tteck/Proxmox/raw/main/misc/update-lxcs-cron.sh)" >>/var/log/update-lxcs-cron.log 2>/dev/null'

# Check if the entry already exists
if ! crontab -l | grep -Fxq "$CRON_JOB"; then
    echo "$CRON_JOB" | crontab -u root -
    echo "Added tteck lxc cron updater" >> new-install.log 2>&1
else
    echo "tteck lxc cron updater already exists" >> new-install.log 2>&1
fi

msg_ok "Added tteck lxc cron updater"

#-----
#DISABLE SWAP
msg_info "Disabling swap"

swapoff -a
SWAP="/dev/pve/swap none swap sw 0 0"

# Comment out the line in /etc/fstab if it exists
sed -i "s|^$SWAP|# $SWAP|" /etc/fstab

msg_ok "Disabled swap"

#-----
#GRUB
GRUB="quiet intel_iommu=on iommu=pt"
msg_info "Updating grub with: GRUB_CMDLINE_LINUX_DEFAULT=\"$GRUB\""

sed -i "s/GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT=\"$GRUB\"/" /etc/default/grub
update-grub >> new-install.log 2>&1

msg_ok "Updated grub, /etc/default/grub (Don't forget to reboot for the changes to take effect.)"

#-----
#MODULES
msg_info "Updating modules"
MODULES="vfio vfio_iommu_type1 vfio_pci vfio_virqfd"

# Add modules to /etc/modules if not already present
for module in $MODULES; do
    grep -qxF "$module" /etc/modules || echo "$module" | tee -a /etc/modules
done

update-initramfs -u -k all >> new-install.log 2>&1
msg_ok "Modules added to /etc/modules"

#-----
#VAINFO (Intel Drivers)
msg_info "Installing vainfo"

apt install vainfo -y >> new-install.log 2>&1

msg_ok "Installed vainfo"

#-----
#ADD USER
msg_info "Add new User: desktop"

USERNAME="desktop"
PASSWORD="desktop"

if id "$USERNAME" &>/dev/null; then
    echo "User $USERNAME already exists" >> new-install.log 2>&1
else
    # Create the user with the specified password
    useradd -m "$USERNAME"
    echo "$USERNAME:$PASSWORD" | chpasswd
    echo "User $USERNAME created with password $PASSWORD" >> new-install.log 2>&1
fi

msg_ok "Added new user: desktop"

#-----
#INSTALL GRAPHICAL DISPLAY
msg_info "Installing graphical display"

apt-get install xfce4 lightdm mate -y >> new-install.log 2>&1

msg_ok "Installed graphical display"

#-----
#SET DEFAULT SESSION TO XFCE
msg_info "Default session to xfce"
SESSION_VALUE="xfce"

# Add user-session=xfce to /etc/lightdm/lightdm.conf if not already present
if grep -qxF "user-session=$SESSION_VALUE" /etc/lightdm/lightdm.conf; then
    echo "user-session=$SESSION_VALUE already exists in /etc/lightdm/lightdm.conf" >> new-install.log 2>&1
else
    echo "user-session=$SESSION_VALUE" | tee -a /etc/lightdm/lightdm.conf >> new-install.log 2>&1
fi

msg_ok "Default session set to xfce"

#-----
#DISABLE LOCK
msg_info "Disabling screen lock"
HIDDEN="Hidden=true"

# Add Hidden=true to /etc/xdg/autostart/light-locker.desktop if not already present
if grep -qxF "$HIDDEN" /etc/xdg/autostart/light-locker.desktop; then
    echo "$HIDDEN already exists in /etc/xdg/autostart/light-locker.desktop" >> new-install.log 2>&1
else
    echo "$HIDDEN" | tee -a /etc/xdg/autostart/light-locker.desktop >> new-install.log 2>&1
fi

msg_ok "Disabled screen lock"

#-----
#AUTO LOGIN
msg_info "Setting Auto login"
# Uncomment the autologin-user line and set the username
sed -i '/^# *autologin-user=/s/^# *\(autologin-user=\)/\1'$USERNAME'/' /etc/lightdm/lightdm.conf

msg_ok "Updated auto login user to $USERNAME"

#-----
#SET DEFAULT RESOLUTION
msg_info "Setting the default resolution"

# Define the content to replace displays.xml
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
  <property name="AutoEnableProfiles" type="bool" value="true"/>
</channel>'

# Write the content to displays.xml
echo -e "$CONTENT" | tee /home/desktop/.config/xfce4/xfconf/xfce-perchannel-xml/displays.xml >> new-install.log 2>&1

msg_ok "Default resolution has been set"

#----
#SET DEFAULT AUDIO DEVICE
msg_info "Trying to set Default Audio Device auto start entry"

# Create the file with the specified content
mkdir -p /scripts
FILE_PATH="/scripts/set_default_audio.sh"
CONTENT="#!/bin/bash\n\n# Set the default audio sink\npacmd set-default-sink alsa_output.pci-0000_00_1f.3.hdmi-stereo\n"
echo -e "$CONTENT" | tee "$FILE_PATH" >> new-install.log 2>&1
chmod +x "$FILE_PATH"

# Create the file with the specified content
FILE_PATH="/etc/xdg/autostart/audio.desktop"
CONTENT="[Desktop Entry]\nName=audio\nExec=/scripts/set_default_audio.sh\nType=Application"
echo -e "$CONTENT" | tee "$FILE_PATH" >> new-install.log 2>&1

msg_ok "Added auto start entry to set Default Audio Device"

#-----
#AUTO START MOONLIGHT
msg_info "Creating auto start entry for Moonlight"

# Define the file path and content
FILE_PATH="/etc/xdg/autostart/moonlight.desktop"
CONTENT="[Desktop Entry]\nName=moonlight\nExec=/snap/bin/moonlight\nType=Application"

# Create the file with the specified content
echo -e "$CONTENT" | tee "$FILE_PATH" >> new-install.log 2>&1

msg_ok "Added auto start entry for Moonlight"

#-----
#INSTALL SNAP & MOONLIGHT
msg_info "Installing snap & moonlight"

apt install snapd -y >> new-install.log 2>&1
snap install core >> new-install.log 2>&1
snap install moonlight >> new-install.log 2>&1

msg_ok "Installed snap & moonlight"

