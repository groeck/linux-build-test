#!/bin/bash

dir=$(cd $(dirname $0); pwd)
. ${dir}/../loongarch/run-qemu-loongarch-common.sh

__runkernel_common "rt"
exit $?
