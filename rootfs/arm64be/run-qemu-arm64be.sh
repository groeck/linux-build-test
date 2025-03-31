#!/bin/bash

dir=$(cd $(dirname $0); pwd)
. "${dir}/../arm64/run-qemu-arm64-common.sh"

skip_61="imx8mp-evk:defconfig:be:smp4:mem2G:net=default:initrd \
	imx8mp-evk:defconfig:be:smp4:mem2G:sdb2:net=default:ext2 \
	imx8mp-evk:defconfig:be:smp4:mem2G:virtio-pci:net=default:ext2 \
	imx8mp-evk:defconfig:be:smp4:mem2G:virtio:net=default:ext2"

__runkernel_common "be:"
exit $?
