buildarch=(alpha arm arm64 avr32 blackfin c6x cris frv hexagon i386 ia64 \
	   m32r m68k m68k_nommu \
	   metag microblaze mips mn10300 openrisc parisc parisc64 powerpc \
	   s390 score sh sparc32 sparc64 \
	   tile x86_64 xtensa um unicore32)

cmd_alpha=(defconfig allmodconfig allnoconfig)
cmd_arc=(defconfig allnoconfig tb10x_defconfig)
cmd_arcv2=(axs103_defconfig nsim_hs_smp_defconfig vdk_hs38_smp_defconfig)
cmd_arm=(allmodconfig allnoconfig s3c2410_defconfig omap2plus_defconfig imx_v6_v7_defconfig \
	ixp4xx_defconfig u8500_defconfig multi_v5_defconfig multi_v7_defconfig omap1_defconfig \
	footbridge_defconfig davinci_all_defconfig mini2440_defconfig \
	rpc_defconfig axm55xx_defconfig mxs_defconfig keystone_defconfig \
	vexpress_defconfig imx_v4_v5_defconfig at91_dt_defconfig \
	s3c6400_defconfig lpc32xx_defconfig shmobile_defconfig \
	nhk8815_defconfig bcm2835_defconfig sama5_defconfig orion5x_defconfig \
	exynos_defconfig cm_x2xx_defconfig s5pv210_defconfig \
	integrator_defconfig efm32_defconfig \
	pxa910_defconfig clps711x_defconfig)
cmd_arm64=(defconfig allnoconfig allmodconfig)
cmd_avr32=(defconfig allnoconfig merisc_defconfig atngw100mkii_evklcd101_defconfig)
cmd_blackfin=(defconfig BF561-EZKIT-SMP_defconfig)
cmd_c6x=(dsk6455_defconfig evmc6457_defconfig evmc6678_defconfig)
cmd_cris=(defconfig allnoconfig etrax-100lx_defconfig)
cmd_crisv32=(artpec_3_defconfig etraxfs_defconfig)
cmd_frv=(defconfig)
cmd_h8300=(allnoconfig edosk2674_defconfig h8300h-sim_defconfig h8s-sim_defconfig)
cmd_hexagon=(defconfig)
cmd_i386=(defconfig allyesconfig allmodconfig allnoconfig)
cmd_ia64=(defconfig allnoconfig)
cmd_m32r=(defconfig)
cmd_m68k=(defconfig allmodconfig allnoconfig sun3_defconfig)
cmd_m68k_nommu=(m5272c3_defconfig m5307c3_defconfig m5249evb_defconfig \
	m5407c3_defconfig m5475evb_defconfig)
cmd_metag=(defconfig allnoconfig meta1_defconfig meta2_defconfig meta2_smp_defconfig)
cmd_microblaze=(mmu_defconfig nommu_defconfig allnoconfig)
cmd_mips=(defconfig allmodconfig allnoconfig bcm47xx_defconfig bcm63xx_defconfig \
	nlm_xlp_defconfig ath79_defconfig ar7_defconfig fuloong2e_defconfig \
	e55_defconfig cavium_octeon_defconfig malta_defconfig)
cmd_mn10300=(asb2303_defconfig asb2364_defconfig)
cmd_nios2=(3c120_defconfig)
cmd_openrisc=(defconfig allnoconfig)
cmd_parisc=(defconfig allnoconfig allmodconfig generic-32bit_defconfig)
cmd_parisc64=(a500_defconfig generic-64bit_defconfig)
cmd_powerpc=(defconfig allmodconfig allnoconfig ppc64e_defconfig cell_defconfig \
	maple_defconfig ppc6xx_defconfig mpc83xx_defconfig \
	mpc85xx_defconfig mpc85xx_smp_defconfig tqm8xx_defconfig \
	85xx/sbc8548_defconfig 83xx/mpc834x_mds_defconfig \
	86xx/sbc8641d_defconfig)
cmd_s390=(defconfig allmodconfig allnoconfig)
cmd_score=(defconfig)
cmd_sh=(defconfig dreamcast_defconfig microdev_defconfig)
cmd_sparc32=(defconfig allnoconfig allmodconfig)
cmd_sparc64=(defconfig allmodconfig allnoconfig)
cmd_tile=(tilegx_defconfig)
cmd_x86_64=(defconfig allyesconfig allmodconfig allnoconfig)
cmd_xtensa=(defconfig allmodconfig allnoconfig)
cmd_um=(defconfig)
cmd_unicore32=(defconfig)

# build to skip

skip_32="alpha:allnoconfig arm:allnoconfig arm:allmodconfig avr32:allnoconfig \
	m68k:allnoconfig microblaze:allnoconfig mips:allmodconfig \
	openrisc:allnoconfig parisc:allnoconfig sparc32:allmodconfig \
	xtensa:defconfig xtensa:allmodconfig xtensa:allnoconfig"
skip_34="arm:allmodconfig openrisc:allnoconfig score:defconfig \
	sparc32:allmodconfig sparc64:allmodconfig \
	xtensa:allmodconfig"
skip_310="alpha:allnoconfig avr32:allnoconfig m68k:allnoconfig microblaze:allnoconfig \
	openrisc:allnoconfig parisc:allmodconfig s390:allmodconfig"
skip_312="alpha:allnoconfig avr32:allnoconfig m68k:allnoconfig \
	openrisc:allnoconfig parisc:allmodconfig sparc32:allmodconfig"
skip_314="alpha:allnoconfig avr32:allnoconfig ia64:allmodconfig m68k:allnoconfig
	openrisc:allnoconfig parisc:allmodconfig"

# fixups
#
fixup_alpha=("s/CONFIG_SAMPLE_KDBUS=y/# CONFIG_SAMPLE_KDBUS is not set/")

fixup_mips=("s/CONFIG_SAMPLE_KDBUS=y/# CONFIG_SAMPLE_KDBUS is not set/")

fixup_tile=("s/CONFIG_BLK_DEV_INITRD=y/# CONFIG_BLK_DEV_INITRD is not set/"
	"/CONFIG_INITRAMFS_SOURCE/d")

fixup_arc=("s/CONFIG_BLK_DEV_INITRD=y/# CONFIG_BLK_DEV_INITRD is not set/"
	"/CONFIG_INITRAMFS_SOURCE/d")

fixup_arcv2=("s/CONFIG_BLK_DEV_INITRD=y/# CONFIG_BLK_DEV_INITRD is not set/"
	"/CONFIG_INITRAMFS_SOURCE/d")

fixup_xtensa=("s/# CONFIG_LD_NO_RELAX is not set/CONFIG_LD_NO_RELAX=y/")
