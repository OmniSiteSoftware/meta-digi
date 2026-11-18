# Wings Rev D product profile. Keep the existing DVK/512 MB descriptions available.
WINGS_BOARD_PROFILE = "revd-1gb"
KERNEL_DEVICETREE:append = " ccmp157-wings-revd.dtb"
# Guard the final compressed image, not its larger uncompressed root directory.
WINGS_ROOTFS_SLOT_BYTES = "167772160"
