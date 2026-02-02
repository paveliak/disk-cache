#!/bin/bash
set -euo pipefail

# Set up dm-cache with RAM disk for /home and /var
# No persistence - data lost on reboot (fine for CI)
# Reference: https://www.tunbury.org/2025/09/04/dm-cache/

echo "dm-cache-ramdisk: Starting..."

# Calculate 10% of total RAM in KB
TOTAL_RAM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
CACHE_SIZE_KB=$((TOTAL_RAM_KB / 10))

# Split between /home and /var (50% each)
CACHE_PER_MOUNT_KB=$((CACHE_SIZE_KB / 2))
META_SIZE_KB=$((CACHE_PER_MOUNT_KB / 100))
DATA_SIZE_KB=$((CACHE_PER_MOUNT_KB - META_SIZE_KB))

echo "dm-cache-ramdisk: Total RAM: $((TOTAL_RAM_KB / 1024)) MB"
echo "dm-cache-ramdisk: Cache per mount: $((CACHE_PER_MOUNT_KB / 1024)) MB"

# Load modules
modprobe brd rd_nr=1 rd_size=$((CACHE_SIZE_KB * 1024))
modprobe dm-cache
modprobe dm-cache-smq

sleep 1

# Calculate sizes in 512-byte sectors
META_SECTORS=$((META_SIZE_KB * 2))
DATA_SECTORS=$((DATA_SIZE_KB * 2))

setup_cached_mount() {
    local name="$1"
    local mount_point="$2"
    local meta_offset="$3"
    local data_offset="$4"
    
    echo "dm-cache-ramdisk: Setting up cache for $mount_point"
    
    # Find current backing device for mount point
    local backing_dev=$(findmnt -n -o SOURCE "$mount_point" 2>/dev/null || findmnt -n -o SOURCE /)
    backing_dev=$(readlink -f "$backing_dev")
    local backing_sectors=$(blockdev --getsz "$backing_dev")
    
    # Unmount current
    if mountpoint -q "$mount_point"; then
        umount "$mount_point" || umount -l "$mount_point"
    fi
    
    # Create cache meta and data from RAM disk at specified offsets
    dmsetup create "cache-meta-$name" --table "0 $META_SECTORS linear /dev/ram0 $meta_offset"
    dmsetup create "cache-data-$name" --table "0 $DATA_SECTORS linear /dev/ram0 $data_offset"
    
    # Create cached device
    dmsetup create "cached-$name" --table "0 $backing_sectors cache /dev/mapper/cache-meta-$name /dev/mapper/cache-data-$name $backing_dev 256 1 writeback smq 2 migration_threshold 100"
    
    # Mount
    mount "/dev/mapper/cached-$name" "$mount_point"
    
    echo "dm-cache-ramdisk: $mount_point mounted with dm-cache"
    dmsetup status "cached-$name"
}

# Layout on RAM disk: [var-meta][var-data][home-meta][home-data]
VAR_META_OFF=0
VAR_DATA_OFF=$META_SECTORS
HOME_META_OFF=$((META_SECTORS + DATA_SECTORS))
HOME_DATA_OFF=$((META_SECTORS + DATA_SECTORS + META_SECTORS))

# Set up cached mounts
setup_cached_mount "var" "/var" "$VAR_META_OFF" "$VAR_DATA_OFF"
setup_cached_mount "home" "/home" "$HOME_META_OFF" "$HOME_DATA_OFF"

echo "dm-cache-ramdisk: Setup complete"
