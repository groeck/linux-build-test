setenv fdt_high "0xffffffff"
setenv bootargs "console=ttyO2,115200n8 root=${mmcroot} rootwait earlyprintk fixrtc nocompcache vram=12M omapfb.mode=${dvimode} mpurate=${mpurate} doreboot"
fatload mmc 0:1 0x80000000 uImage
fatload mmc 0:1 0x815f0000 devicetree.dtb
echo "Booting from boot.scr"
bootm 0x80000000 - 0x815f0000
