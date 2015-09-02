setenv mmcrootfstype ext3 rootwait doreboot
fatload mmc ${mmcdev} 0x82001000 uImage
fatload mmc ${mmcdev} 0x83000000 devicetree.dtb
echo mmcrootfstype: ${mmcrootfstype}
echo mmcargs: ${mmcargs}
run mmcargs
echo bootargs: ${bootargs}
echo Booting from boot.src ...
bootm 0x82001000 - 0x83000000
