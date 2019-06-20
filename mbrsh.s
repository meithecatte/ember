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
	xor bx, bx
	mov ax, 0x0e00 + '>'
	int i_biosdisp

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
	mov ah, 0x0e
	xor bx, bx
	lodsb
	or al, al
	jz short .skip_char
	int i_biosdisp
.skip_char:
	mov al, '?'
	int i_biosdisp
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
	int i_biosdisp
	push cx
	mov cx, 16
.byteloop:
	mov al, ' '
	int i_biosdisp
	lodsb
	call writehexbyte
	loop .byteloop
	mov al, 13
	int i_biosdisp
	mov al, 10
	int i_biosdisp
	mov dx, si
	pop cx
	loop hexdump
	jmp short shell

; Read a line of text, store at ES:DI. Null-terminated.
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

	mov ah, 0x0e
	xor bx, bx
	int i_biosdisp
	cmp al, 13
	jne short .loop
	mov al, 10
	int i_biosdisp
	dec di ; undo the store of the line terminatior
	mov byte[di], 0
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
	call hexparse
	jc short .fail
	shl al, 4
	mov bl, al
	lodsb
	call hexparse
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
hexparse:
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
;  AH = 0x0e
;  AL = the lower nibble as ASCII
;  BX = 0
;  DL = the byte, unchanged
; Clobbers BP
writehexbyte:
	mov dl, al
	shr al, 4
	call hexput
	mov al, dl
	and al, 0x0f
	; fallthrough

; Write a hexadecimal digit.
; Input:
;  AL = digit [0; 0x10)
; Output:
;  (screen)
;  AH = 0x0e
;  AL = digit as ASCII
;  BX = 0
; Clobbers BP
hexput:
	add al, '0'
	cmp al, '9'
	jbe .ok
	add al, 'a' - '0' - 10
.ok:
	mov ah, 0x0e
	xor bx, bx
	int i_biosdisp
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
	mov ax, 0x0e21
	xor bx, bx
	int i_biosdisp
	cli
	hlt
