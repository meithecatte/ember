; memory map:
; [0000; 0400) IVT
; [0400; 0500) BDA
; [    ; 7c00) stack
; [7c00; 7e00) MBR
; [7de0; 7deb) filename buffer
; [7df0; 7e00) EDD disk packet
; [7e00;     ) variables

org 0x7c00
bits 16

; Some BIOSes start with CS=07c0. Make sure this does not wreak havoc
	jmp 0:start

ivtptr:
%define i_biosdisp 0x10
%define i_biosdisk 0x13
%define i_bioskbd  0x16

%define i_readline 0x80
	dw readline

%define i_putchar  0x81
	dw putchar
.end:

start:
	cli
	xor cx, cx
	mov ds, cx
	mov es, cx
	mov ss, cx
	mov sp, 0x7c00
	mov [diskread.diskload+1], dl
	sti

	mov di, 0x200
	mov si, ivtptr
	mov cl, ivtptr.end - ivtptr
.ivtloop:
	movsw
	; it's not necessary to clear the upper part of EAX now, but it saves bytes
	; compared to doing it again before the BPB read
	xor eax, eax
	stosw
	loop .ivtloop

	xor dx, dx
shell:
	mov al, '>'
	int i_putchar

	mov di, 0x600
	int i_readline

	mov si, di
	call readhexword
	jnc short .addr
	mov si, di
	db 0xbb ; load the two-byte `mov dx, ax` below into BX to skip it
.addr:
	mov dx, ax

	; command dispatch
	lodsb
	or al, al
	jnz short .not_singledump

	mov cx, 1
	jmp short hexdump
.not_singledump:
	cmp al, '.'
	jnz short .not_rangedump

	call readhexword
	jc short parse_error

	sub ax, dx ; length in bytes
	add ax, 15 ; round up
	shr ax, 4  ; into line count
	mov cx, ax ; prepare loop counter

	lodsb
	or al, al
	jz short hexdump
	jnz short parse_error ; TODO: optimize?

.not_rangedump:

parse_error:
	dec si
	lodsb
	or al, al
	jz short .skip_char
	int i_putchar
.skip_char:
	mov al, '?'
	int i_putchar
	jmp short shell

; Print a hexdump
; Returns to `shell`
; Input:
;  DX = data pointer
;  CX = line count
; Output:
;  CX = 0
;  DX = first unprinted byte
; Clobbers AX, BX, BP
hexdump:
	mov si, dx
	mov al, dh
	call writehexbyte
	mov ax, si
	call writehexbyte
	mov al, ':'
	int i_putchar
	push cx
	mov cx, 16
.byteloop:
	mov al, ' '
	int i_putchar
	lodsb
	call writehexbyte
	loop .byteloop
	mov al, `\r`
	int i_putchar
	mov dx, si
	pop cx
	loop hexdump
	jmp short shell

; Read a line of text. The result is null-terminated. No overflow checking is performed
; because any memory access can be performed with the monitor with the intended
; functionality.
; Input:
;  ES:DI = output buffer pointer
readline:
	pusha
	mov si, di
.loop:
	mov ah, 0
	int i_bioskbd

	cmp al, 8
	jne short .nobackspace
	cmp si, di
	je short .loop
	dec di
	db 0xb4 ; load the opcode of the stosb to AH to skip its execution
.nobackspace:
	stosb
	int i_putchar

	cmp al, `\r`
	jne short .loop

	dec di ; undo the store of the line terminatior
	mov byte[di], 0
	popa
	iret

; Put a character on the screen. Expands \r into \r\n because the latter is required
; by the BIOS for a proper newline. \r is used to signify newlines because that's what
; the keyboard gives us.
; Input:
;  AL = ASCII character
; TODO: replace backspace with "\b \b" to erase properly? (will it fit?)
putchar:
	pusha
	mov ah, 0x0e
	xor bx, bx
	int i_biosdisp
	cmp al, `\r` ; all registers are preserved by the BIOS function
	jne short .skip_newline
	mov al, `\n`
	int i_biosdisp
.skip_newline:
	popa
	iret

; Parse a hexadecimal word.
; Input:
;  SI = input buffer pointer
; Output (success):
;  CF clear
;  AX = parsed word
;  SI = input + 4
; Output (failure):
;  CF set
;  SI = after first invalid character
readhexword:
	call readhexbyte
	jc short readhexbyte.fail
	mov ah, al
	; fallthrough

; Parse a hexadecimal byte.
; Input:
;  SI = input buffer pointer
; Output (success):
;  CF clear
;  AL = parsed byte
;  SI = input + 2
; Output (failure):
;  CF set
;  AL = undefined
;  SI = after invalid character
; Clobbers BL
readhexbyte:
	lodsb
	call readhexchar
	jc short .fail
	shl al, 4
	mov bl, al
	lodsb
	call readhexchar
	jc short .fail
	or al, bl ; carry flag is clear
.fail:
	ret

; Parse a hexadecimal digit.
; Input:
;  AL = ASCII character
; Output (success):
;  CF clear
;  AL = digit value [0; 16)
; Output (failure):
;  CF set
;  AL = undefined
readhexchar:
	sub al, '0'
	jc short .end
	cmp al, 10 ; jb = jc, so right now carry = ok
	cmc ; now, carry = try different range
	jnc short .end
	sub al, 'a' - '0'
	jc short .end
	add al, 10
	cmp al, 16
	cmc ; before, carry = ok. now, carry = error
.end:
	ret

; Write a hexadecimal byte.
; Input:
;  AL = the byte
; Output:
;  (screen)
;  AL = the lower nibble as ASCII
;  DL = the byte, unchanged
; Clobbers BP
writehexbyte:
	mov dl, al
	shr al, 4
	call writehexchar
	mov al, dl
	and al, 0x0f
	; fallthrough

; Write a hexadecimal digit.
; Input:
;  AL = digit [0; 0x10)
; Output:
;  (screen)
;  AL = digit as ASCII
; Clobbers BP
writehexchar:
	add al, '0'
	cmp al, '9'
	jbe .ok
	add al, 'a' - '0' - 10
.ok:
	int i_putchar
	ret

; Read sector 
; Input:
;  eax = LBA
;  es:di = operation buffer
; Stops execution on error
diskread:
	pusha
	push ds

	push cs
	pop ds

	mov si, 0x7df0
	mov dword[si], 0x10010
	mov [si+4], di
	mov [si+6], es
	mov [si+8], eax
	xor eax, eax
	mov [si+12], eax
.diskload:
	mov dl, 0 ; overwritten during init
	mov ah, 0x42
	int i_biosdisk
	jc short error

	pop ds
	popa
	iret

error:
	mov al, '!'
	int i_putchar
	cli
	hlt
