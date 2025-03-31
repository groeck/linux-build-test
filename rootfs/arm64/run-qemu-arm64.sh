#!/bin/bash

dir=$(cd $(dirname $0); pwd)
. "${dir}/run-qemu-arm64-common.sh"

skip_61="imx8mp-evk:defconfig:smp4:mem2G:net=default:initrd \
	imx8mp-evk:defconfig:smp4:mem2G:sdb2:net=default:ext2 \
	imx8mp-evk:defconfig:smp4:mem2G:virtio-pci:net=default:ext2 \
	imx8mp-evk:defconfig:smp4:mem2G:virtio:net=default:ext2"

__runkernel_common ""
retcode=$?

runkernel virt defconfig nosmp:mem512 rootfs.cpio
retcode=$((retcode + $?))

runkernel xlnx-zcu102 defconfig nosmp:mem2G rootfs.cpio xilinx/zynqmp-ep108.dtb
retcode=$((retcode + $?))
runkernel xlnx-zcu102 defconfig nosmp:mem2G:sd rootfs.ext2 xilinx/zynqmp-ep108.dtb
    retcode=$((retcode + $?))

exit ${retcode}
