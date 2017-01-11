# QEMU target installation. Use QEMU_BIN for default,
# otherwise use the versioned target.

QEMU_INSTALL=/opt/buildbot/qemu-install
QEMU_V25_BIN=${QEMU_INSTALL}/v2.5/bin
QEMU_V26_BIN=${QEMU_INSTALL}/v2.6/bin
QEMU_V27_BIN=${QEMU_INSTALL}/v2.7/bin
QEMU_V28_BIN=${QEMU_INSTALL}/v2.8/bin

QEMU_BIN=${QEMU_V27_BIN}

QEMU_LINARO_BIN=${QEMU_INSTALL}/v2.3.50-linaro/bin
QEMU_METAG_BIN=${QEMU_INSTALL}/metag/bin
