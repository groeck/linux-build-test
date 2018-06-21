/*
 * Copyright (c) 2017 ARM Limited. All rights reserved.
 * Copyright (c) 2018 Guenter Roeck
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */


	.syntax	unified

.macro mov32, reg, val
	movw	\reg, #:lower16:\val
	movt	\reg, #:upper16:\val
.endm

	.section ".head.text", "ax"
	.globl  _start

	.int 0x00004000
	.int _start + 1

_start:
	ldr	sp, =stack_base

	@
	@ Init uart
	@

	mov32	r0, #0x40004000			@ uart base addr
	mov32	r1, #0xa2c			@ 25MHz/9600
	str	r1, [r0, #0x10]			@ set BAUDDIV
	mov	r1, #3				@ TX/RX
	str	r1, [r0, #0x8]			@ enable uart

	@
	@ Kernel parameters
	@
	mov	r0, #0
	mov32	r1, #-1				@ don't match to any platform
	mov32	r2, #0x20000000			@ dtb into ZSRAM
	mov32	lr, #(PHYS_OFFSET + 0x8000)	@ kernel
	orr	lr, lr, #1			@ Thumb-2 kernel entry
	mov	pc, lr				@ jump to the kernel
