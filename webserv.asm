
; Only supports current directory, so only files in the current directory can be viewed without changin this
directory_to_list db WEBSERVER_TO_LIST, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0

sys_read equ 0
sys_write equ 1
sys_open equ 2
sys_close equ 3
sys_exit equ 60
sys_sendfile equ 40
sys_socket equ 41
sys_accept equ 43
sys_bind equ 49
sys_listen equ 50
sys_setsockopt equ 54
sys_getdents64 equ 217

O_RDONLY equ 0
O_WRONLY equ 1
O_RDWR	 equ 2
O_DIRECTORY equ	0o200000
O_NOFOLLOW equ	0o400000
AF_INET equ 2
SOCK_STREAM equ 1
SOL_SOCKET equ 1
SO_REUSEADDR equ 2

struc sockaddr_in
	.sin_family resb 2
	.sin_port resb 2
	.sin_addr resb 4
	.sin_zero resb 8
endstruc

section .text
global _start

extern printf
extern puts

_start:
	mov rax, sys_write
	mov rdi, 1
	mov rsi, msg
	mov rdx, msglen
	syscall

	mov rax, sys_socket
	mov rdi, AF_INET ; IPV4
	mov rsi, SOCK_STREAM ; TCP
	mov rdx, 0 ; default
	syscall

	mov rsi, socket_str
	mov rdx, rax
	cmp rax, 0
	jl fail

;	Save socket fd 
	mov DWORD [servfd], eax

	mov r8, 4
	mov r10, yes
	mov rdx, SO_REUSEADDR
	mov rsi, SOL_SOCKET
	mov rdi, [servfd]
	mov rax, sys_setsockopt
	syscall

	mov rsi, setsockopt_str
	mov rdx, rax
	cmp rax, 0
	jl fail

	mov rdi, [servfd]
	mov rax, sys_bind
	mov rsi, server_info
	mov rdx, sockaddr_in_size ; IPv4 Addr is 4 bytes
	syscall

	mov rsi, bind_str
	mov rdx, rax
	cmp rax, 0
	jl fail

	mov rax, sys_listen
	mov rdi, [servfd]
	mov rsi, 1
	syscall

	mov rsi, listen_str
	mov rdx, rax
	cmp rax, 0
	jl fail

accept_loop:
	mov DWORD [remote_sockaddr_size], sockaddr_in_size
	mov rax, sys_accept
	mov rdi, [servfd]
	mov rsi, remote_sockaddr
	mov rdx, remote_sockaddr_size
	syscall

	mov [clientfd], rax

	mov rsi, accept_str
	mov rdx, rax
	cmp rax, 0
	jl fail

	mov rdi, remote_addr
	movzx esi, BYTE [remote_sockaddr+sockaddr_in.sin_addr]
	movzx edx, BYTE [remote_sockaddr+sockaddr_in.sin_addr+1]
	movzx ecx, BYTE [remote_sockaddr+sockaddr_in.sin_addr+2]
	movzx r8, BYTE [remote_sockaddr+sockaddr_in.sin_addr+3]
	mov ah, BYTE [remote_sockaddr+sockaddr_in.sin_port]
	mov al, BYTE [remote_sockaddr+sockaddr_in.sin_port+1]
	movzx r9, ax
	xor eax, eax
	call printf

;	Yes marks if this is the start of the HTTP request,
;	if so we need to check whether a file or the root
;	page is being requested
	mov DWORD [yes], 2

;	Read request
reading:
	mov rax, sys_read
	mov rdi, [clientfd]
	mov rsi, buf
	mov rdx, sizeof_buf
	syscall

	push rax

	mov rsi, read_str
	mov rdx, rax
	cmp rax, 0
	jl fail

	mov rdx, rax
	mov rsi, buf
	mov rdi, 1
	mov rax, sys_write
	syscall

;	Check what path was requested
	cmp DWORD [yes], 2
	jne continue

	xor rax, rax
	cmp QWORD [rsp], sizeof_buf
	cmovge eax, DWORD [yes]

	mov DWORD [yes], eax


	cmp DWORD [buf+4], "/ HT"
	jne send_file

	mov DWORD [yes], 0

continue:
	pop rax
	cmp rax, sizeof_buf
	jge reading

;	Send header
	mov rax, sys_write
	mov rdi, [clientfd]
	mov rsi, http_response
	mov rdx, sizeof_http_response
	syscall

	mov rsi, write_str
	mov rdx, rax
	cmp rax, 0
	jl fail

	mov rax, sys_open
	mov rdi, directory_to_list
	mov rsi, O_RDONLY|O_DIRECTORY
	xor rdx, rdx
	syscall

	mov rsi, open_str
	mov rdx, rax
	cmp rax, 0
	jl fail

	mov [dirfd], rax

;	Read index file
	mov rax, sys_open
	mov rdi, index_file
	mov rsi, O_RDONLY
	xor rdx, rdx
	syscall

	mov rsi, open_str
	mov rdx, rax
	cmp rax, 0
	jl fail

	push rax

;	Start of new stuff

	mov rdx, sizeof_buf
	mov rsi, buf
	mov rdi, [rsp]
	mov rax, sys_read
	syscall

	mov rsi, read_str
	mov rdx, rax
	cmp rax, 0
	jl fail

	mov r9, rax
	mov [template_size], rax

	mov rsi, buf

find_temp_start:
	dec rax
	cmp rax, 0
	jl dir_loop
	inc rsi
	cmp BYTE [rsi], "%"
	jne find_temp_start
	cmp DWORD [rsi], "%%--"
	je find_temp_start_end
	jmp find_temp_start

find_temp_start_end:
	mov [temp_start], rsi
	push rsi
	dec rsi
	mov rdi, format_start
find_format_string:
	inc rsi
	mov rcx, buf+sizeof_buf
	sub rcx, rsi
	cmp rcx, 0
	jl dir_loop
	cmp BYTE [rsi], "%"
	jne find_format_string
	cmp WORD [rsi], "%s"
	jne find_format_string

	mov [rdi], rsi
	mov rdi, second_format
	cmp QWORD [second_format], 0
	je find_format_string

	pop rdx
	sub rdx, buf
	mov rsi, buf
	mov rdi, [clientfd]
	mov rax, sys_write
	syscall

find_temp_end:
	mov r10, rsi

	dec rsi
	
temp_end_loop:
	inc rsi
	mov rcx, buf+sizeof_buf
	sub rcx, rsi
	cmp rcx, 0
	jl dir_loop
	cmp BYTE [rsi], "-"
	jne temp_end_loop
	cmp DWORD [rsi], "--%%"
	jne temp_end_loop

	mov [temp_end], rsi

dir_loop:
	mov rax, sys_getdents64
	mov rdi, [dirfd]
	mov rsi, dir_entries
	mov rdx, sizeof_dir_entries
	syscall

	mov r10, rax

	mov rdi, rax
	cmp rax, 0
	jl exit
	je done

	mov rsi, dir_entries

inner_loop:
	push rsi
	add rsi, linux_dirent64.d_name
	call strlen

;	cmp DWORD[rsi+rax-4], ".png"
;	jne increment
;	Hide hidden files
	cmp BYTE [rsi], "."
	je increment

	push rsi
	push rax

	mov rdx, [format_start]
	sub rdx, [temp_start]
	sub rdx, 4
	mov rsi, [temp_start]
	add rsi, 4
	mov rdi, [clientfd]
	mov rax, sys_write
	syscall

	mov rdx, QWORD [rsp]
	mov rsi, QWORD [rsp-8]
	mov rdi, [clientfd]
	mov rax, sys_write
	syscall

	mov rdx, [second_format]
	sub rdx, [format_start]
	sub rdx, 2
	mov rsi, [format_start]
	add rsi, 2
	mov rdi, [clientfd]
	mov rax, sys_write
	syscall

	pop rdx
	pop rsi
	mov rdi, [clientfd]
	mov rax, sys_write
	syscall

	mov rdx, [temp_end]
	sub rdx, [second_format]
	sub rdx, 2
	mov rsi, [second_format]
	add rsi, 2
	mov rdi, [clientfd]
	mov rax, sys_write
	syscall

increment:
	pop rsi

	movzx rax, WORD [rsi+linux_dirent64.d_reclen]
	add rsi, rax
	sub r10, rax

	cmp r10, 0
	jg inner_loop

	jmp dir_loop

send_file:
	mov rsi, directory_to_list
	mov rdi, dir_entries
	cld
send_file_loop:
	movsd
	cmp DWORD [rsi], 0x0
	jne send_file_loop

	inc rdi
go_back_to_end:
	dec rdi
	cmp BYTE [rdi], "/"
	jne go_back_to_end
	
	mov rsi, buf+4
append_file_to_path:
	movsb
	cmp DWORD [rsi], " HTT"
	jne append_file_to_path

	push rdi

read_all_request:
	cmp DWORD [yes], 0
	je done_reading_full_request

	mov rax, sys_read
	mov rdi, [clientfd]
	mov rsi, buf
	mov rdx, sizeof_buf
	syscall

	push rax

	mov rdx, rax
	mov rsi, buf
	mov rdi, 1
	mov rax, sys_write
	syscall

	pop rax
	cmp rax, sizeof_buf
	jge read_all_request

done_reading_full_request:

	pop rdi

	mov BYTE [rdi], 0xa

	mov rdx, rdi
	sub rdx, dir_entries-1
	mov rsi, dir_entries
	mov rdi, 1
	mov rax, sys_write
	syscall

	mov BYTE [rsi+rax-1], 0x0

	mov rax, sys_open
	mov rdi, dir_entries
	mov rsi, O_RDONLY|O_NOFOLLOW
	xor rdx, rdx
	syscall

	cmp rax, 0
	jl http_send_failure

	push rax

;	Send header
	mov rax, sys_write
	mov rdi, [clientfd]
	mov rsi, http_response
	mov rdx, sizeof_http_response
	syscall

	mov rsi, write_str
	mov rdx, rax
	cmp rax, 0
	jl fail

	mov r10, 0x7ffff000
	mov rdx,  0
	mov rsi, [rsp]
	mov rdi, [clientfd]
	mov rax, sys_sendfile
	syscall

	mov rsi, sendfile_str
	mov rdx, rax,
	cmp rax, 0
	jl fail

	pop rdi
	mov rax, sys_close
	syscall

	jmp close_client_fd

http_send_failure:
	mov rax, sys_write
	mov rdi, [clientfd]
	mov rsi, http_not_found
	mov rdx, sizeof_http_not_found
	syscall

	mov rsi, write_str
	mov rdx, rax
	cmp rax, 0
	jl fail

	jmp close_client_fd

done:
	mov rax, sys_close
	mov rdi, [dirfd]
	syscall

	mov rax, sys_write
	mov rdi, [clientfd]
	mov rsi, [temp_end]
	add rsi, 4
	movsx rdx, DWORD [template_size]
	mov rcx, rsi
	sub rcx, buf
	sub rdx, rcx
	syscall

;	Close html file
	pop rdi
	mov rax, sys_close
	syscall

close_client_fd:
;	Close client socket
	mov rdi, [clientfd]
	mov rax, sys_close
	syscall

	jmp accept_loop

exit:
;	Close server socket
	mov rdi, [servfd]
	mov rax, sys_close
	syscall

	mov rax, sys_exit
	mov rdi, 0
	syscall

fail:
	mov rdi, result
	xor eax, eax
	call printf
	jmp exit
strlen:
	push rbp
	mov rbp, rsp
	push rsi
strlen_inner:
	inc rsi
	cmp BYTE [rsi], 0x0
	ja strlen_inner

	mov rax, rsi
	sub rax, [rsp]
	pop rsi

	pop rbp
	ret


section .data
msg db "Starting server", 0xa
msglen equ $- msg
server_info istruc sockaddr_in
	at sockaddr_in.sin_family, dw AF_INET
	at sockaddr_in.sin_port, dw 0x901f
	at sockaddr_in.sin_addr, db 127, 0, 0, 1
	;at sockaddr_in.sin_addr, db 0, 0, 0, 0 ; Use this for outside netowkr access
	at sockaddr_in.sin_zero, dq 0
iend
yes dd 1

bind_fail db "Error code", 0x0
result db "%s returned %d", 0xa, 0x0
remote_addr db "Connection from %d.%d.%d.%d on port %d", 0xa, 0x0
index_file db "index.html", 0x0
read_str db "read", 0x0
write_str db "write", 0x0
open_str db "open", 0x0
sendfile_str db "sendfile", 0x0
socket_str db "socket", 0x0
bind_str db "bind", 0x0
listen_str db "listen", 0x0
accept_str db "accept", 0x0
setsockopt_str db "setsockopt", 0x0

http_response	db "HTTP/1.1 200 OK", 0xd, 0xa
				db "Content-Type: image", 0xd, 0xa
;				db "Content-Length: %ld", 0xd, 0xa
				db "Server: Very Cool ASM Webserver", 0xd, 0xa
				db "Connection: close", 0xd, 0xa
				db 0xd, 0xa
sizeof_http_response equ $- http_response
http_not_found	db "HTTP/1.1 404 Not Found", 0xd, 0xa
				db "Content-Type: text/plain", 0xd, 0xa
				db "Connection: close", 0xd, 0xa
				db 0xd, 0xa
sizeof_http_not_found equ $- http_not_found

section .bss
servfd: resd 1
clientfd: resd 1
dirfd: resd 1
remote_sockaddr_size: resd 1
remote_sockaddr: resb sockaddr_in_size
template_size: resd 1
temp_start: resq 1
format_start: resq 1
second_format: resq 1
temp_end: resq 1
buf: resb 256
sizeof_buf equ $- buf
struc linux_dirent64
	.d_ino resq 1 ; ino64_t d_ino
	.d_off resq 1 ; off64_t d_off
	.d_reclen resw 1 ; unsigned short d_reclen
	.d_type resb 1 ; unsigned char d_type
	.d_name resb 1 ; char d_name[]
endstruc
dir_entries resb 512
sizeof_dir_entries equ $- dir_entries
