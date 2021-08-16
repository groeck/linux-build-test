buildarch=(alpha arm arm64 blackfin c6x cris frv hexagon i386 ia64 \
	   m32r m68k m68k_nommu \
	   metag microblaze mips mn10300 openrisc parisc parisc64 powerpc \
	   s390 score sh sparc32 sparc64 \
	   tile x86_64 xtensa um)

cmd_alpha=(defconfig allmodconfig allnoconfig tinyconfig)
cmd_arc=(tb10x_defconfig)
cmd_arcv2=(defconfig allnoconfig tinyconfig axs103_defconfig nsim_hs_smp_defconfig vdk_hs38_smp_defconfig)
cmd_arm=(allmodconfig allnoconfig tinyconfig \
	s3c2410_defconfig omap2plus_defconfig imx_v6_v7_defconfig \
	ixp4xx_defconfig u8500_defconfig multi_v5_defconfig omap1_defconfig \
	footbridge_defconfig davinci_all_defconfig mini2440_defconfig \
	axm55xx_defconfig mxs_defconfig keystone_defconfig \
	vexpress_defconfig imx_v4_v5_defconfig at91_dt_defconfig \
	s3c6400_defconfig lpc32xx_defconfig shmobile_defconfig \
	nhk8815_defconfig bcm2835_defconfig sama5_defconfig orion5x_defconfig \
	exynos_defconfig cm_x2xx_defconfig s5pv210_defconfig \
	integrator_defconfig efm32_defconfig \
	pxa910_defconfig clps711x_defconfig)
cmd_arm64=(allnoconfig tinyconfig defconfig allmodconfig)
cmd_blackfin=(defconfig BF561-EZKIT-SMP_defconfig)
cmd_c6x=(dsk6455_defconfig evmc6457_defconfig evmc6678_defconfig)
cmd_cris=(defconfig allnoconfig tinyconfig etrax-100lx_defconfig)
cmd_crisv32=(artpec_3_defconfig etraxfs_defconfig)
cmd_csky=(defconfig allnoconfig tinyconfig)
cmd_frv=(defconfig)
cmd_h8300=(allnoconfig tinyconfig edosk2674_defconfig h8300h-sim_defconfig h8s-sim_defconfig)
cmd_hexagon=(defconfig allnoconfig tinyconfig)
cmd_i386=(defconfig allyesconfig allmodconfig allnoconfig tinyconfig tools/perf)
cmd_ia64=(defconfig allnoconfig tinyconfig)
cmd_m32r=(defconfig)
cmd_m68k=(defconfig allmodconfig allnoconfig tinyconfig sun3_defconfig)
cmd_m68k_nommu=(m5272c3_defconfig m5307c3_defconfig m5249evb_defconfig \
	m5407c3_defconfig m5475evb_defconfig)
cmd_metag=(defconfig allnoconfig tinyconfig meta1_defconfig meta2_defconfig meta2_smp_defconfig)
cmd_microblaze=(mmu_defconfig nommu_defconfig allnoconfig tinyconfig)
cmd_mips=(defconfig allmodconfig allnoconfig tinyconfig bcm47xx_defconfig bcm63xx_defconfig \
	nlm_xlp_defconfig ath79_defconfig ar7_defconfig \
	e55_defconfig cavium_octeon_defconfig malta_defconfig rt305x_defconfig)
cmd_mn10300=(asb2303_defconfig asb2364_defconfig)
cmd_nds32=(defconfig allnoconfig tinyconfig allmodconfig)
cmd_nios2=(allnoconfig tinyconfig 3c120_defconfig)
cmd_openrisc=(defconfig allnoconfig tinyconfig)
cmd_parisc=(allnoconfig tinyconfig allmodconfig generic-32bit_defconfig)
cmd_parisc64=(a500_defconfig generic-64bit_defconfig)
cmd_powerpc=(defconfig allmodconfig allnoconfig tinyconfig ppc64e_defconfig cell_defconfig \
	maple_defconfig ppc6xx_defconfig mpc83xx_defconfig \
	tqm8xx_defconfig \
	85xx/sbc8548_defconfig 83xx/mpc834x_mds_defconfig)
cmd_riscv=(defconfig allnoconfig tinyconfig allmodconfig)
cmd_s390=(defconfig allmodconfig allnoconfig tinyconfig performance_defconfig)
cmd_score=(defconfig)
cmd_sh=(defconfig allnoconfig tinyconfig dreamcast_defconfig microdev_defconfig shx3_defconfig)
cmd_sparc32=(defconfig allnoconfig tinyconfig)
cmd_sparc64=(allmodconfig defconfig allnoconfig tinyconfig)
cmd_tile=(tilegx_defconfig)
cmd_x86_64=(defconfig allyesconfig allmodconfig allnoconfig tinyconfig tools/perf)
cmd_xtensa=(defconfig allmodconfig allnoconfig tinyconfig)
cmd_um=(defconfig)

# build to skip

skip_44="crisv32:allnoconfig crisv32:tinyconfig cris:allnoconfig \
	cris:tinyconfig powerpc:allmodconfig i386:tools/perf x86_64:tools/perf"
skip_49="i386:tools/perf x86_64:tools/perf"
skip_419="riscv32:allmodconfig riscv:allmodconfig"
skip_54="riscv32:allmodconfig riscv:allmodconfig"

# fixups

fixup_parisc=("s/# CONFIG_MLONGCALLS is not set/CONFIG_MLONGCALLS=y/")

fixup_tile=("s/CONFIG_BLK_DEV_INITRD=y/# CONFIG_BLK_DEV_INITRD is not set/"
	"/CONFIG_INITRAMFS_SOURCE/d")

fixup_arc=("s/CONFIG_BLK_DEV_INITRD=y/# CONFIG_BLK_DEV_INITRD is not set/"
	"/CONFIG_INITRAMFS_SOURCE/d")

fixup_xtensa=("s/# CONFIG_LD_NO_RELAX is not set/CONFIG_LD_NO_RELAX=y/")

fixup_csky=("s/CONFIG_FRAME_POINTER=y/# CONFIG_FRAME_POINTER is not set/")
