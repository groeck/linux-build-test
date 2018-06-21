#
# Copyright (c) 2017, ARM Limited. All rights reserved.
# Copyright (c) 2018, Guenter Roeck
#
# SPDX-License-Identifier: BSD-3-Clause
#

CROSS_COMPILE=arm-linux-

STACK_SIZE	= 0x10000
PHYS_OFFSET	= 0x21000000	# RAM
DTB_OFFSET	= 0x20000000	# ZSRAM

BOOT		= mps2-boot.axf

CC		= $(CROSS_COMPILE)gcc
LD		= $(CROSS_COMPILE)ld
AS		= $(CROSS_COMPILE)as

CFLAGS		+= -DPHYS_OFFSET=$(PHYS_OFFSET)
CFLAGS		+= -DSTACK_SIZE=$(STACK_SIZE)
CFLAGS		+= -DKERNEL=$(KERNEL)
CFLAGS		+= -DDTB_OFFSET=$(DTB_OFFSET)

ASFLAGS		+= -march=armv7-m
ASFLAGS		+= -mthumb -mthumb -mimplicit-it=always
ASFLAGS		+= --defsym PHYS_OFFSET=$(PHYS_OFFSET)
ASFLAGS		+= --defsym DTB_OFFSET=$(DTB_OFFSET)

all: $(BOOT)

clean:
	rm -f $(BOOT) boot.o boot.lds

$(BOOT): boot.lds boot.o
	$(LD) boot.o -o $@ --script=boot.lds

%.o: %.S
	$(AS) $(ASFLAGS) -o $@ $<

boot.lds: boot.lds.S
	$(CC) $(CFLAGS) -E -P -C -o $@ $<

.PHONY: FORCE
FORCE:
