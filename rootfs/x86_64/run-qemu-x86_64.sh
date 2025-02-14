#!/bin/bash

dir=$(cd $(dirname $0); pwd)

. ${dir}/run-qemu-x86_64-common.sh

__runkernel_common ""
retcode=$?
checkstate ${retcode}

# Run some tests tests with CONFIG_PREEMPT enabled
runkernel defconfig preempt:smp4:net=ne2k_pci:efi:mem2G:virtio Icelake-Server q35 rootfs.iso
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel defconfig "preempt:smp8:net=i82557a:mem4G:nvme${gfs2}" Icelake-Server q35 rootfs.btrfs
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel defconfig preempt:smp2:net=i82558b:efi32:mem1G:sdhci-mmc Skylake-Client-IBRS q35 rootfs.ext2
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel defconfig preempt:smp6:net=i82550:mem512:ata:fstest=minix KnightsMill q35 rootfs.ext2
retcode=$((retcode + $?))
checkstate ${retcode}

runkernel defconfig nosmp:net=e1000:mem1G:usb Opteron_G3 pc rootfs.ext2
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel defconfig nosmp:net=ne2k_pci:efi:mem512:ata:fstest=hfs+ Opteron_G4 q35 rootfs.ext2
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel defconfig nosmp:net=pcnet:efi32:mem2G:ata Haswell-noTSX-IBRS q35 rootfs.ext2
retcode=$((retcode + $?))

exit ${retcode}
