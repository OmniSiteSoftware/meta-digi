SUMMARY = "OPTEE Client"
HOMEPAGE = "https://github.com/OP-TEE/optee_client"

LICENSE = "BSD-2-Clause"
LIC_FILES_CHKSUM = "file://${S}/LICENSE;md5=69663ab153298557a59c67a60a743e5b"

inherit python3native systemd cmake

SRC_URI = "git://github.com/OP-TEE/optee_client.git;protocol=https;branch=master \
           file://tee-supplicant.service \
    "

SRCREV = "06db73b3f3fdb8d23eceaedbc46c49c0b45fd1e2"

PV = "3.16.0+git${SRCPV}"

S = "${WORKDIR}/git"

SYSTEMD_SERVICE:${PN} = "tee-supplicant.service"

EXTRA_OECMAKE = " \
    -DCFG_TEE_FS_PARENT_PATH='${localstatedir}/lib/tee' \
    -DCFG_WERROR=OFF \
    -DCFG_TEE_CLIENT_LOG_LEVEL=2 \
    -DBUILD_SHARED_LIBS=ON \
    "

# If TF file based encryption is enabled, move the TEE_FS_PARENT_PATH out of the rootfs
EXTRA_OECMAKE += "${@oe.utils.vartrue('TRUSTFENCE_FILE_BASED_ENCRYPT', '-DCFG_TEE_FS_PARENT_PATH=/mnt/data/tee', '', d)}"

do_install:append() {
    if ${@bb.utils.contains('DISTRO_FEATURES','systemd','true','false',d)}; then
        install -D -p -m0644 ${WORKDIR}/tee-supplicant.service ${D}${systemd_system_unitdir}/tee-supplicant.service
    fi
}
FILES:${PN} += "${systemd_system_unitdir}"
