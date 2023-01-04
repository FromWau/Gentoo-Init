#!/bin/bash

# new root pass
passwd root


# start sshd
/etc/init.d/sshd start


# Connect to Internet (IDK how to WLAN)
net-setup

# Check if internet OK
ping -c3 orf.at



# Disk setup (IDK if that works)

# delete everything
wipefs /dev/nvme0n1

# create new partitions
# nvme0n1p1 EFI 512M
# nvme0n1p2 LINUX 250G
# nvme0n1p3 LINUX rest
cfdisk

# Create filesystems
# EFI
mkfs.vfat -F 32 -n "EFI" /dev/nvme0n1p1

# ARCH
cryptsetup luksFormat --type luks2 --key-size 512 /dev/nvme0n1p2 &&
cryptsetup open /dev/nvme0n1p2 crypt_arch &&
mkfs.btrfs -L ARCH /dev/mapper/crypt_arch


#GENTOO
cryptsetup luksFormat --type luks2 --key-size 512 /dev/nvme0n1p3 &&
cryptsetup open /dev/nvme0n1p3 crypt_gentoo &&
mkfs.btrfs -L GENTOO /dev/mapper/crypt_gentoo

# Create mount points and ... mount
mkdir -p /mnt/{arch,gentoo} &&
mount /dev/mapper/crypt_arch /mnt/arch &&
mount /dev/mapper/crypt_gentoo /mnt/gentoo


# Create Subvolumes
# Arch
btrfs sub create /mnt/arch/@ &&
btrfs sub create /mnt/arch/@home &&
btrfs sub create /mnt/arch/@snapshots &&
btrfs sub create /mnt/arch/@swap &&
btrfs sub create /mnt/arch/@var &&
umount /mnt/arch

# Gentoo
btrfs sub create /mnt/gentoo/@ &&
btrfs sub create /mnt/gentoo/@home &&
btrfs sub create /mnt/gentoo/@snapshots &&
btrfs sub create /mnt/gentoo/@swap &&
btrfs sub create /mnt/gentoo/@var &&
umount /mnt/gentoo



# Mount everything properly
# Arch
mount -o noatime,compress=zstd,space_cache=v2,discard=async,ssd,subvol=@ /dev/mapper/crypt_arch /mnt/arch &&
mkdir -p /mnt/arch/{boot,home,.snapshots,.swap,var} &&
mount -o noatime,compress=zstd,space_cache=v2,discard=async,ssd,subvol=@home /dev/mapper/crypt_arch /mnt/arch/home &&
mount -o noatime,compress=zstd,space_cache=v2,discard=async,ssd,subvol=@snapshots /dev/mapper/crypt_arch /mnt/arch/.snapshots &&
mount -o compress=no,space_cache=v2,discard=async,ssd,subvol=@swap /dev/mapper/crypt_arch /mnt/arch/.swap &&
mount -o noatime,compress=zstd,space_cache=v2,discard=async,ssd,subvol=@var /dev/mapper/crypt_arch /mnt/arch/var

# Create swap
truncate -s 0 /mnt/arch/.swap/swapfile &&
chattr +C /mnt/arch/.swap/swapfile &&
btrfs property set /mnt/arch/.swap/swapfile compression none &&
fallocate -l 16G /mnt/arch/.swap/swapfile &&
chmod 600 /mnt/arch/.swap/swapfile &&
mkswap /mnt/arch/.swap/swapfile &&
swapon /mnt/arch/.swap/swapfile

# Mount the EFI partition
mount /dev/nvme0n1p1 /mnt/arch/boot



# Gentoo
mount -o noatime,compress=zstd,space_cache=v2,discard=async,ssd,subvol=@ /dev/mapper/crypt_gentoo /mnt/gentoo &&
mkdir -p /mnt/gentoo/{boot,home,.snapshots,.swap,var} &&
mount -o noatime,compress=zstd,space_cache=v2,discard=async,ssd,subvol=@home /dev/mapper/crypt_gentoo /mnt/gentoo/home &&
mount -o noatime,compress=zstd,space_cache=v2,discard=async,ssd,subvol=@snapshots /dev/mapper/crypt_gentoo /mnt/gentoo/.snapshots &&
mount -o compress=no,space_cache=v2,discard=async,ssd,subvol=@swap /dev/mapper/crypt_gentoo /mnt/gentoo/.swap &&
mount -o noatime,compress=zstd,space_cache=v2,discard=async,ssd,subvol=@var /dev/mapper/crypt_gentoo /mnt/gentoo/var

# Create swap
truncate -s 0 /mnt/gentoo/.swap/swapfile &&
chattr +C /mnt/gentoo/.swap/swapfile &&
btrfs property set /mnt/gentoo/.swap/swapfile compression none &&
fallocate -l 16G /mnt/gentoo/.swap/swapfile &&
chmod 600 /mnt/gentoo/.swap/swapfile &&
mkswap /mnt/gentoo/.swap/swapfile &&
swapon /mnt/gentoo/.swap/swapfile

# Mount the EFI partition
mount /dev/nvme0n1p1 /mnt/gentoo/boot


# Disk done (still need to do the cryp uuid stuff for fstab)


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













