# Copyright (C) 2022 Digi International

require digi-u-boot.inc
LIC_FILES_CHKSUM = "file://Licenses/README;md5=5a7450c57ffe5ae63fd732446b988025"

DEPENDS += "flex-native bison-native"

SRCBRANCH = "v2021.04/master"
SRCREV = "${AUTOREV}"

COMPATIBLE_MACHINE = "(ccimx8mp|ccmp15)"
