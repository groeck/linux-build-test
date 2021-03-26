# QEMU target installation. Use QEMU_BIN for default,
# otherwise use the versioned target.

QEMU_INSTALL=/opt/buildbot/qemu-install
QEMU_V30_BIN=${QEMU_INSTALL}/v3.0/bin
QEMU_V40_BIN=${QEMU_INSTALL}/v4.0/bin
QEMU_V41_BIN=${QEMU_INSTALL}/v4.1/bin
QEMU_V42_BIN=${QEMU_INSTALL}/v4.2/bin
QEMU_V52_BIN=${QEMU_INSTALL}/v5.2/bin
QEMU_V60_BIN=${QEMU_INSTALL}/v6.0/bin
QEMU_MASTER_BIN=${QEMU_INSTALL}/master/bin

QEMU_BIN=${QEMU_V52_BIN}

QEMU_METAG_BIN=${QEMU_INSTALL}/metag/bin

config_initcli="slub_debug=FZPUA"
