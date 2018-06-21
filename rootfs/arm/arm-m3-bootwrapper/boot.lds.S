/*
 * Copyright (c) 2017 ARM Limited. All rights reserved.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */


OUTPUT_ARCH(arm)
ENTRY(_start)

SECTIONS
{
	. = 0x0;
	.text : {
		*(.head.text)
		*(.text)
	}

	.data : { *(.data) }
	.bss : {
		*(.bss)

		. = ALIGN(8) + STACK_SIZE;
		stack_base = .;
	}
}
