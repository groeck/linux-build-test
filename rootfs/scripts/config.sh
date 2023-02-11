# QEMU target installation. Use QEMU_BIN for default,
# otherwise use the versioned target.

QEMU_INSTALL=/opt/buildbot/qemu-install
QEMU_V42_BIN=${QEMU_INSTALL}/v4.2/bin
QEMU_V72_BIN=${QEMU_INSTALL}/v7.2/bin
QEMU_MASTER_BIN=${QEMU_INSTALL}/master/bin

QEMU_BIN=${QEMU_V72_BIN}

# default compiler
DEFAULT_CC="gcc-11.3.0-2.39-nolibc"

config_initcli="slub_debug=FZPUA"
