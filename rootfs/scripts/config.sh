# QEMU target installation. Use QEMU_BIN for default,
# otherwise use the versioned target.

QEMU_INSTALL=/opt/buildbot/qemu-install
QEMU_V81_BIN=${QEMU_INSTALL}/v8.1/bin
QEMU_V82_BIN=${QEMU_INSTALL}/v8.2/bin
QEMU_V90_BIN=${QEMU_INSTALL}/v9.0/bin
QEMU_V91_BIN=${QEMU_INSTALL}/v9.1/bin
QEMU_MASTER_BIN=${QEMU_INSTALL}/master/bin

QEMU_BIN=${QEMU_V90_BIN}

# default compiler
DEFAULT_CC9="gcc-9.4.0-nolibc"
DEFAULT_CC11="gcc-11.5.0-2.40-nolibc"
DEFAULT_CC12="gcc-12.4.0-2.42-nolibc"
DEFAULT_CC13="gcc-13.3.0-2.42-nolibc"

# Now set in common.sh
# DEFAULT_CC="${DEFAULT_CC11}"

config_initcli="panic=-1"
