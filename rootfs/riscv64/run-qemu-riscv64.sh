#!/bin/bash

progdir=$(cd $(dirname "$0"); pwd)
. "${progdir}/run-qemu-riscv64-common.sh"

__runkernel_common ""
exit $?
