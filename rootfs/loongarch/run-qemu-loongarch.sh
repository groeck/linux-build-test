#!/bin/bash

dir=$(cd $(dirname $0); pwd)
. ${dir}/run-qemu-loongarch-common.sh

__runkernel_common ""
exit $?
