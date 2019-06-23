# ember

An Apple II-style monitor that fits in your MBR.

# Usage

The ember monitor will prompt you with `>` once ready.

## Reading memory

Enter a 4-hexdigit lowercase address to view a hexdump of 16 bytes at that address:

```
>7c00
7c00: ea 0d 7c 00 00 47 7d 69 7d 12 7d 0b 7d fa 31 c9
>
```

It's also possible to specify a range with `.`:

```
>7c00.7c40
7c00: ea 0d 7c 00 00 47 7d 69 7d 12 7d 0b 7d fa 31 c9
7c10: 8e d9 8e c1 8e d1 bc 00 7c 88 16 37 7d fb fc bf
7c20: 80 00 be 05 7c b1 08 a5 31 c0 ab e2 fa 31 db b0
7c30: 3e cd 21 cd 20 be 00 06 e8 8b 00 72 05 93 89 df
>
```

The count is rounded up to the nearest 16 bytes:

```
>7c08.7c40
7c08: 7d 12 7d 0b 7d fa 31 c9 8e d9 8e c1 8e d1 bc 00
7c18: 7c 88 16 37 7d fb fc bf 80 00 be 05 7c b1 08 a5
7c28: 31 c0 ab e2 fa 31 db b0 3e cd 21 cd 20 be 00 06
7c38: e8 8b 00 72 05 93 89 df eb 03 be 00 06 ac 08 c0
>
```

## Writing memory

After the address, type a `:` and the bytes you want to poke:

```
>7e00:dead beef
>7e00
7e00: de ad be ef 00 00 00 00 00 00 00 00 00 00 00 00
>
```

## Inferred locations

Ember keeps track of the last read and write location and substitutes them
when you omit the address at the start of the line.

- The "read location" points after the last byte of the last read and is the default for
  read operations:

  ```
  >7c00
  7c00: ea 0d 7c 00 00 47 7d 69 7d 12 7d 0b 7d fa 31 c9
  >
  7c10: 8e d9 8e c1 8e d1 bc 00 7c 88 16 37 7d fb fc bf
  >
  7c20: 80 00 be 05 7c b1 08 a5 31 c0 ab e2 fa 31 db b0
  >.7c60
  7c30: 3e cd 21 cd 20 be 00 06 e8 8b 00 72 05 93 89 df
  7c40: eb 03 be 00 06 ac 08 c0 75 05 b9 01 00 eb 16 3c
  7c50: 2e 75 39 e8 70 00 72 5f 29 d8 83 c0 0f c1 e8 04
  >
  ```

- The "write location" points after the last byte of the last write and is the default for
  write operations:

  ```
  >7e00:cafe
  >:babe
  >7e00
  7e00: ca fe ba be 00 00 00 00 00 00 00 00 00 00 00 00
  >
  ```

- Specifying an explicit address moves both locations to that address:

  ```
  >7c00
  7c00: ea 0d 7c 00 00 47 7d 69 7d 12 7d 0b 7d fa 31 c9
  >7e00:12 34 56 78
  >
  7e00: 12 34 56 78 00 00 00 00 00 00 00 00 00 00 00 00
  >7e80
  7e80: 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
  >:abcd
  >7e80
  7e80: ab cd 00 00 00 00 00 00 00 00 00 00 00 00 00 00
  >
  ```

- Writes move the read location to the beginning of the write:

  ```
  >7e80
  7e80: 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
  >:abcd
  >
  7e80: ab cd 00 00 00 00 00 00 00 00 00 00 00 00 00 00
  >
  ```

## Running code

The `g` command will call the specified address. When no address is provided, the write location
is used.

```
>7e00:4869210d00
>:be007e
>:ac 08c0 7404 cd21 ebf7 c3
>7e05g
Hi!
>
```

# Routines provided to runnning programs

Some routines used in ember are exposed as interrupts. Apart from explicit outputs, no registers
are modified.

```asm
; Interrupt 0x20
; Read a line of text and store it in the global `linebuffer` (0x600). The result is
; null-terminated. No overflow checking is performed.

; Interrupt 0x21
; Put a character on the screen. Expands \r into \r\n because the latter is required
; by the BIOS for a proper newline. \r is used to signify newlines because that's what
; the keyboard gives us.
; Input:
;  AL = ASCII character

; Interrupt 0x22
; Read sector on the boot disk
; Input:
;  eax = LBA
;  es:di = operation buffer
; Stops execution on error

; Interrupt 0x23
; Write sector on the boot disk
; Input:
;  eax = LBA
;  es:di = operation buffer
```

# Limitations

- uppercase letters are not recognized in commands
- only the first 64K of memory is accessible
- the error handling creates confusing messages when less than
  four hexdigits of address are provided
- backspacing over the edge of the screen desyncs what's visible from the internal buffer

# TODO

- `r` and `w` commands for accessing the boot disk.
- Restart the main loop after a disk error.
