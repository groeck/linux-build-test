#!/bin/bash

dir=$(cd $(dirname $0); pwd)

. ${dir}/../x86_64/run-qemu-x86_64-common.sh

__runkernel_common "rt:"

exit $?
