#!/bin/bash

# new root pass
#passwd root


# start sshd
#/etc/init.d/sshd start


# Connect to Internet (IDK how to WLAN)
#net-setup

# Check if internet OK
#ping -c3 orf.at


localectl set-keymap de-latin1
timedatectl set-timezone Europe/Vienna


timedatectl set-ntp true



# delete everything
wipefs -af /dev/nvme0n1 && 


# create new partitions
fdisk /dev/nvme0n1 --wipe always --wipe-partitions always <<EOF &&
    g
    n
    1

    +512M

    n
    p
    2

    +250G

    n
    p
    3



    t
    1
    EF

    t
    2
    83

    t
    3
    83

    w
EOF


# Create filesystems
# EFI
mkfs.vfat -F 32 -n "EFI" /dev/nvme0n1p1

# ARCH
cryptsetup luksFormat --type luks1 --key-size 512 -v -y /dev/nvme0n1p2 &&
cryptsetup open /dev/nvme0n1p2 crypt_arch &&
mkfs.btrfs -L ARCH /dev/mapper/crypt_arch &&
mkdir -p /mnt/arch &&
mount /dev/mapper/crypt_arch /mnt/arch

# Create Subvolumes
btrfs sub create /mnt/arch/@ &&
btrfs sub create /mnt/arch/@home &&
btrfs sub create /mnt/arch/@snapshots &&
btrfs sub create /mnt/arch/@swap &&
btrfs sub create /mnt/arch/@var &&
umount /mnt/arch

# Mount Subvolumes
mount -o noatime,compress=zstd,space_cache=v2,discard=async,ssd,subvol=@ /dev/mapper/crypt_arch /mnt/arch &&
mkdir -p /mnt/arch/{boot/efi,home,.snapshots,.swap,var} &&
mount -o noatime,compress=zstd,space_cache=v2,discard=async,ssd,subvol=@home /dev/mapper/crypt_arch /mnt/arch/home &&
mount -o noatime,compress=zstd,space_cache=v2,discard=async,ssd,subvol=@snapshots /dev/mapper/crypt_arch /mnt/arch/.snapshots &&
mount -o compress=no,space_cache=v2,discard=async,ssd,subvol=@swap /dev/mapper/crypt_arch /mnt/arch/.swap &&
mount -o noatime,compress=zstd,space_cache=v2,discard=async,ssd,subvol=@var /dev/mapper/crypt_arch /mnt/arch/var

# Create swap
truncate -s 0 /mnt/arch/.swap/swapfile &&
chattr +C /mnt/arch/.swap/swapfile &&
btrfs property set /mnt/arch/.swap compression none &&
fallocate -l 16G /mnt/arch/.swap/swapfile &&
chmod 0600 /mnt/arch/.swap/swapfile &&
mkswap /mnt/arch/.swap/swapfile &&
swapon /mnt/arch/.swap/swapfile

# Mount the EFI partition
mount /dev/nvme0n1p1 /mnt/arch/boot/efi




# Arch setup

# Setup pacman and install base pkgs
sed -i "/\[multilib\]/,/Include/"'s/^#//' /etc/pacman.conf &&
sed -i "/Color/s/^#//" /etc/pacman.conf &&
sed -i "/ParallelDownloads/s/^#//" /etc/pacman.conf &&
reflector --country AT --latest 50 --sort rate --save /etc/pacman.d/mirrorlist &&
pacstrap /mnt/arch base base-devel linux vim openssh git intel-ucode btrfs-progs grub grub-btrfs efibootmgr

# Generate fstab
genfstab -U -p /mnt/arch >> /mnt/arch/etc/fstab

# Generate Keyfile to unlock boot and add to luks
dd bs=512 count=4 iflag=fullblock if=/dev/random of=/mnt/arch/crypto_keyfile.bin &&
chmod 600 /mnt/arch/crypto_keyfile.bin && 
arch-chroot /mnt/arch /bin/bash -c "cryptsetup luksAddKey /dev/nvme0n1p2 /crypto_keyfile.bin"

# edit conf initframes conf and generate
sed -i '/^BINARIES=/ s/()/(btrfs)/i' /mnt/arch/etc/mkinitcpio.conf &&
sed -i '/^FILES=/ s/()/(\/crypto_keyfile.bin)/i' /mnt/arch/etc/mkinitcpio.conf &&
sed -i '/^HOOKS=/ s/(.*)/\(base udev btrfs keyboard autodetect keymap consolefont modconf block encrypt filesystems fsck\)/i' /mnt/arch/etc/mkinitcpio.conf &&
arch-chroot /mnt/arch /bin/bash -c "mkinitcpio -p linux"

# edit default grub config
DISK='/dev/nvme0n1p2'
CRYPT_UUID=$( blkid -s UUID -o value $DISK ) && 
sed -i "s/GRUB_TIMEOUT=5/GRUB_TIMEOUT=3/g" /mnt/arch/etc/default/grub &&
# maybe set root= to not have to search for btrfs filesystem
# root=\/dev\/mapper\/cryptroot\
sed -i "/^GRUB_CMDLINE_LINUX_DEFAULT=/ s/\"loglevel=3 quiet\"/\"loglevel=3 quiet cryptdevice=UUID=$CRYPT_UUID\:crypt_arch\"/i" /mnt/arch/etc/default/grub &&
sed -i "/^GRUB_PRELOAD_MODULES=/ s/\".*\"/\"part_gpt part_msdos luks\"/i" /mnt/arch/etc/default/grub &&
sed -i "/^#GRUB_ENABLE_CRYPTODISK.*/s/^#//" /mnt/arch/etc/default/grub

# set grub vimix theme
arch-chroot /mnt/arch /bin/bash -c "git clone https://github.com/vinceliuice/grub2-themes.git /grub2-themes" &&
mkdir -p /mnt/arch/boot/grub/themes &&
/mnt/arch/grub2-themes/install.sh -t vimix -g /mnt/arch/boot/grub/themes &&
rm -rf /mnt/arch/grub2-themes &&
sed -i "s|.*GRUB_THEME=.*|GRUB_THEME=\"boot\/grub\/themes\/vimix/theme.txt\"|" /mnt/arch/etc/default/grub &&
sed -i "s|.*GRUB_GFXMODE=.*|GRUB_GFXMODE=1920x1080,auto|" /mnt/arch/etc/default/grub

# Install grub
arch-chroot /mnt/arch /bin/bash -c 'grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB' &&
arch-chroot /mnt/arch /bin/bash -c 'grub-mkconfig -o /boot/grub/grub.cfg'

# Set vconsole
echo "KEYMAP=de-latin1" > /mnt/arch/etc/vconsole.conf

# Locale
LOCALE='de_AT.UTF-8'
sed -i "/$LOCALE/s/^#//g" /mnt/arch/etc/locale.gen && 
arch-chroot /mnt/arch /bin/bash -c "locale-gen" && 
echo "LANG=$LOCALE" > /mnt/arch/etc/locale.conf

# Host
HOST='arsus'
echo "${HOST}" > /mnt/arch/etc/hostname
printf "127.0.0.1  localhost\n::1        localhost\n127.0.1.1  %s.local  %s\n" "$HOST" "$HOST" > /mnt/arch/etc/hosts

# Time
ln -s /usr/share/zoneinfo/Europe/Vienna /mnt/arch/etc/localtime
arch-chroot /mnt/arch /bin/bash -c "hwclock --systohc"


# Base system installed! ----------------------


# Install pkgs for desktop 
pacstrap /mnt/arch picom sxhkd sddm iwd powerdevil \
            ranger  rofi rofi-calc kdeconnect \
            neofetch man tldr reflector btop exa procs ripgrep \
            firefox kitty zsh dash neovim  thunderbird discord  \
            alsa-firmware alsa-ucm-conf sof-firmware pipewire pipewire-alsa pipewire-audio playerctl \
            bluedevil bluez bluez-utils blueberry


# Set dash as default shell
arch-chroot /mnt/arch /bin/bash -c "ln -sfT dash /usr/bin/sh" &&
    echo '[Trigger]
Type = Package
Operation = Install
Operation = Upgrade
Target = bash
[Action]
Description = Re-pointing /bin/sh symlink to dash...
When = PostTransaction
Exec = /usr/bin/ln -sfT dash /usr/bin/sh
Depends = dash' > /mnt/arch/usr/share/libalpm/hooks/update-bash.look


# Set root passwd
ROOT_PASS='root'
arch-chroot /mnt/arch /bin/bash -c "echo 'root:$ROOT_PASS' | chpasswd"


# Useradd
USER_NAME='fromml'
USER_PASS='2556'
arch-chroot /mnt/arch /bin/bash -c "useradd -mG wheel -s /usr/bin/zsh $USER_NAME && echo '$USER_NAME:$USER_PASS' | chpasswd"


# Install yay
## uncomment wheel
arch-chroot /mnt/arch /bin/bash -c "chmod +w /etc/sudoers &&
    sed -i 's/# %wheel ALL=(ALL:ALL) NOPASSWD: ALL/%wheel ALL=(ALL:ALL) NOPASSWD: ALL/g' /etc/sudoers &&
    chmod 0440 /etc/sudoers"


arch-chroot /mnt/arch /bin/bash -c "runuser -l $USER_NAME -c 'git clone https://aur.archlinux.org/yay-git.git ~/yay-git &&
    cd ~/yay-git &&
    makepkg -si --noconfirm &&
    rm -rf ~/yay-git &&
    yay -Syyyu timeshift-bin polybar-git ranger_devicons-git ncspot-cover awesome-git --noconfirm --removemake --rebuild'"


# Download dotfiles
arch-chroot /mnt/arch /bin/bash -c "git clone https://github.com/FromWau/dotfiles.git" 
    cp -r /mnt/arch/dotfiles/.zshenv /mnt/arch/home/"$USER_NAME" &&
    cp -r /mnt/arch/dotfiles/.config /mnt/arch/home/"$USER_NAME"


# Create playerctld.service
echo "[Unit]
Description=Keep track of media player activity
[Service]
Type=oneshot
ExecStart=/usr/bin/playerctld daemon
[Install]
WantedBy=default.target" > /mnt/arch/usr/lib/systemd/user/playerctld.service


# enable experimental bluetooth features to be able to see the bluetooth headset battery
sed -i "s/ExecStart\=\/usr\/lib\/bluetooth\/bluetoothd/ExecStart\=\/usr\/lib\/bluetooth\/bluetoothd --experimental/g" /mnt/arch/usr/lib/systemd/system/bluetooth.service


# Enable Services
arch-chroot /mnt/arch /bin/bash -c "systemctl enable NetworkManager &&
    systemctl enable sshd.service &&
    systemctl enable sddm.service &&
    systemctl enable cronie.service &&
    systemctl enable bluetooth.service &&
    systemctl enable upower.service &&
    systemctl --user enable playerctld.service"

# Setup NetworkManager use iwd as backend and copy already setup networks
printf "[device]\nwifi.backend=iwd" > /mnt/arch/etc/NetworkManager/conf.d/wifi_backend.conf && 
    mkdir -p /mnt/arch/var/lib/iwd/ &&
    cp -r /var/lib/iwd/* /mnt/arch/var/lib/iwd/


# Enable wheel properly
arch-chroot /mnt/arch /bin/bash -c "chmod +w /etc/sudoers &&
    sed -i 's/%wheel ALL=(ALL:ALL) NOPASSWD: ALL/# %wheel ALL=(ALL:ALL) NOPASSWD: ALL/g' /etc/sudoers &&
    sed -i 's/# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/g' /etc/sudoers &&
    chmod 0440 /etc/sudoers"



# Setup nvim
arch-chroot /mnt/arch /bin/bash -c "runuser -l $USER_NAME -c 'nvim --headless +source +PackerSync +qa'"


# Clean up home (remove cargo)
rm -rf /mnt/arch/home/"$USER_NAME"/.cargo



echo 'DONE'
echo 'for changing the keymap use:'
echo 'localectl set-x11-keymap de'
echo
echo 'to reboot run:'
echo 'umount -R /mnt/arch && reboot'


exit 0












# GENTOO
cryptsetup luksFormat --type luks2 --key-size 512 /dev/nvme0n1p3 &&
cryptsetup open /dev/nvme0n1p3 crypt_gentoo &&
mkfs.btrfs -L GENTOO /dev/mapper/crypt_gentoo

# Create mount points and ... mount
mkdir -p /mnt/{arch,gentoo} &&
mount /dev/mapper/crypt_arch /mnt/arch &&
mount /dev/mapper/crypt_gentoo /mnt/gentoo


# Create Subvolumes
btrfs sub create /mnt/gentoo/@ &&
btrfs sub create /mnt/gentoo/@home &&
btrfs sub create /mnt/gentoo/@snapshots &&
btrfs sub create /mnt/gentoo/@swap &&
btrfs sub create /mnt/gentoo/@var &&
umount /mnt/gentoo


# Mount everything properly
mount -o noatime,compress=zstd,space_cache=v2,discard=async,ssd,subvol=@ /dev/mapper/crypt_gentoo /mnt/gentoo &&
mkdir -p /mnt/gentoo/{boot,home,.snapshots,.swap,var} &&
mount -o noatime,compress=zstd,space_cache=v2,discard=async,ssd,subvol=@home /dev/mapper/crypt_gentoo /mnt/gentoo/home &&
mount -o noatime,compress=zstd,space_cache=v2,discard=async,ssd,subvol=@snapshots /dev/mapper/crypt_gentoo /mnt/gentoo/.snapshots &&
mount -o compress=no,space_cache=v2,discard=async,ssd,subvol=@swap /dev/mapper/crypt_gentoo /mnt/gentoo/.swap &&
mount -o noatime,compress=zstd,space_cache=v2,discard=async,ssd,subvol=@var /dev/mapper/crypt_gentoo /mnt/gentoo/var

# Create swap
truncate -s 0 /mnt/gentoo/.swap/swapfile &&
chattr +C /mnt/gentoo/.swap/swapfile &&
btrfs property set /mnt/gentoo/.swap compression none &&
fallocate -l 16G /mnt/gentoo/.swap/swapfile &&
chmod 600 /mnt/gentoo/.swap/swapfile &&
mkswap /mnt/gentoo/.swap/swapfile &&
swapon /mnt/gentoo/.swap/swapfile

# Mount the EFI partition
mount -o noatime,compress=zstd,space_cache=v2,discard=async,ssd /dev/nvme0n1p1 /mnt/gentoo/boot &&
mkdir -p /mnt/gentoo/boot/efi &&
mount /dev/nvme0n1p1 /mnt/gentoo/boot/efi



# Gentoo System setup

# Set date (manual)
date #MMDDhhmmYYYY

# Download stage3

cd /mnt/gentoo &&
links https://www.gentoo.org/downloads

# Unpack
tar xpvf stage3-*.tar.xz --xattrs-include='*.*' --numeric-owner


# Edit portgae make.conf
vi /mnt/gentoo/etc/portage/make.conf
# links of CPU names for march https://wiki.gentoo.org/wiki/Safe_CFLAGS
# At common flags add -march=<CPU name>



# Select mirrors (not working atm?)
mirrorselect -i -o >> /mnt/gentoo/etc/portage/make.conf


# eBuild
mkdir --parents /mnt/gentoo/etc/portage/repos.conf &&
cp /mnt/gentoo/usr/share/portage/config/repos.conf /mnt/gentoo/etc/portage/repos.conf/gentoo.conf

# cp DNS info
cp --dereference /etc/resolv.conf /mnt/gentoo/etc/

# mounting necessary filesystems
mount --types proc /proc /mnt/gentoo/proc &&
mount --rbind /sys /mnt/gentoo/sys &&
mount --make-rslave /mnt/gentoo/sys &&
mount --rbind /dev /mnt/gentoo/dev &&
mount --make-rslave /mnt/gentoo/dev &&
mount --bind /run /mnt/gentoo/run &&
mount --make-slave /mnt/gentoo/run


# Chroot
chroot /mnt/gentoo /bin/bash
source /etc/profile
export PS1="(chroot) ${PS1}"

# Mount boot (idk i did already but lets do it again?)
mount /dev/nvme0n1p1 /boot # says it is already mounted


# Install eBuild Repos
emerge-webrsync

emerge --sync 
# if opengpt error disable feature

nano /etc/portage/repos.conf/gentoo.conf
# set sync-rsync-verify-metamanifest = no



# Select profile
eselect profile list

# ERROR? looped checking sequence for 1 hour
# Update @world set (takes long)
emerge --ask --verbose --update --deep --newuse @world













