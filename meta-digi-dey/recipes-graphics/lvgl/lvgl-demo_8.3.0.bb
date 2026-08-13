SUMMARY = "Wing Application"
HOMEPAGE = "https://github.com/digi-embedded/lv_port_linux_frame_buffer"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://LICENSE;md5=802d3d83ae80ef5f343050bf96cce3a4 \
                    file://lvgl/LICENCE.txt;md5=bf1198c89ae87f043108cea62460b03a"

SRCBRANCH ?= "master_stage"

SRC_URI = " \
    gitsm://git@github.com/OmniSiteSoftware/WingsApp.git;branch=${SRCBRANCH};protocol=ssh \
    file://wings.service \
    file://wings-launcher \
    file://wings-log-manager.service \
    file://wings-log-manager \
    file://99-eth1-100mbps \
    file://cert \
"

# Always fetch the latest commit from the branch.
SRCREV = "${AUTOREV}"
PV = "1.0+git${SRCPV}"

# Use the Makefile build system.
EXTRA_OEMAKE = "DESTDIR=${D}"

inherit pkgconfig systemd

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
    gstreamer1.0-rtsp-server \
    networkmanager "
DEPENDS += "${@oe.utils.conditional('TRUSTFENCE_SIGN', '1', 'openssl-native trustfence-sign-tools-native', '', d)}"

# Backend configuration variables.
MINIMAL_BACKEND ?= "fbdev"
MINIMAL_BACKEND:imxdrm = "drm"
MINIMAL_BACKEND:ccmp15 = "sdl"
PACKAGECONFIG = "${@bb.utils.contains('DISTRO_FEATURES', 'wayland', 'wayland', '${MINIMAL_BACKEND}', d)}"
PACKAGECONFIG[wayland] = ",,wayland libxkbcommon"
PACKAGECONFIG[fbdev] = ",,"
PACKAGECONFIG[drm] = ",,libdrm"
PACKAGECONFIG[sdl] = ",,"

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
WINGS_AWS_IOT_ENDPOINT ?= "a1sfjfagbw2oyq-ats.iot.us-east-2.amazonaws.com"

do_install:append() {
    # Create the writable configuration directory backed by overlayfs-etc.
    install -d ${D}${sysconfdir}/wings

    printf 'WINGS_AWS_IOT_ENDPOINT=%s\n' "${WINGS_AWS_IOT_ENDPOINT}" > ${D}${sysconfdir}/wings/wings.env
    chmod 0644 ${D}${sysconfdir}/wings/wings.env

    # Install the binary where file-based SWU can update it on read-only rootfs.
    install -m 0755 ${B}/wings_app ${D}${sysconfdir}/wings/wings_app

    if [ "${TRUSTFENCE_SIGN}" = "1" ]; then
        TRUSTFENCE_KEYS_DIR="${TRUSTFENCE_SIGN_KEYS_PATH}"
        if [ "${TRUSTFENCE_KEYS_DIR}" = "default" ]; then
            TRUSTFENCE_KEYS_DIR="${TOPDIR}/trustfence"
        fi

        export CONFIG_SIGN_KEYS_PATH="${TRUSTFENCE_KEYS_DIR}"
        trustfence-gen-pki.sh -p "${DIGI_SOM}"

        if [ "${DIGI_SOM}" = "ccmp15" ]; then
            TRUSTFENCE_PRIVATE_KEY="${TRUSTFENCE_KEYS_DIR}/keys/privateKey.pem"
            TRUSTFENCE_PUBLIC_KEY="${TRUSTFENCE_KEYS_DIR}/keys/publicKey.pem"
            TRUSTFENCE_PASSWORD_FILE="${TRUSTFENCE_KEYS_DIR}/keys/key_pass.txt"
        elif [ "${DIGI_SOM}" = "ccmp13" ]; then
            TRUSTFENCE_PRIVATE_KEY="${TRUSTFENCE_KEYS_DIR}/keys/privateKey0${TRUSTFENCE_KEY_INDEX}.pem"
            TRUSTFENCE_PUBLIC_KEY="${TRUSTFENCE_KEYS_DIR}/keys/publicKey0${TRUSTFENCE_KEY_INDEX}.pem"
            TRUSTFENCE_PASSWORD_FILE="${TRUSTFENCE_KEYS_DIR}/keys/key_pass0${TRUSTFENCE_KEY_INDEX}.txt"
        else
            die "Unsupported DIGI_SOM for WingsApp signing: ${DIGI_SOM}"
        fi

        [ -f "${TRUSTFENCE_PRIVATE_KEY}" ] || die "Missing TrustFence private key: ${TRUSTFENCE_PRIVATE_KEY}"
        [ -f "${TRUSTFENCE_PUBLIC_KEY}" ] || die "Missing TrustFence public key: ${TRUSTFENCE_PUBLIC_KEY}"
        [ -f "${TRUSTFENCE_PASSWORD_FILE}" ] || die "Missing TrustFence password file: ${TRUSTFENCE_PASSWORD_FILE}"

        openssl dgst -sha256 \
            -sign "${TRUSTFENCE_PRIVATE_KEY}" \
            -passin file:"${TRUSTFENCE_PASSWORD_FILE}" \
            -out "${D}${sysconfdir}/wings/wings_app.sig" \
            "${D}${sysconfdir}/wings/wings_app"

        [ -s "${D}${sysconfdir}/wings/wings_app.sig" ] || die "Failed to generate WingsApp signature"

        install -d ${D}${datadir}/wings
        install -m 0644 "${TRUSTFENCE_PUBLIC_KEY}" ${D}${datadir}/wings/trustfence_key.pub
    fi

    if [ -f ${S}/config.json ]; then
        install -m 0644 ${S}/config.json ${D}${sysconfdir}/wings/config.json
    fi
    if [ -f ${S}/plc_settings.json ]; then
        install -m 0644 ${S}/plc_settings.json ${D}${sysconfdir}/wings/plc_settings.json
    fi

    # Create the target directory for certificates and copy all files.
    install -d ${D}${sysconfdir}/wings/cert
    cp -r ${WORKDIR}/cert/* ${D}${sysconfdir}/wings/cert/
    # Set all certificate files to read-only (0444) and directories to 0555.
    find ${D}${sysconfdir}/wings/cert -type f -exec chmod 0444 {} \;
    find ${D}${sysconfdir}/wings/cert -type d -exec chmod 0555 {} \;

    # Install systemd service unit if systemd is enabled.
    if ${@bb.utils.contains('DISTRO_FEATURES', 'systemd', 'true', 'false', d)}; then
        install -d ${D}${systemd_unitdir}/system
        install -m 0644 ${WORKDIR}/wings.service ${D}${systemd_unitdir}/system/
        install -m 0644 ${WORKDIR}/wings-log-manager.service ${D}${systemd_unitdir}/system/
        sed -i -e "s,##WESTON_SERVICE##,${WESTON_SERVICE},g" \
               "${D}${systemd_unitdir}/system/wings.service"
    fi

    # Install the trusted launcher into read-only rootfs.
    install -d ${D}${bindir}
    install -m 0755 ${WORKDIR}/wings-launcher ${D}${bindir}/wings-launcher
    install -m 0755 ${WORKDIR}/wings-log-manager ${D}${bindir}/wings-log-manager
    sed -i -e "s@##LVGL_DEMO_DISPLAY##@${LVGL_DEMO_DISPLAY}@g" \
           -e "s@##LVGL_DEMO_ENV##@${LVGL_DEMO_ENV}@g" \
           "${D}${bindir}/wings-launcher"

    # Install NetworkManager dispatcher to advertise only 10/100 Mbps on eth1.
    install -d ${D}${sysconfdir}/NetworkManager/dispatcher.d
    install -m 0755 ${WORKDIR}/99-eth1-100mbps \
        ${D}${sysconfdir}/NetworkManager/dispatcher.d/99-eth1-100mbps
}

FILES:${PN} += " \
    ${bindir}/wings-launcher \
    ${bindir}/wings-log-manager \
    ${systemd_unitdir}/system/wings.service \
    ${systemd_unitdir}/system/wings-log-manager.service \
    ${sysconfdir}/wings/ \
    ${datadir}/wings/ \
    ${sysconfdir}/NetworkManager/dispatcher.d/99-eth1-100mbps \
"
RDEPENDS:${PN} += "ethtool libmodbus openssl"

SYSTEMD_SERVICE:${PN} = "wings.service wings-log-manager.service"

COMPATIBLE_MACHINE = "(ccimx6$|ccimx6ul|ccimx8m|ccimx8x|ccimx93|ccmp15|ccmp2)"
