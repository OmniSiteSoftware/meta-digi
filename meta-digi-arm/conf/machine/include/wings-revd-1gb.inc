# Wings Rev D product profile. Keep the existing DVK/512 MB descriptions available.
WINGS_BOARD_PROFILE = "revd-1gb"
# Digi dboot uses the FIT default configuration, not fdt_file, in FIT mode.
# kernel-fitimage makes the first DTB the default; retain all legacy entries.
KERNEL_DEVICETREE:prepend = "ccmp157-wings-revd.dtb "
# Guard the final compressed image, not its larger uncompressed root directory.
WINGS_ROOTFS_SLOT_BYTES = "167772160"
