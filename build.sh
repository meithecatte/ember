#!/bin/sh
set -ev
rm -rf gen
mkdir gen
nasm mbrsh.s -o gen/mbrsh.img -l gen/mbrsh.lst
[ "$1" = "run" ] && qemu-system-i386 -curses -drive format=raw,file=gen/mbrsh.img
