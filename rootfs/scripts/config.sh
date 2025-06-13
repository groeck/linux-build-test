# QEMU target installation. Use QEMU_BIN for default,
# otherwise use the versioned target.

QEMU_INSTALL=/opt/buildbot/qemu-install
QEMU_V81_BIN=${QEMU_INSTALL}/v8.1/bin
QEMU_V82_BIN=${QEMU_INSTALL}/v8.2/bin
QEMU_V90_BIN=${QEMU_INSTALL}/v9.0/bin
QEMU_V91_BIN=${QEMU_INSTALL}/v9.1/bin
QEMU_V92_BIN=${QEMU_INSTALL}/v9.2/bin
QEMU_V100_BIN=${QEMU_INSTALL}/v10.0/bin
QEMU_MASTER_BIN=${QEMU_INSTALL}/master/bin

QEMU_BIN=${QEMU_V100_BIN}

QEMU_DATA=${QEMU_BIN}/../share/qemu

# default compiler
DEFAULT_CC9="gcc-9.5.0-2.37-nolibc"
DEFAULT_CC11="gcc-11.5.0-2.40-nolibc"
# gcc 12.4-2.42 fails (assembler errors) for parisc
DEFAULT_CC12="gcc-12.4.0-2.40-nolibc"
# nios2 is no longer supported in binutils 2.44
DEFAULT_CC13="gcc-13.4.0-2.43-nolibc"
DEFAULT_CC14="gcc-14.3.0-2.44-nolibc"

config_initcli="panic=-1"
