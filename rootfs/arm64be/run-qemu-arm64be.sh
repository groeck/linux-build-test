#!/bin/bash

dir=$(cd $(dirname $0); pwd)
. "${dir}/../arm64/run-qemu-arm64-common.sh"

__runkernel_common "be:"
exit $?
