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

HOME_ROOT_DIR="/home/root"
PERSISTENT_DATA_DIR="/mnt/data"
BACKUP_DIR="${PERSISTENT_DATA_DIR}/swupdate-home-root-backup"
PRESERVED_ITEMS="cert config.json plc_settings.json stats.json"

backup_home_root_files() {
	echo "Backing up persistent /home/root files to ${BACKUP_DIR}"
	mkdir -p "${BACKUP_DIR}"

	for item in ${PRESERVED_ITEMS}; do
		src="${HOME_ROOT_DIR}/${item}"
		dst="${BACKUP_DIR}/${item}"

		if [ -e "${src}" ]; then
			rm -rf "${dst}"
			cp -a "${src}" "${dst}"
			echo "Backed up ${src} to ${dst}"
		else
			echo "Skipping ${src}; file or directory not found"
		fi
	done
}

restore_home_root_files() {
	echo "Restoring persistent /home/root files from ${BACKUP_DIR}"
	mkdir -p "${HOME_ROOT_DIR}"

	for item in ${PRESERVED_ITEMS}; do
		src="${BACKUP_DIR}/${item}"
		dst="${HOME_ROOT_DIR}/${item}"

		if [ -e "${src}" ]; then
			rm -rf "${dst}"
			cp -a "${src}" "${dst}"
			echo "Restored ${src} to ${dst}"
		else
			echo "Skipping ${src}; backup not found"
		fi
	done
}

# Called just before installation process starts.
if [ "${1}" = "preinst" ]; then
	backup_home_root_files

	# TODO: Execute custom code here. For example:
	# - Mount additional devices/partitions.
	# - Stop services/process before installing files.
fi

# Called just after installation process ends.
if [ "${1}" = "postinst" ]; then
	restore_home_root_files

	# TODO: Execute custom code here. For example:
	# - Clean files/directories.
	# - Post-process files.
fi
