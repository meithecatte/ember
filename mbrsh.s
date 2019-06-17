; memory map:
; [0000; 0400) IVT
; [0400; 0500) BDA
; [    ; 7c00) stack
; [7c00; 7e00) MBR
; [7de0; 7deb) filename buffer
; [7df0; 7e00) EDD disk packet
; [7e00; 8000) BPB sector

; FILE structure:
; .buffer: ds 0x200    ; (offset 0)
; .initial_cluster: dd ; (offset 0x200)
; .current_cluster: dd ; (offset 0x204)
; .offset: dw          ; (offset 0x208)

%define FILE_initial_cluster 0x200
%define FILE_current_cluster 0x204
%define FILE_offset          0x208
%define sizeof_FILE          0x20a

%define BPB_loadaddr    0x7e00
%define BPB_SecPerClus  BPB_loadaddr + 13 ; db
%define BPB_ResvdSecCnt BPB_loadaddr + 14 ; dw
%define BPB_NumFATs     BPB_loadaddr + 16 ; db
%define BPB_FATSz32     BPB_loadaddr + 36 ; dd
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
%define i_partread 0x81
	dw partread
%define i_readcluster 0x82
	dw readcluster
%define i_readopen 0x83
	dw readopen
.end:

start:
	cli
	xor cx, cx
	mov ds, cx
	mov es, cx
	mov ss, cx
	mov sp, 0x7c00
	mov [dopacket.diskload+1], dl
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

; Read the BPB
	mov di, 0x7e00
	xor eax, eax
	int i_partread

; Check for 512-byte sectors.
	cmp byte[BPB_BytsPerSec+1], 2
	jne short error

	; eax = 0
	mov al, byte[BPB_NumFATs]
	mul dword[BPB_FATSz32]
	movzx ebx, byte[BPB_SecPerClus]
	add bx, bx
	sub eax, ebx
	mov bx, word[BPB_ResvdSecCnt]
	add eax, ebx
	mov [readcluster.offset+2], eax

	mov bx, 3
	mov cl, 0
	mov di, 0x8000
	int i_readcluster

	cli
	hlt

shell:
	xor bx, bx
	mov ax, 0x0e00 + '>'
	int i_biosdisp

	mov di, 0x600
	int i_readline
	; TODO

; Read a line of text, store at ES:DI. Returns end in DI.
readline:
	push ax
	push bx
	push bp ; some BIOSes thrash BP on scroll -RBIL
.loop:
	mov ah, 0
	int i_bioskbd

	cmp al, 8
	jne short .nobackspace
	dec di
	db 0xb4 ; load the opcode of the stosb to AH to skip it
.nobackspace:
	stosb

	mov ah, 0x0e
	xor bx, bx
	int i_biosdisp
	cmp al, 13
	jne short .loop
	mov al, 10
	int i_biosdisp
	pop bp
	pop bx
	pop ax
	dec di
	iret

; Reads the next sector of a file.
; Input:
;  es:di = FILE
nextsector:
	pusha
	mov ebx, dword[es:di+FILE_current_cluster]
	mov cx, word[es:di+FILE_offset] ; TODO(opt): get pointer to the var in a register?
	or cx, 0x1FF
	inc cx
	mov word[es:di+FILE_offset], cx
	shr cx, 9
	cmp cl, byte[cs:BPB_SecPerClus]
	jl short .nonewcluster
	xor cx, cx
	
.nonewcluster
	
	db 0xb2 ; skip the pusha from readcluster by loading the opcode into dl

; Read a sector of a cluster.
; Input:
;  ebx = cluster number
;  cl = sector offset within cluster
;  es:di = buffer (512 bytes)
readcluster:
	pusha
	movzx eax, byte[cs:BPB_SecPerClus]
	mul ebx
.offset:
	add eax, dword 0xaaaaaaaa ; overwritten during init
	movzx ecx, cl
	add eax, ecx
	db 0xb1 ; skip the pusha from partread by loading the opcode into cl

; Read sector 
; Input:
;  eax = LBA (partition-relative)
;  es:di = operation buffer
; Stops execution on error
partread:
	pusha
	push ds

	push cs
	pop ds

	add eax, [0x7c00+0x1be+8]
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

; Open a file for reading.
; Input:
;  DS:SI = file name
;  ES:DI = file structure
; Output:
;  carry flag set if not found
readopen:
