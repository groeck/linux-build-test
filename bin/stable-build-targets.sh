cmd_alpha=(defconfig allmodconfig allnoconfig tinyconfig)
cmd_arc=(tb10x_defconfig)
cmd_arcv2=(defconfig allnoconfig tinyconfig axs103_defconfig \
	nsimosci_hs_smp_defconfig vdk_hs38_smp_defconfig)
cmd_arm=(allmodconfig allnoconfig tinyconfig \
	omap2plus_defconfig imx_v6_v7_defconfig ep93xx_defconfig \
	ixp4xx_defconfig u8500_defconfig multi_v5_defconfig omap1_defconfig \
	footbridge_defconfig davinci_all_defconfig \
	axm55xx_defconfig mxs_defconfig keystone_defconfig imxrt_defconfig \
	vexpress_defconfig imx_v4_v5_defconfig at91_dt_defconfig \
	s3c6400_defconfig lpc32xx_defconfig shmobile_defconfig \
	nhk8815_defconfig bcm2835_defconfig sama5_defconfig sama7_defconfig \
	orion5x_defconfig exynos_defconfig s5pv210_defconfig \
	integrator_defconfig sp7021_defconfig \
	pxa910_defconfig clps711x_defconfig)
cmd_arm64=(allnoconfig tinyconfig defconfig allmodconfig)
cmd_csky=(defconfig allnoconfig tinyconfig allmodconfig)
cmd_h8300=(allnoconfig tinyconfig edosk2674_defconfig h8300h-sim_defconfig h8s-sim_defconfig)
cmd_hexagon=(defconfig allnoconfig tinyconfig)
cmd_i386=(defconfig allyesconfig allmodconfig allnoconfig tinyconfig tools/perf)
cmd_loongarch=(defconfig allnoconfig tinyconfig allmodconfig)
cmd_m68k=(defconfig allmodconfig allnoconfig tinyconfig sun3_defconfig)
cmd_m68k_nommu=(m5272c3_defconfig m5307c3_defconfig m5249evb_defconfig \
	m5407c3_defconfig m5475evb_defconfig)
cmd_microblaze=(defconfig allnoconfig tinyconfig)
cmd_mips=(defconfig allmodconfig allnoconfig tinyconfig bcm47xx_defconfig bcm63xx_defconfig \
	ath79_defconfig ar7_defconfig loongson2k_defconfig mtx1_defconfig db1xxx_defconfig \
	cavium_octeon_defconfig malta_defconfig rt305x_defconfig)
cmd_nds32=(defconfig allnoconfig tinyconfig allmodconfig)
# nios2 allmodconfig: "Internal error in nios2_align" (binutils)
cmd_nios2=(allnoconfig tinyconfig 3c120_defconfig)
cmd_openrisc=(defconfig allnoconfig tinyconfig allmodconfig)
cmd_parisc=(allnoconfig tinyconfig allmodconfig generic-32bit_defconfig)
cmd_parisc64=(allnoconfig generic-64bit_defconfig)
cmd_powerpc=(defconfig allmodconfig ppc32_allmodconfig allnoconfig tinyconfig \
	ppc64e_defconfig cell_defconfig skiroot_defconfig \
	maple_defconfig ppc6xx_defconfig mpc83xx_defconfig \
	tqm8xx_defconfig \
	85xx/tqm8548_defconfig 83xx/mpc834x_itx_defconfig)
cmd_riscv32=(defconfig allnoconfig tinyconfig allmodconfig \
	nommu_virt_defconfig)
cmd_riscv64=(defconfig allnoconfig tinyconfig allmodconfig nommu_k210_sdcard_defconfig \
	nommu_virt_defconfig)
cmd_s390=(defconfig allmodconfig allnoconfig tinyconfig debug_defconfig)
cmd_sh=(defconfig allnoconfig tinyconfig dreamcast_defconfig microdev_defconfig \
	shx3_defconfig se7619_defconfig)
cmd_sparc32=(defconfig allnoconfig tinyconfig)
cmd_sparc64=(allmodconfig defconfig allnoconfig tinyconfig)
cmd_x86_64=(defconfig allyesconfig allmodconfig allnoconfig tinyconfig tools/perf)
cmd_xtensa=(defconfig allmodconfig allnoconfig tinyconfig)
cmd_um=(defconfig)

# builds to skip

skip_419="x86_64:tools/perf i386:tools/perf riscv32:allmodconfig riscv:allmodconfig powerpc:ppc32_allmodconfig openrisc:allmodconfig parisc64:allnoconfig"
skip_54="x86_64:tools/perf i386:tools/perf riscv32:allmodconfig riscv:allmodconfig csky:allmodconfig parisc64:allnoconfig"
skip_510="x86_64:tools/perf i386:tools/perf csky:allmodconfig parisc64:allnoconfig"
skip_515="x86_64:tools/perf i386:tools/perf"
skip_61="x86_64:tools/perf i386:tools/perf"

# fixups

# CONFIG_WERROR is disabled on some architectures where builds are known to fail
# if it is enabled.
# Affects:
# - alpha
# - sh4
# - sparc64

fixup_alpha=("s/CONFIG_WERROR=y/CONFIG_WERROR=n/")

fixup_arc=("s/CONFIG_BLK_DEV_INITRD=y/CONFIG_BLK_DEV_INITRD=n/"
	"/CONFIG_INITRAMFS_SOURCE/d")

fixup_csky=("s/CONFIG_FRAME_POINTER=y/CONFIG_FRAME_POINTER=n/")

fixup_parisc=("s/# CONFIG_MLONGCALLS is not set/CONFIG_MLONGCALLS=y/"
	"s/CONFIG_MLONGCALLS=n/CONFIG_MLONGCALLS=y/")

fixup_sh=("s/CONFIG_WERROR=y/CONFIG_WERROR=n/")

fixup_sparc64=("s/CONFIG_WERROR=y/CONFIG_WERROR=n/")

fixup_xtensa=("s/# CONFIG_LD_NO_RELAX is not set/CONFIG_LD_NO_RELAX=y/"
	"s/CONFIG_SECTION_MISMATCH_WARN_ONLY is not set/CONFIG_SECTION_MISMATCH_WARN_ONLY=y/"
	"s/CONFIG_LD_NO_RELAX=n/CONFIG_LD_NO_RELAX=y/")

# We don't ever want to be in the business of arguing about frame sizes,
# so disable frame size warnings/errors completely.
# Plugins need gcc 14.1, 13.3, or 12.4 to work on some architectures.
# See https://gcc.gnu.org/r14-3331 for details affecting looongarch,
# but other architectures are affected as well. Disable plugin support
# entirely since it only has limited if any value for test builds.
# Disable CONFIG_RANDSTRUCT because it results in random build failures
# which are difficult to track down, for example on s390.
fixup_common=("s/CONFIG_FRAME_WARN=.*/CONFIG_FRAME_WARN=0/"
	"s/CONFIG_GCC_PLUGINS=y/CONFIG_GCC_PLUGINS=n/"
	"s/CONFIG_RANDSTRUCT=y/CONFIG_RANDSTRUCT=n/"
	"s/CONFIG_RANDSTRUCT_FULL=y/CONFIG_RANDSTRUCT_NONE=y/"
	)
