# bootwrapper
Linux kernel bootwrapper code

This directory contains a simple Cortex-M uClinux bootloader.
The bootloader is intended for use with ARM's MPS2 (Cortex-M Prototyping
System) and the associated FVP (Fixed Virtual Platform) model.

The code is derived from git@github.com:ARM-software/bootwrapper.git.

Build with:

PATH=<path-to-toolchain>:${PATH} make

The generated image should work for AN385 and AN511 (tested for AN385 only).
Assumptions:
	Linux kernel at 0x21000000
	DTB at 0x20000000
The local version of qemu loads the DTB at this location.

AN399 and AN505 would need a different memory layout.
