#!/bin/sh
set -ev
rm -rf gen
mkdir gen
nasm mbrsh.s -o gen/mbrsh.bin -l gen/mbrsh.lst
truncate -s 64M gen/fs.img
mkfs.fat -F 32 gen/fs.img
mcopy -i gen/fs.img fs/* ::
truncate -s $(($(stat -c %s gen/fs.img) + 512)) gen/mbrsh.img
sfdisk --quiet --no-reread --no-tell-kernel gen/mbrsh.img <<EOF
label: dos
unit: sectors
1
EOF
dd if=gen/mbrsh.bin of=gen/mbrsh.img conv=notrunc
dd if=gen/fs.img    of=gen/mbrsh.img conv=notrunc bs=512 seek=1 status=none
[ "$1" = "run" ] && qemu-system-i386 -curses -drive format=raw,file=gen/mbrsh.img
