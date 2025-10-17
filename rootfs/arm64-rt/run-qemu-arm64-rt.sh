#!/bin/bash

dir=$(cd $(dirname $0); pwd)
. "${dir}/../arm64/run-qemu-arm64-common.sh"

skip_617="npcm845-evb:defconfig:smp:mem1G:initrd"

__runkernel_common "rt:"
exit $?
