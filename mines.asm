[BITS 64]
[ORG 0x000000000200000]

%INCLUDE "bmdev.asm"

minesweeper_init:
	mov al, 50
	newline_loop:
		call b_print_newline
		dec al
		cmp al, 0
		;print a lot of newlines, effectively clearing the screen to black.
		jnz newline_loop
	mov al, 17
	mov ah, 18
	call b_move_cursor
	mov rsi, quitmsg
	call b_print_string
	call seed_rand    ;seed the random number generator with the system time
	jmp prepare_board

prepare_board:
	xor cx, cx
	mov rax, board
	mov rbx, visibleBoard
	prepare_board_clear:
		mov [rax], byte 0
		mov [rbx], byte 10
		inc rax
		inc rbx
		inc cx
		cmp cx, 256
		jl prepare_board_clear
	xor cl, cl
	prepare_board_mines:
		call place_mine_refactored
		inc cl
		cmp cl, 40    ;places this many mines
		jl prepare_board_mines
	mov al, 17
	mov ah, 18
	call b_move_cursor
	mov rsi, quitmsg
	call b_print_string
	jmp redraw

;al and rbx act as arguments for this function
;al is the index number of a cell in board
;rbx points to a function to apply to all of the valid surrounding cells
;assumes that the function at [rbx] also takes al as a parameter for index
surround:
	push rdx
	push rcx
	mov rcx, board
	and rax, 0x00000000000000ff    ;fill rax with 0's, excepting al
	mov dl, al
	mov dh, al
	and dl, 0x0f    ;dl becomes the column number
	shr dh, 4    ;dh becomes the row number
	surround_upl:    ;up-left cell
		cmp dh, 0    ;check for top row
		je surround_mdl
		cmp dl, 0    ;check for leftmost column
		je surround_upc
		push rax
		sub al, 11h
		call rbx
		pop rax
	surround_upc:    ;up-center cell
		;already jumped over if top row, so no further checks needed
		push rax
		sub al, 10h
		call rbx
		pop rax
	surround_upr:    ;up-right cell
		;already jumped over if top row, so no check for top row needed
		cmp dl, 0fh    ;check for rightmost column
		je surround_mdl
		push rax
		sub al, 0fh
		call rbx
		pop rax
	surround_mdl:    ;middle-left cell
		cmp dl, 00h    ;check for leftmost column
		je surround_mdr
		push rax
		sub al, 01h
		call rbx
		pop rax
	surround_mdr:    ;middle-left cell
		cmp dl, 0fh    ;check for rightmost column
		je surround_btl
		push rax
		add al, 01h
		call rbx
		pop rax
	surround_btl:    ;bottom-left cell
		cmp dh, 0fh    ;check for bottom row
		je surround_end
		cmp dl, 00h    ;check for leftmost column
		je surround_btc
		push rax
		add al, 0fh
		call rbx
		pop rax
	surround_btc:    ;bottom-center cell
		push rax
		add al, 10h
		call rbx
		pop rax
	surround_btr:    ;bottom-right cell
		cmp dl, 0fh    ;check for rightmost column
		je surround_end
		push rax
		add al, 11h
		call rbx
		pop rax
	surround_end:
	pop rcx
	pop rdx
ret

;increments a cell in board, unless it contains a mine
;takes al as index
increment_cell:
	push rcx
	push rbx
	push rax
	mov rbx, board
	and rax, 0x00000000000000ff
	add rbx, rax
	mov cl, [rbx]
	cmp cl, 9
	je increment_cell_end
	inc cl
	mov [rbx], cl
	increment_cell_end:
	pop rax
	pop rbx
	pop rcx
ret

place_mine_refactored:
	push rbx
	push rax
	place_mine_refactored_loop:
		xor rax, rax
		xor rbx, rbx
		call generate_random_byte
		inc ah
		;mov al, 0x80    ;test code places mine at specific location
		mov bl, al
		add rbx, board    ;make rbx point to the random cell
		cmp [rbx], byte 09h
		je place_mine_refactored_loop
	mov [rbx], byte 9
	mov rbx, increment_cell
	call surround    ;increments all of the numbers surrounding the mine
	pop rax
	pop rbx
ret

reveal_cell:
	push rcx
	push rbx
	push rax
	
	;clear rax except for ax, which holds the index of the cell
	and rax, 0x00000000000000ff
	mov rbx, board
	mov rcx, visibleBoard
	add rbx, rax
	add rcx, rax
	;only a value of 10 or 11 can indicate an uncleared cell, so if cell<10,
	;return
	cmp [rcx], byte 10
	jl reveal_cell_end
	mov ah, [rbx]
	mov [rcx], ah
	cmp ah, 0
	;if cell != 0, skip the recursive step
	jne reveal_cell_end
	mov rbx, reveal_cell
	call surround
	reveal_cell_end:
	pop rax
	pop rbx
	pop rcx
ret

;reveals a cell as if it has been clicked by the player, rather than cleared
;recursively.
player_reveal_cell:
	mov ah, [cursory]
	shl ah, 4
	mov al, [cursorx]
	add al, ah    ;generate the 1-dimensional index of the player's cursor
	xor rbx, rbx
	xor rcx, rcx
	mov bl, al
	mov cl, al
	;rbx and rcx hold the addresses of the corresponding cells in board and
	;visibleBoard.
	add rbx, board
	add rcx, visibleBoard
	mov ah, [rcx]
	cmp ah, 0ah
	;if cell has already been revealed, return.
	jne player_reveal_cell_end
	mov ah, [rbx]
	cmp ah, 9    ;if cell=9, player clicked a mine
	je lose
	mov [rcx], ah
	cmp [rbx], byte 0
	jne player_reveal_cell_end
	mov rbx, reveal_cell
	call surround    ;if the cell revealed is 0, clear all surrounding cells
	player_reveal_cell_end:
	jmp check_win
	
;seeds the random number generator with the system time
seed_rand:
	push rbx
	push rax
	
	call b_get_timecounter    ;moves the current time string into [rdi]
	mov bx, 907
	mul bx
	add ax, 367
	mov [lcg_seed], al
	mov [lcg_seed2], ah
	
	pop rax
	pop rbx
ret

;Uses a dual-phase linear congruential random number generator.  See lcg1 and
;lcg2.
generate_random_byte:
	push rbx
	xor al, al
	call lcg1
	mov bl, al
	call lcg2
	add al, bl
	jl generate_random_byte_end
	mov bl, [lcg_seed]
	mov bh, [lcg_seed2]
	mov [lcg_seed], bh
	mov [lcg_seed2], bl
	generate_random_byte_end
	pop rbx
ret

lcg1:
	push rbx
	mov al, [lcg_seed]
	mov bl, 71
	mul bl
	add al, 123
	mov [lcg_seed], al
	pop rbx
ret

lcg2:
	push rbx
	mov al, [lcg_seed2]
	mov bl, 131
	mul bl
	add al, 107
	mov [lcg_seed2], al
	pop rbx
ret

input_loop:
	call b_input_key_wait
	cmp al, 'w'
	je w_input
	cmp al, 'a'
	je a_input
	cmp al, 's'
	je s_input
	cmp al, 'd'
	je d_input
	cmp al, 'k'
	je k_input
	cmp al, 'j'
	je player_reveal_cell
	cmp al, 'R'
	je reveal_board
	cmp al, 'Q'    ;shift+Q quits the game
	jne redraw
	mov ah, 0
	mov al, 18
	;move cursor to below the board so that console output doesn't overlap -
	;with the residual output from the game.
	call b_move_cursor
ret

w_input:
	mov al, [cursory]
	cmp al, 0
	je redraw    ;if cursory is 0, can't move up, so don't change cursory
	dec al
	mov [cursory], al
	jmp redraw

a_input:
	mov ah, [cursorx]
	cmp ah, 0
	je redraw    ;if cursorx is 0, can't move left, so don't change cursorx
	dec ah
	mov [cursorx], ah
	jmp redraw
	
s_input:
	mov al, [cursory]
	cmp al, 15
	je redraw    ;if cursory is 15, can't move down, so don't change cursory
	inc al
	mov [cursory], al
	jmp redraw

d_input:
	mov ah, [cursorx]
	cmp ah, 15
	je redraw    ;if cursorx is 15, can't move right, so don't change cursorx
	inc ah
	mov [cursorx], ah
	jmp redraw
	
k_input:
	call place_flag
	jmp redraw

place_flag:
	push rbx
	push rax
	xor rax, rax
	mov ah, [cursorx]
	mov al, [cursory]
	shl al, 4
	add al, ah
	xor ah, ah
	mov rbx, visibleBoard
	add rbx, rax
	mov al, [rbx]
	cmp al, 10
	je place_flag_place
	cmp al, 11
	je place_flag_remove
	jmp place_flag_end
	place_flag_place:
		mov [rbx], byte 11
		jmp place_flag_end
	place_flag_remove:
		mov [rbx], byte 10
		jmp place_flag_end
	place_flag_end:
	pop rax
	pop rbx
ret


get_char_and_color:    ;takes ah and al as x and y coordinates on the grid
	push rdx
	push rcx
	mov rbx, visibleBoard
	shl al, 4    ;al *= 16 so that rbx + al + ah points to the given cell
	xor rcx, rcx
	xor rdx, rdx
	mov cl, ah
	mov dl, al
	;move the values of ah and al into the c and d registers so that they can
	;be added to rbx
	add rbx, rcx
	add rbx, rdx
	mov al, [rbx]   ;move the value of the cell in visibleBoard to al
	cmp al, 8
	jle get_char_and_color_number_cell
	cmp al, 9
	je get_char_and_color_mine
	cmp al, 10
	je get_char_and_color_uncleared_cell
	cmp al, 11
	je get_char_and_color_flagged_cell
	mov bl, 0xD0    ;any errors in the visible cells table will be indicated by
	mov al, '!'     ;a black exclamation mark in a magenta cell.
	jmp get_char_and_color_end
	get_char_and_color_number_cell:
		;clear all of rax except for the last byte(al)
		and rax, 0x00000000000000FF
		;lower half of bl represents the character color
		mov bl, [cellColors + rax]
		;upper half of bl makes the background dark grey
		or bl, 0x80
		;make al represent the character corresponding with the number(see
		;ascii table)
		add al, 48
		jmp get_char_and_color_end
	get_char_and_color_mine:
		mov bl, 0x70    ;mines are a black X in a light grey cell
		mov al, 'X'
		jmp get_char_and_color_end
	get_char_and_color_uncleared_cell:
		mov bl, 0x70    ;uncleared cells are blank light grey cells
		mov al, ' '
		jmp get_char_and_color_end
	get_char_and_color_flagged_cell:
		mov bl, 0x7C    ;flagged cells are light grey cells with a bright red F
		mov al, 'F'
		jmp get_char_and_color_end
	get_char_and_color_end:
	pop rcx
	pop rdx
ret

check_win:
	xor al, al    ;al is the index being checked
	check_win_loop:
		xor rbx, rbx
		xor rcx, rcx
		mov bl, al
		mov cl, al
		add rbx, board
		add rcx, visibleBoard
		cmp [rbx], byte 9    ;check for a mine
		;doesn't matter that a cell with a mine hasn't been cleared
		je check_win_loop_continue
		cmp [rcx], byte 10
		jge check_win_end
		;found uncleared, non-mine cell, so jump to end of loop.  You didn't
		;win. Nobody likes you.
		check_win_loop_continue:
		;keep looping and incrementing al until it wraps around and becomes 0
		;after 256 iterations
		inc al
		cmp al, 0
		jne check_win_loop
	jmp win
	check_win_end:
	jmp redraw   ;didn't win, so continue game loop

win:    ;user has won
	mov al, 17
	mov ah, 18
	call b_move_cursor
	mov rsi, winmsg
	call b_print_string    ;print win message
	jmp reveal_board
	
lose:    ;user has lost
	mov al, 17
	mov ah, 18
	call b_move_cursor
	mov rsi, losemsg
	call b_print_string    ;print lose message
	jmp reveal_board
	
reveal_board:
	mov rax, board
	mov rbx, visibleBoard
	xor cx, cx
	reveal_board_loop:
		mov dl, [rax]
		mov [rbx], dl
		inc rax
		inc rbx
		inc cx
		cmp cx, 256
		jl reveal_board_loop
	call print_board
	call b_input_key_wait    ;wait for the user to press a key and then restart
	jmp prepare_board

redraw:
	call print_board
	mov ah, [cursorx]
	mov al, [cursory]
	add al, 2
	inc ah
	;move the os cursor back to the user position to draw the user's cursor
	call b_move_cursor
	sub al, 2
	dec ah
	;get the character and color at the location of the user's cursor
	call get_char_and_color
	mov bl, 0xC0    ;replace the color with black on red
	call b_print_char_with_color    ;draw the cursor
	xor ax, ax
	call b_move_cursor    ;move the os cursor to 0, 0
	jmp input_loop
	
print_board:
	push rcx
	push rax
	;cx will act as an iterator in visibleBoard, representing the current index
	xor cx, cx
	redraw_loop:
		mov ah, cl    ;ah is the x coordinate of the current cell
		mov al, cl    ;al is the y coordinate of the current cell
		and ah, 0x0F    ;ah = cl % 16
		shr al, 4    ;al = cl / 16
		inc ah
		add al, 2
		call b_move_cursor
		dec ah
		sub al, 2
		call get_char_and_color
		call b_print_char_with_color
		inc cx
		cmp cx, 256
		jne redraw_loop
	pop rax
	pop rcx
ret

;moves the cursor below the board and calls b_debug_dump_reg
dump_registers_below_board:
	push rax
	xor ah, ah
	mov al, 18
	call b_move_cursor
	pop rax
	call b_debug_dump_reg
ret
;------------------------------
;the location at which the initial seed and future seeds for the random number
;generator should be stored.  An initial seed should be stored here before
;generating any numbers. 7 is hardcoded in because, I dunno, 7.
lcg_seed: db 7
lcg_seed2:db 3

;the x and y coordinates of the cursor for when the user is in charge of it
;these coordinates pertain to the board, not the screen
cursorx: db 7
cursory: db 7

;16x16 array of bytes to serve as the minesweeper board.
;0-8 indicates the number of surrounding mines, and 9 indicates a mine.
board: times 256 db 0

;the array which indicates uncleared cells(10) and flagged cells(11)
visibleBoard: times 256 db 10

;graphical test board. Leave commented out unless you want a really wonky board
;visibleBoard: times 16 db 0,1,2,3,4,5,6,7,8,9,10,11,12,0,0,0
;colors corresponding to numbers on the visible grid
cellColors: db 0x08, 0x09, 0x02, 0x0C, 0x01, 0x04, 0x0b, 0x00, 0x0A
;              grey  blue  green red   blue  red   cyan  black green

;Strings to display at the bottom of the board.  They're all the same length so
;that writing one to the screen will erase the previous message from the screen
;completely.
quitmsg: db 'Press Shift+Q to quit the game.',0
winmsg:  db 'You win!  Press any key.       ',0
losemsg: db 'You lose.  Press any key.      ',0

;the time string will be stored here for seeding the random number generator
time_string: times 9 db 0