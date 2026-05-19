build:
	nasm -f elf64 -dWEBSERVER_TO_LIST="\"$$HOME/Downloads/\"" webserv.asm
	ld -o server webserv.o -lc -dynamic-linker /lib64/ld-linux-x86-64.so.2
	rm webserv.o

