SUMMARY = "Minute-by-minute append-only syslog backup to USB/SD with pruning"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

PV = "1.0"
PR = "r0"

SRC_URI = " \
    file://syslog-sync.sh \
    file://syslog-sync.cron \
"

inherit update-rc.d

# we’ll ship the cron-spool file too
INSANE_SKIP_${PN} += "installed-vs-shipped"

# Enable BusyBox crond on boot (SysV style)
INITSCRIPT_NAME = "crond"
INITSCRIPT_PARAMS = "defaults"

# Ensure we have the cron daemon
RDEPENDS_${PN} = "busybox busybox-initscripts"

# Package both the script and the cron-spool entry
FILES_${PN} = " \
    ${bindir}/syslog-sync.sh \
    /var/spool/cron/crontabs/root \
"

do_install() {
    # 1) Script → /usr/bin
    install -d ${D}${bindir}
    install -m 0755 ${WORKDIR}/syslog-sync.sh ${D}${bindir}/syslog-sync.sh

    # 2) Cron-spool entry → /var/spool/cron/crontabs/root
    install -d ${D}/var/spool/cron/crontabs
    install -m 600 ${WORKDIR}/syslog-sync.cron ${D}/var/spool/cron/crontabs/root
}
