#!/bin/sh
#===============================================================================
#
#  update_images
#
#  Copyright (C) 2023 by Digi International Inc.
#  All rights reserved.
#
#  This program is free software; you can redistribute it and/or modify it
#  under the terms of the GNU General Public License version 2 as published by
#  the Free Software Foundation.
#
#
#  !Description: SWU update images script
#
#===============================================================================

# Sanity check. This script should be always executed with at least one argument.
if [ $# -lt 1 ]; then
	exit 1;
fi

WINGS_CONFIG_DIR="/etc/wings"
LEGACY_HOME_ROOT_DIR="/home/root"
PERSISTENT_DATA_DIR="/mnt/data"
BACKUP_DIR="${PERSISTENT_DATA_DIR}/swupdate-wings-config-backup"
PRESERVED_ITEMS="cert config.json plc_settings.json stats.json"
NM_CONNECTIONS_DIR="/etc/NetworkManager/system-connections"
NM_BACKUP_DIR="${BACKUP_DIR}/NetworkManager/system-connections"
TARGET_ROOTFS_MOUNT="${PERSISTENT_DATA_DIR}/swupdate-target-rootfs"
TARGET_UBI_ROOTFS_VOLUMES="rootfs rootfs_a rootfs_b"

backup_wings_config_files() {
	echo "Backing up persistent Wings configuration to ${BACKUP_DIR}"
	mkdir -p "${BACKUP_DIR}"

	for item in ${PRESERVED_ITEMS}; do
		src="${WINGS_CONFIG_DIR}/${item}"
		legacy_src="${LEGACY_HOME_ROOT_DIR}/${item}"
		dst="${BACKUP_DIR}/${item}"

		if [ ! -e "${src}" ] && [ -e "${legacy_src}" ]; then
			src="${legacy_src}"
		fi

		if [ -e "${src}" ]; then
			rm -rf "${dst}"
			cp -a "${src}" "${dst}"
			echo "Backed up ${src} to ${dst}"
		else
			echo "Skipping ${src}; file or directory not found"
		fi
	done

	backup_networkmanager_connections
}

backup_networkmanager_connections() {
	echo "Backing up NetworkManager connections from ${NM_CONNECTIONS_DIR} to ${NM_BACKUP_DIR}"

	if [ ! -d "${NM_CONNECTIONS_DIR}" ]; then
		echo "Skipping ${NM_CONNECTIONS_DIR}; directory not found"
		return
	fi

	rm -rf "${NM_BACKUP_DIR}"
	mkdir -p "$(dirname "${NM_BACKUP_DIR}")"
	cp -a "${NM_CONNECTIONS_DIR}" "${NM_BACKUP_DIR}"
	echo "Backed up NetworkManager connections to ${NM_BACKUP_DIR}"
}

restore_wings_config_files() {
	restore_wings_config_files_to "${WINGS_CONFIG_DIR}"
	restore_networkmanager_connections_to_root "/"
	restore_wings_config_files_to_ubi_rootfs
}

restore_wings_config_files_to() {
	restore_dir="${1}"

	echo "Restoring persistent Wings configuration from ${BACKUP_DIR} to ${restore_dir}"
	mkdir -p "${restore_dir}"

	for item in ${PRESERVED_ITEMS}; do
		src="${BACKUP_DIR}/${item}"
		dst="${restore_dir}/${item}"

		if [ -e "${src}" ]; then
			rm -rf "${dst}"
			cp -a "${src}" "${dst}"
			echo "Restored ${src} to ${dst}"
		else
			echo "Skipping ${src}; backup not found"
		fi
	done
}

restore_networkmanager_connections_to_root() {
	root_dir="${1}"
	src="${NM_BACKUP_DIR}"

	if [ "${root_dir}" = "/" ]; then
		dst="${NM_CONNECTIONS_DIR}"
	else
		dst="${root_dir}${NM_CONNECTIONS_DIR}"
	fi

	echo "Restoring NetworkManager connections from ${src} to ${dst}"

	if [ ! -d "${src}" ]; then
		echo "Skipping ${src}; backup not found"
		return
	fi

	rm -rf "${dst}"
	mkdir -p "$(dirname "${dst}")"
	cp -a "${src}" "${dst}"
	echo "Restored NetworkManager connections to ${dst}"
}

get_mtd_number() {
	mtd_line="$(sed -ne "/${1}/s,^mtd\([0-9]\+\).*,\1,g;T;p" /proc/mtd)"
	echo "${mtd_line:--1}"
}

create_ubi_device() {
	dev_number="$(ubiattach -m "${1}" 2>/dev/null | sed -ne 's,.*device number \([0-9]\).*,\1,g;T;p' 2>/dev/null)"
	echo "${dev_number:--1}"
}

get_ubi_device() {
	volume_name="${1}"
	ubi_devices="$(ubinfo | grep "Present UBI devices:" | cut -d ":" -f2 | xargs | sed -e 's/,//g')"

	for ubi_device in ${ubi_devices}; do
		if ubinfo "/dev/${ubi_device}" -a | grep -qe "Name:.*${volume_name}"; then
			echo "${ubi_device}" | tr -dc '0-9'
			return 0
		fi
	done

	mtd_num="$(get_mtd_number "${volume_name}")"
	if [ "${mtd_num}" = "-1" ]; then
		echo "-1"
		return 1
	fi

	create_ubi_device "${mtd_num}"
}

is_mount_source_mounted() {
	mount_source="${1}"

	grep -q "[[:space:]]${mount_source}[[:space:]]" /proc/mounts || grep -q "^${mount_source}[[:space:]]" /proc/mounts
}

is_active_rootfs_squashfs() {
	awk '$2 == "/" && $3 == "squashfs" { found = 1 } END { exit !found }' /proc/mounts
}

restore_wings_config_files_to_ubi_rootfs() {
	if ! command -v ubinfo >/dev/null 2>&1; then
		echo "Skipping UBI rootfs restore; ubinfo not available"
		return
	fi

	if is_active_rootfs_squashfs; then
		echo "Skipping UBI rootfs restore; read-only SquashFS rootfs cannot be modified"
		return
	fi

	for volume_name in ${TARGET_UBI_ROOTFS_VOLUMES}; do
		ubi_device="$(get_ubi_device "${volume_name}")"
		if [ "${ubi_device}" = "-1" ]; then
			echo "Skipping UBI volume ${volume_name}; volume not found"
			continue
		fi

		mount_source="ubi${ubi_device}:${volume_name}"
		if is_mount_source_mounted "${mount_source}"; then
			echo "Skipping ${mount_source}; UBI volume is already mounted"
			continue
		fi

		echo "Mounting ${mount_source} at ${TARGET_ROOTFS_MOUNT} to restore persistent files"
		mkdir -p "${TARGET_ROOTFS_MOUNT}"
		if mount -t ubifs "${mount_source}" "${TARGET_ROOTFS_MOUNT}"; then
			restore_wings_config_files_to "${TARGET_ROOTFS_MOUNT}${WINGS_CONFIG_DIR}"
			restore_networkmanager_connections_to_root "${TARGET_ROOTFS_MOUNT}"
			sync
			umount "${TARGET_ROOTFS_MOUNT}"
			echo "Restored persistent files into ${mount_source}"
		else
			echo "Skipping ${mount_source}; unable to mount as ubifs"
		fi
	done
}

# Called just before installation process starts.
if [ "${1}" = "preinst" ]; then
	backup_wings_config_files

	# TODO: Execute custom code here. For example:
	# - Mount additional devices/partitions.
	# - Stop services/process before installing files.
fi

# Called just after installation process ends.
if [ "${1}" = "postinst" ]; then
	restore_wings_config_files

	# TODO: Execute custom code here. For example:
	# - Clean files/directories.
	# - Post-process files.
fi
