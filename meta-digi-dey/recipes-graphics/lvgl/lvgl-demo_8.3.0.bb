SUMMARY = "Wing Application"
HOMEPAGE = "https://github.com/digi-embedded/lv_port_linux_frame_buffer"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://LICENSE;md5=802d3d83ae80ef5f343050bf96cce3a4 \
                    file://lvgl/LICENCE.txt;md5=bf1198c89ae87f043108cea62460b03a"

SRCBRANCH ?= "ishanya-lvgl-yocto"

SRC_URI = " \
    gitsm://github.com/OmniSiteSoftware/WingsApp.git;branch=${SRCBRANCH};protocol=https \
    file://lvgl-demo-init \
    file://lvgl-demo-init.service \
    file://cert \
"

# Always fetch the latest commit from the branch.
SRCREV = "${AUTOREV}"
PV = "1.0+git${SRCPV}"

# Use the Makefile build system.
EXTRA_OEMAKE = "DESTDIR=${D}"

inherit pkgconfig update-rc.d systemd

DEPENDS += "\
    ffmpeg curl openssl json-c wayland libxkbcommon \
    libpng swupdate libconfuse recovery-utils libubootenv \
    libgpiod libsoc libdigiapix cccs \
    glib-2.0 \
    gstreamer1.0 \
    gstreamer1.0-plugins-base \
    gstreamer1.0-plugins-good \
    gstreamer1.0-plugins-bad \
    gstreamer1.0-plugins-ugly \
    gstreamer1.0-libav \
    gstreamer1.0-rtsp-server "

# Backend configuration variables.
MINIMAL_BACKEND ?= "fbdev"
MINIMAL_BACKEND:imxdrm = "drm"
MINIMAL_BACKEND:ccmp15 = "sdl"
PACKAGECONFIG = "${@bb.utils.contains('DISTRO_FEATURES', 'wayland', 'wayland', '${MINIMAL_BACKEND}', d)}"

# Inherit classes for systemd service and init script handling.
inherit update-rc.d systemd

# Set the source directory to the git checkout.
S = "${WORKDIR}/git"

# Provide additional include paths.
TARGET_CFLAGS += "-I${STAGING_INCDIR}/libdrm"

# Change DRM card used for i.MX8-based platforms.
LVGL_CONFIG_DRM_CARD:mx8-generic-bsp = "/dev/dri/card1"

# Display resolution configuration.
LVGL_CONFIG_HOR_RES ?= "800"
LVGL_CONFIG_VER_RES ?= "480"
LVGL_CONFIG_HOR_RES:ccimx6ul ?= "1280"
LVGL_CONFIG_VER_RES:ccimx6ul ?= "800"

# Disable the configuration step (if any).
do_configure() {
    :
    
}

# Modified do_compile that only does a clean build if the Git revision has changed.
do_compile() {
    # Use a persistent file in WORKDIR to record the last built revision.
    if [ -f ${WORKDIR}/.last_srcrev ]; then
        LAST_SRCREV=$(cat ${WORKDIR}/.last_srcrev)
    else
        LAST_SRCREV=""
    fi

    # If the Git revision has changed, perform a clean build.
    if [ "${SRCREV}" != "${LAST_SRCREV}" ]; then
        oe_runmake clean
    fi

    oe_runmake -j || die "Makefile build failed"

    # Record the current Git revision.
    echo "${SRCREV}" > ${WORKDIR}/.last_srcrev
}

# Weston service names for different targets.
WESTON_SERVICE ?= "weston.service"
WESTON_SERVICE:ccmp15 ?= "weston-launch.service"
WESTON_SERVICE:ccmp2 ?= "weston-launch.service"

# LVGL demo display and environment settings.
LVGL_DEMO_DISPLAY ?= "wayland-0"
LVGL_DEMO_DISPLAY:ccmp15 ?= "wayland-1"
LVGL_DEMO_DISPLAY:ccmp2 ?= "wayland-1"
LVGL_DEMO_DISPLAY:ccimx93 ?= "wayland-1"
LVGL_DEMO_ENV ?= "DISPLAY=:0.0 XDG_RUNTIME_DIR=/run/user/0 WAYLAND_DISPLAY=\$\{DEMO_DISPLAY\}"
LVGL_DEMO_ENV:ccimx6ul ?= ""

do_install:append() {
    # Install the binary built by the Makefile.
    install -d ${D}/etc
    install -m 0755 ${B}/wings_app ${D}/etc/wings_app
    
    # Create the target directory for certificates and copy all files.
    install -d ${D}/etc/cert
    cp -r ${WORKDIR}/cert/* ${D}/etc/cert/
    # Set all certificate files to read-only (0444) and directories to 0555.
    find ${D}/etc/cert -type f -exec chmod 0444 {} \;
    find ${D}/etc/cert -type d -exec chmod 0555 {} \;

    # Install systemd service unit if systemd is enabled.
    if ${@bb.utils.contains('DISTRO_FEATURES', 'systemd', 'true', 'false', d)}; then
        install -d ${D}${systemd_unitdir}/system
        install -m 0644 ${WORKDIR}/lvgl-demo-init.service ${D}${systemd_unitdir}/system/
        sed -i -e "s,##WESTON_SERVICE##,${WESTON_SERVICE},g" \
               "${D}${systemd_unitdir}/system/lvgl-demo-init.service"
    fi

    # Install the init script that launches the LVGL demo on boot.
    install -d ${D}${sysconfdir}/init.d
    install -m 0755 ${WORKDIR}/lvgl-demo-init ${D}${sysconfdir}/lvgl-demo-init
    sed -i -e "s@##LVGL_DEMO_DISPLAY##@${LVGL_DEMO_DISPLAY}@g" \
           -e "s@##LVGL_DEMO_ENV##@${LVGL_DEMO_ENV}@g" \
           "${D}${sysconfdir}/lvgl-demo-init"
    ln -sf ${sysconfdir}/lvgl-demo-init ${D}${sysconfdir}/init.d/lvgl-demo-init
}

PACKAGES += "${PN}-init"
FILES:${PN}-init = " \
    ${sysconfdir}/lvgl-demo-init \
    ${sysconfdir}/init.d/lvgl-demo-init \
    ${systemd_unitdir}/system/lvgl-demo-init.service \
    /etc/cert/ \
    /etc/wings_app \
"

INITSCRIPT_PACKAGES += "${PN}-init"
INITSCRIPT_NAME:${PN}-init = "lvgl-demo-init"
INITSCRIPT_PARAMS:${PN}-init = "start 99 3 5 . stop 20 0 1 2 6 ."

SYSTEMD_PACKAGES = "${PN}-init"
SYSTEMD_SERVICE:${PN}-init = "lvgl-demo-init.service"

COMPATIBLE_MACHINE = "(ccimx6$|ccimx6ul|ccimx8m|ccimx8x|ccimx93|ccmp15|ccmp2)"
