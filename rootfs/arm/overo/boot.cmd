setenv mmcrootfstype ext3 rootwait doreboot
fatload mmc ${mmcdev} 0x82001000 uImage
fatload mmc ${mmcdev} 0x83000000 devicetree.dtb
run mmcargs
echo Booting from boot.scr ...
bootm 0x82001000 - 0x83000000
