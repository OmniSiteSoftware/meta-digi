FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"

SUMMARY = "Minute-by-minute append-only syslog backup to USB/SD with pruning"

LICENSE = "MIT"

LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI += " \
    file://syslog-sync.service \
    file://syslog-sync.timer \
"

inherit allarch systemd

# -----------------------------------------------------------------------------
# 1) Ship exactly those two unit files under /lib/systemd/system
# -----------------------------------------------------------------------------
FILES:${PN} += " \
    ${systemd_system_unitdir}/syslog-sync.service \
    ${systemd_system_unitdir}/syslog-sync.timer \
"

# -----------------------------------------------------------------------------
# 2) Install them into that directory
# -----------------------------------------------------------------------------
do_install:append() {
    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${WORKDIR}/syslog-sync.service \
        ${D}${systemd_system_unitdir}/syslog-sync.service
    install -m 0644 ${WORKDIR}/syslog-sync.timer  \
        ${D}${systemd_system_unitdir}/syslog-sync.timer
}

# -----------------------------------------------------------------------------
# 3) Register & auto-enable our timer (the .service is implicit)
# -----------------------------------------------------------------------------
SYSTEMD_SERVICE:${PN} = "syslog-sync.timer"
SYSTEMD_AUTO_ENABLE:${PN} = "enable"
SYSTEMD_PACKAGES += "${PN}"
