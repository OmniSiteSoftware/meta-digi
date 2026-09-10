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
PERSISTENT_DATA_DIR="@@SWUPDATE_OVERLAYFS_ETC_MOUNT_POINT@@"
BACKUP_DIR="${PERSISTENT_DATA_DIR}/swupdate-wings-config-backup"
PRESERVED_ITEMS="cert config.json plc_settings.json stats.json"
OVERLAY_ETC_UPPER_DIR="${PERSISTENT_DATA_DIR}/overlay-etc/upper"
REFRESHED_ETC_ITEMS="@@SWUPDATE_OVERLAYFS_ETC_REFRESH_LIST@@"
NM_CONNECTIONS_DIR="/etc/NetworkManager/system-connections"
NM_BACKUP_DIR="${BACKUP_DIR}/NetworkManager/system-connections"
TARGET_ROOTFS_MOUNT="${PERSISTENT_DATA_DIR}/swupdate-target-rootfs"
TARGET_UBI_ROOTFS_VOLUMES="rootfs rootfs_a rootfs_b"
OTA_STATUS_DIR="/etc/wings/fw-update"
OTA_STATUS_FILE="${OTA_STATUS_DIR}/software-update-status.json"

timestamp_utc() {
	date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date
}

json_escape() {
	printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

read_ota_status_field() {
	key="${1}"

	[ -r "${OTA_STATUS_FILE}" ] || return 1
	sed -n "s/.*\"${key}\"[[:space:]]*:[[:space:]]*\"\\{0,1\\}\\([^\",}]*\\)\"\\{0,1\\}.*/\\1/p" "${OTA_STATUS_FILE}" | head -n 1
}

write_ota_status() {
	status="${1}"
	phase="${2}"
	message="${3}"
	rc="${4:-0}"
	error_stage="${5:-}"
	ts="$(timestamp_utc)"
	active="true"
	component="system_firmware"
	source="$(read_ota_status_field source || true)"
	started_at="$(read_ota_status_field started_at || true)"
	update_id="$(read_ota_status_field update_id || true)"
	package_name="$(read_ota_status_field package_name || true)"
	expected_version="$(read_ota_status_field expected_version || true)"
	current_version="$(read_ota_status_field current_version || true)"
	rc_json="${rc}"
	error_stage_json="null"
	completed_at_json="null"

	case "${status}" in
		success|failed|blocked|verify_failed|interrupted) active="false" ;;
	esac
	case "${status}" in
		success|failed|blocked|verify_failed|interrupted) ;;
		*) rc_json="null" ;;
	esac
	if [ -n "${error_stage}" ]; then
		error_stage_json="\"$(json_escape "${error_stage}")\""
	fi
	if [ "${active}" = "false" ]; then
		completed_at_json="\"${ts}\""
	fi
	[ -n "${source}" ] || source="drm"
	[ -n "${started_at}" ] || started_at="${ts}"
	[ -n "${update_id}" ] || update_id="${started_at}-${component}"

	mkdir -p "${OTA_STATUS_DIR}" 2>/dev/null || true
	{
		printf '{\n'
		printf '  "reportType": "ota_status",\n'
		printf '  "active": %s,\n' "${active}"
		printf '  "update_id": "%s",\n' "$(json_escape "${update_id}")"
		printf '  "component": "%s",\n' "${component}"
		printf '  "source": "%s",\n' "$(json_escape "${source}")"
		printf '  "phase": "%s",\n' "$(json_escape "${phase}")"
		printf '  "status": "%s",\n' "$(json_escape "${status}")"
		printf '  "package_name": "%s",\n' "$(json_escape "${package_name}")"
		printf '  "expected_version": "%s",\n' "$(json_escape "${expected_version}")"
		printf '  "current_version": "%s",\n' "$(json_escape "${current_version}")"
		printf '  "port": null,\n'
		printf '  "return_code": %s,\n' "${rc_json}"
		printf '  "error_stage": %s,\n' "${error_stage_json}"
		printf '  "message": "%s",\n' "$(json_escape "${message}")"
		printf '  "recovery_action": "Device should reboot into the updated A/B bank after SWUpdate completes",\n'
		printf '  "reboot_required": true,\n'
		printf '  "started_at": "%s",\n' "${started_at}"
		printf '  "completed_at": %s,\n' "${completed_at_json}"
		printf '  "timestamp": "%s"\n' "${ts}"
		printf '}\n'
	} > "${OTA_STATUS_FILE}.tmp" && mv "${OTA_STATUS_FILE}.tmp" "${OTA_STATUS_FILE}"
}

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

remove_overlayfs_etc_entry() {
	item="${1}"
	entry="${OVERLAY_ETC_UPPER_DIR}/${item}"
	parent_dir="$(dirname "${entry}")"
	base_name="$(basename "${entry}")"
	whiteout="${parent_dir}/.wh.${base_name}"

	if [ -e "${entry}" ] || [ -L "${entry}" ]; then
		rm -rf "${entry}"
		echo "Removed stale /etc overlay entry ${entry}"
	fi

	if [ -e "${whiteout}" ] || [ -L "${whiteout}" ]; then
		rm -rf "${whiteout}"
		echo "Removed stale /etc overlay whiteout ${whiteout}"
	fi
}

clear_refreshed_files_from_overlayfs_etc() {
	if [ ! -d "${OVERLAY_ETC_UPPER_DIR}" ]; then
		echo "Skipping /etc overlay cleanup; ${OVERLAY_ETC_UPPER_DIR} not found"
		return
	fi

	echo "Clearing rootfs-owned /etc files from overlay so updated image versions are used"
	for item in ${REFRESHED_ETC_ITEMS}; do
		remove_overlayfs_etc_entry "${item}"
	done
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
	write_ota_status "running" "pre_update" "Full image SWU preinstall started" 0
	backup_wings_config_files

	# TODO: Execute custom code here. For example:
	# - Mount additional devices/partitions.
	# - Stop services/process before installing files.
fi

# Called just after installation process ends.
if [ "${1}" = "postinst" ]; then
	restore_wings_config_files
	clear_refreshed_files_from_overlayfs_etc
	write_ota_status "success" "post_update" "Full image SWU completed successfully" 0

	# TODO: Execute custom code here. For example:
	# - Clean files/directories.
	# - Post-process files.
fi

if [ "${1}" = "postfailure" ]; then
	write_ota_status "failed" "post_update" "Full image SWU failed" 1 "swupdate"
fi
