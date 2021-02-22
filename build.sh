#!/bin/sh
set -ev
rm -rf gen
mkdir gen
nasm ember.s -o gen/ember.img -l gen/ember.lst
[ "$1" = "run" ] && qemu-system-i386 -drive format=raw,file=gen/ember.img
