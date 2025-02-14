#!/bin/bash

progdir=$(cd $(dirname "$0"); pwd)
. "${progdir}/../riscv64/run-qemu-riscv64-common.sh"

__runkernel_common "rt:"
exit $?
