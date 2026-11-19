; ============================================================================
; GALAXIAN '79 — BEGINNER'S FULLY ANNOTATED SOURCE
; ============================================================================
; WHAT THIS IS
;   A Commodore 64 game written in 6502-family assembly for the 6510 CPU.
;   The game uses the VIC-II video chip, SID sound chip and CIA joystick input.
;   Read the routine comments to connect each instruction to game behavior.
;
; HOW TO BUILD (ACME assembler)
;   acme --strict-segments -f cbm -o galaxian.prg galaxian.asm
;   The !to directive below names the CBM-format output galaxian.prg.
;   Load the PRG in VICE or a C64 and type RUN (or use emulator autostart).
;
; READING AN ASSEMBLY LINE
;   label:         A named address. Other instructions can jump to it.
;   lda #3         Put the literal number 3 into register A (# = immediate).
;   lda lives      Read the byte stored at the address named lives.
;   sta lives      Write A to the byte stored at lives.
;   lda $d012      Read hexadecimal address $D012 (the raster register).
;   jsr motion     Call motion; motion finishes with rts.
;   beq label      Branch to label if the previous result was zero.
;   ; comment      An explanation for humans; ACME ignores it.
;
; IMPORTANT SYMBOLS
;   $ means hexadecimal (base 16): $10 = 16 decimal, $FF = 255.
;   % means binary (base 2) in ACME: %00000001 = 1.
;   # means use the value itself rather than the byte stored at an address.
;   A, X and Y are the CPU's three 8-bit working registers.
;   A flag is a 1-bit CPU status value (zero, carry, negative, etc.).
;   The carry flag is used in arithmetic and comparisons.
;   !byte puts literal bytes into the output; !word puts 16-bit values.
;   !fill reserves/initialises repeated bytes; !for repeats source at build time.
;   *=$3000 means place following bytes at C64 address $3000.
;
; HOW A FRAME WORKS
;   Wait for raster timing -> read joystick -> move objects -> check hits
;   -> redraw formation/HUD -> update SID and explosion timers -> repeat.
;   PAL is roughly 50 frames/second. Timing here is frame-count based.
;
; C64 VIDEO MEMORY
;   $0400 and $3800 : two 1000-character screens for flicker reduction.
;   $D800             : colour RAM, separate from screen character codes.
;   $2000 onwards    : custom character graphics in RAM.
;   $3000 onwards    : hardware sprite bitmap graphics (64 bytes each).
;   $D000-$D02E      : VIC-II sprite registers and colours.
;   A sprite is 24x21 pixels; a character tile is 8x8 pixels.
;   Multicolour pixels are twice the width of hires pixels.
;   The VIC uses an extra bit in $D010 for X positions above 255.
;
; GAME STATE
;   `alive` contains 46 entries, one per formation alien.
;   `diveindex` selects an alien; `diveon` marks a live dive.
;   `alienboom` and `playerboom` count remaining explosion frames.
;   `scorelo`/`scorehi` and `highlo`/`highhi` are 16-bit values.
;   The high score lasts across restarts, not power cycles.
;
; BEGINNER TIP
;   Read start -> main -> joystick -> motion -> checkhits -> paint -> sprites.
;   Data tables and bitmaps at the end are pictures, not CPU instructions.
; ============================================================================

; GALAXIAN '79 C64 - original arcade-inspired, single-file PAL game
; ACME: acme galaxian.asm  (produces galaxian.prg)
; Joystick port 2: left/right/fire. BASIC: RUN
; Screen-code formation: 46 enemies, 10+10+10+10+6.
!to "galaxian.prg",cbm ; ACME output file
; Declare zero-page pointers before use so ACME selects indirect ZP addressing.
ptr = $fb
cptr = $fd
*=$0801
!byte $0b,$08,$0a,$00,$9e
!text "2064"
!byte 0,0,0
*=$0810

; ---------------------------------------------------------------------------
; START: Initialise the CPU, VIC-II display, SID sound chip, persistent high score, character set and title screen. SEI prevents interrupts during setup.
; ---------------------------------------------------------------------------
start:
 sei                          ; Disable maskable interrupts temporarily
 lda #$37                     ; Load a value into A
 sta $01                      ; Store A into memory
 lda #0                       ; Load a value into A
 sta $d020                    ; Store A into memory; screen border colour
 sta $d021                    ; Store A into memory; background colour
 sta $d015                    ; Store A into memory; sprite enable bitmask
 sta $d01c                    ; Store A into memory; sprite multicolour mask
 sta $d017                    ; Store A into memory; sprite vertical expansion mask
 sta $d01d                    ; Store A into memory; sprite horizontal expansion mask
 sta $d010                    ; Store A into memory; ninth X-position bits for sprites 0–7
 lda #$1b                     ; Load a value into A
 sta $d011                    ; Store A into memory; VIC display/raster control
 lda #$03                     ; Load a value into A
 sta $dd00                    ; Store A into memory; VIC memory-bank selector
 lda #$18                     ; Load a value into A
 sta $d016                    ; Store A into memory; VIC horizontal/multicolour mode
 lda #$18                     ; Load a value into A
 sta $d018                    ; Store A into memory; screen and character-set base selector
 lda #15                      ; Load a value into A
 sta $d418                    ; Store A into memory; SID master volume
 lda #0                       ; Load a value into A
 sta $d404                    ; Store A into memory
 sta $d40b                    ; Store A into memory
 sta $d412                    ; Store A into memory
 lda #0                       ; Load a value into A
 sta highlo                   ; Store A into memory; low byte of session high score
 sta highhi                   ; Store A into memory; high byte of session high score
 jsr charset_init             ; Call a subroutine (return address saved on stack)
 jsr clear                    ; Call a subroutine (return address saved on stack)
 lda #0                       ; Load a value into A
 sta screenbank               ; Store A into memory; which screen is currently visible (double buffering)
 jsr title_screen             ; Call a subroutine (return address saved on stack)
 cli                          ; Enable maskable interrupts

; ---------------------------------------------------------------------------
; ATTRACT: Title-screen loop. Poll the keyboard until P is pressed, then initialise a new game.
; ---------------------------------------------------------------------------
attract:
 jsr read_p                   ; Call a subroutine (return address saved on stack)
 bcc attract                  ; Branch when carry is clear
 sei                          ; Disable maskable interrupts temporarily
 jsr begin_play               ; Call a subroutine (return address saved on stack)
 cli                          ; Enable maskable interrupts

; ---------------------------------------------------------------------------
; MAIN: Main game loop. Synchronise to raster line 250, process input, move objects, check collisions, redraw and update effects.
; ---------------------------------------------------------------------------
main:
 lda $d012                    ; Load a value into A; current raster line
 cmp #250                     ; Compare A against operand
 bne main                     ; Branch when zero flag is clear

; ---------------------------------------------------------------------------
; WAITFRAME: Wait for raster line 250 to pass so the loop executes once per video frame rather than repeatedly on one scanline.
; ---------------------------------------------------------------------------
waitframe:
 lda $d012                    ; Load a value into A; current raster line
 cmp #250                     ; Compare A against operand
 beq waitframe                ; Branch when zero flag is set
 inc tick                     ; Increase memory byte by 1; frame counter used for timing
 jsr joystick                 ; Call a subroutine (return address saved on stack)
 jsr motion                   ; Call a subroutine (return address saved on stack)
 jsr checkhits                ; Call a subroutine (return address saved on stack)
 jsr paint                    ; Call a subroutine (return address saved on stack)
 jsr soundtick                ; Call a subroutine (return address saved on stack)
 jsr explosion_tick           ; Call a subroutine (return address saved on stack)
 lda gamestate                ; Load a value into A; 1 during play, 0 after game over
 beq game_over                ; Branch when zero flag is set
 jmp main                     ; Jump unconditionally

; ---------------------------------------------------------------------------
; GAME_OVER: Turn off sprites and draw the GAME OVER message using screen codes.
; ---------------------------------------------------------------------------
game_over:
 lda #0                       ; Load a value into A
 sta $d015                    ; Store A into memory; sprite enable bitmask
 jsr menu_setup               ; Call a subroutine (return address saved on stack)
 ldx #0                       ; Load a value into X
over_line:
 lda gameover_text,x          ; Load a value into A
 beq over_end                 ; Branch when zero flag is set
 sta $059f,x                  ; row 10 column 15 (centred 9 chars) | Store A into memory
 inx                          ; Increase X by 1
 bne over_line                ; Branch when zero flag is clear
over_end:
 cli                          ; Enable maskable interrupts

; ---------------------------------------------------------------------------
; WAIT_RESTART: Keep checking for P before starting another game. High score is intentionally not cleared.
; ---------------------------------------------------------------------------
wait_restart:
 jsr read_p                   ; Call a subroutine (return address saved on stack)
 bcc wait_restart             ; Branch when carry is clear
 sei                          ; Disable maskable interrupts temporarily
 jsr begin_play               ; Call a subroutine (return address saved on stack)
 cli                          ; Enable maskable interrupts
 jmp main                     ; Jump unconditionally

; Read P from KERNAL keyboard buffer (SCNKEY and GETIN).
; Carry set when P is pressed. Wait for key release to avoid repeats.

; ---------------------------------------------------------------------------
; READ_P: Call KERNAL keyboard scanning/GETIN. Carry set signals P; carry clear means no P detected.
; ---------------------------------------------------------------------------
read_p:
 jsr $ff9f                    ; Call a subroutine (return address saved on stack)
 jsr $ffe4                    ; Call a subroutine (return address saved on stack)
 cmp #$50                     ; Compare A against operand
 beq p_pressed                ; Branch when zero flag is set
 cmp #$70                     ; Compare A against operand
 beq p_pressed                ; Branch when zero flag is set
 clc                          ; Clear carry before addition / unsigned comparison
 rts                          ; Return from subroutine
p_pressed:
 sec                          ; Set carry before subtraction
 rts                          ; Return from subroutine


; ---------------------------------------------------------------------------
; BEGIN_PLAY: Restore the gameplay VIC settings (multicolour characters, custom RAM font), clear the display and initialise a new round.
; ---------------------------------------------------------------------------
begin_play:
 jsr restore_character_display ; Leave bitmap mode before drawing the game.
 lda #$03                     ; Load a value into A
 sta $dd00                    ; Store A into memory; VIC memory-bank selector
 lda #$18                     ; 40-column VIC multicolour characters | Load a value into A
 sta $d016                    ; Store A into memory; VIC horizontal/multicolour mode
 lda #$00                     ; Load a value into A
 sta $d021                    ; VIC colour 0 is black; 1 is white | Store A into memory; background colour
 lda #$06                     ; Load a value into A
 sta $d022                    ; shared blue outline | Store A into memory; shared character multicolour 1
 lda #$01                     ; Load a value into A
 sta $d023                    ; shared white highlights | Store A into memory; shared character multicolour 2
 jsr clear                    ; Call a subroutine (return address saved on stack)
 lda #$18                     ; screen $0400, custom RAM character set $2000 | Load a value into A
 sta $d018                    ; Store A into memory; screen and character-set base selector
 lda #0                       ; Load a value into A
 sta screenbank               ; Store A into memory; which screen is currently visible (double buffering)
 lda #1                       ; Load a value into A
 sta gamestate                ; Store A into memory; 1 during play, 0 after game over
 jsr initgame                 ; Call a subroutine (return address saved on stack)
 jsr paint_force              ; Call a subroutine (return address saved on stack)
 rts                          ; Return from subroutine


; ---------------------------------------------------------------------------
; TITLE_SCREEN: Enter the bitmap splash; P input is still polled by attract.
; ---------------------------------------------------------------------------
title_screen:
 jmp draw_bitmap_splash ; Display the bitmap, then return to the startup caller.
character_title_screen:
 jsr menu_setup               ; Call a subroutine (return address saved on stack)
 ldx #0                       ; Load a value into X
title_line:
 lda title_text,x             ; Load a value into A
 beq title_prompt             ; Branch when zero flag is set
 sta $059e,x                  ; row 10, column 14 (11 characters) | Store A into memory
 inx                          ; Increase X by 1
 bne title_line               ; Branch when zero flag is clear
title_prompt:
 jmp menu_prompt              ; Jump unconditionally


; ---------------------------------------------------------------------------
; MENU_SETUP: Switch to the ROM font and standard character mode so menu letters are legible; clear both screen buffers.
; ---------------------------------------------------------------------------
menu_setup:
 jsr restore_character_display ; Game-over menus use standard text mode.
 lda #$03                     ; Load a value into A
 sta $dd00                    ; Store A into memory; VIC memory-bank selector
 lda #0                       ; Load a value into A
 sta $d015                    ; Store A into memory; sprite enable bitmask
 sta $d01c                    ; Store A into memory; sprite multicolour mask
 sta $d010                    ; Store A into memory; ninth X-position bits for sprites 0–7
 lda #$03                     ; Load a value into A
 sta $dd00                    ; VIC bank 0: ROM charset at $1000 | Store A into memory; VIC memory-bank selector
 lda #0                       ; Load a value into A
 sta $d015                    ; Store A into memory; sprite enable bitmask
 jsr clear                    ; Call a subroutine (return address saved on stack)
 lda #$14                     ; screen $0400, VIC built-in uppercase character ROM at $1000 | Load a value into A
 sta $d018                    ; Store A into memory; screen and character-set base selector
 lda #$08                     ; normal 40-column hires text | Load a value into A
 sta $d016                    ; Store A into memory; VIC horizontal/multicolour mode
 lda #0                       ; Load a value into A
 sta $d017                    ; Store A into memory; sprite vertical expansion mask
 sta $d01d                    ; Store A into memory; sprite horizontal expansion mask
 sta $d01b                    ; Store A into memory; sprite priority mask
 lda #0                       ; Load a value into A
 sta $d015                    ; Store A into memory; sprite enable bitmask

; ---------------------------------------------------------------------------
; MENU_PROMPT: Write PRESS P TO PLAY to row 13, column 12 of the 40-column screen.
; ---------------------------------------------------------------------------
menu_prompt:
 ldx #0                       ; Load a value into X
menu_prompt_loop:
 lda prompt_text,x            ; Load a value into A
 beq title_end                ; Branch when zero flag is set
 sta $0614,x                  ; row 13 col 12 (15 characters) | Store A into memory
 inx                          ; Increase X by 1
 bne menu_prompt_loop         ; Branch when zero flag is clear
title_end:
 rts                          ; Return from subroutine



; ---------------------------------------------------------------------------
; CLEAR: Fill both screen buffers with spaces and the colour RAM with white. Uses X wrapping from 255 to 0 as the loop end.
; ---------------------------------------------------------------------------
clear:
 lda #$20                     ; Load a value into A
 ldx #0                       ; Load a value into X
cl:
 sta $0400,x                  ; Store A into memory
 sta $0500,x                  ; Store A into memory
 sta $0600,x                  ; Store A into memory
 sta $06e8,x                  ; Store A into memory
 sta $3800,x                  ; Store A into memory
 sta $3900,x                  ; Store A into memory
 sta $3a00,x                  ; Store A into memory
 sta $3ae8,x                  ; Store A into memory
 inx                          ; Increase X by 1
 bne cl                       ; Branch when zero flag is clear
 lda #1                       ; Load a value into A
 ldx #0                       ; Load a value into X
cc:
 sta $d800,x                  ; Store A into memory
 sta $d900,x                  ; Store A into memory
 sta $da00,x                  ; Store A into memory
 sta $dae8,x                  ; Store A into memory
 inx                          ; Increase X by 1
 bne cc                       ; Branch when zero flag is clear
 rts                          ; Return from subroutine


; ---------------------------------------------------------------------------
; INITGAME: Reset lives, score, wave and ship position for a new game; leave the persistent high-score bytes alone.
; ---------------------------------------------------------------------------
initgame:
 lda #3                       ; Load a value into A
 sta lives                    ; Store A into memory; player lives remaining
 lda #0                       ; Load a value into A
 sta scorelo                  ; Store A into memory; low byte of current 16-bit score
 sta scorehi                  ; Store A into memory; high byte of current 16-bit score
 sta wave                     ; Store A into memory; current wave number
 lda #160                     ; Load a value into A
 sta shipx                    ; Store A into memory; player X position, low 8 bits
 lda #0                       ; Load a value into A
 sta shipxhi                  ; Store A into memory; player X position, ninth bit
 jsr newwave                  ; Call a subroutine (return address saved on stack)
 rts                          ; Return from subroutine

; ---------------------------------------------------------------------------
; NEWWAVE: Prepare a new 46-alien formation and reset bullets, diving state and movement.
; ---------------------------------------------------------------------------
newwave:
 inc wave                     ; Increase memory byte by 1; current wave number
 lda #0                       ; Load a value into A
 sta shoton                   ; Store A into memory; nonzero while player laser is active
 sta enemyshoton              ; Store A into memory; nonzero while enemy bullet is active
 sta diveon                   ; Store A into memory; nonzero while a dive is active
 sta formationstep            ; Store A into memory
 sta drift                    ; Store A into memory; horizontal formation offset
 sta divephase                ; Store A into memory; current position in the 64-step dive curve
 sta divepick                 ; Store A into memory; next candidate index for diving
 lda #1                       ; Load a value into A
 sta dir                      ; Store A into memory; formation travel direction
 ldx #45                      ; Load a value into X
nw:
 lda #1                       ; Load a value into A
 sta alive,x                  ; Store A into memory
 dex                          ; Decrease X by 1
 bpl nw                       ; Branch when result is nonnegative
 lda #46                      ; Load a value into A
 sta remaining                ; Store A into memory; number of aliens left in this wave
 jsr hud                      ; Call a subroutine (return address saved on stack)
 rts                          ; Return from subroutine


; ---------------------------------------------------------------------------
; JOYSTICK: Read CIA #1 port A ($DC00), joystick port 2. Joystick switches are active LOW: a cleared bit means pressed.
; ---------------------------------------------------------------------------
joystick:
 lda $dc00                    ; Load a value into A; CIA joystick port 2 inputs
 and #4                       ; Mask A to keep selected bits
 bne joyright                 ; Branch when zero flag is clear
 ; Left edge of visible 320px screen is sprite X=24.
 lda shipxhi                  ; Load a value into A; player X position, ninth bit
 bne moveleft                 ; Branch when zero flag is clear
 lda shipx                    ; Load a value into A; player X position, low 8 bits
 cmp #27                      ; Compare A against operand
 bcc joyright                 ; Branch when carry is clear

; ---------------------------------------------------------------------------
; MOVELEFT: Move ship 3 pixels left, using SBC carry/borrow to update the ninth X bit.
; ---------------------------------------------------------------------------
moveleft:
 sec                          ; Set carry before subtraction
 lda shipx                    ; Load a value into A; player X position, low 8 bits
 sbc #3                       ; Subtract operand and borrow from A
 sta shipx                    ; Store A into memory; player X position, low 8 bits
 lda shipxhi                  ; Load a value into A; player X position, ninth bit
 sbc #0                       ; Subtract operand and borrow from A
 sta shipxhi                  ; Store A into memory; player X position, ninth bit

; ---------------------------------------------------------------------------
; JOYRIGHT: Test the right-direction joystick bit, then clamp the ship near the right screen edge.
; ---------------------------------------------------------------------------
joyright:
 lda $dc00                    ; Load a value into A; CIA joystick port 2 inputs
 and #8                       ; Mask A to keep selected bits
 bne joyfire                  ; Branch when zero flag is clear
 ; Right edge is X=320 (sprite width 24, visible area ends 344).
 lda shipxhi                  ; Load a value into A; player X position, ninth bit
 beq moveright                ; Branch when zero flag is set
 lda shipx                    ; Load a value into A; player X position, low 8 bits
 cmp #62                      ; Compare A against operand
 bcs joyfire                  ; Branch when carry is set

; ---------------------------------------------------------------------------
; MOVERIGHT: Move ship 3 pixels right. ADC carry propagates into the high X-position byte.
; ---------------------------------------------------------------------------
moveright:
 clc                          ; Clear carry before addition / unsigned comparison
 lda shipx                    ; Load a value into A; player X position, low 8 bits
 adc #3                       ; Add operand and carry to A
 sta shipx                    ; Store A into memory; player X position, low 8 bits
 lda shipxhi                  ; Load a value into A; player X position, ninth bit
 adc #0                       ; Add operand and carry to A
 sta shipxhi                  ; Store A into memory; player X position, ninth bit

; ---------------------------------------------------------------------------
; JOYFIRE: Start a player laser if fire is pressed and no laser is already active. Also trigger a short SID note.
; ---------------------------------------------------------------------------
joyfire:
 lda $dc00                    ; Load a value into A; CIA joystick port 2 inputs
 and #16                      ; Mask A to keep selected bits
 bne joyend                   ; Branch when zero flag is clear
 lda shoton                   ; Load a value into A; nonzero while player laser is active
 bne joyend                   ; Branch when zero flag is clear
 lda #1                       ; Load a value into A
 sta shoton                   ; Store A into memory; nonzero while player laser is active
 lda shipx                    ; Load a value into A; player X position, low 8 bits
 clc                          ; Clear carry before addition / unsigned comparison
 adc #1                       ; Add operand and carry to A
 sta shotx                    ; Store A into memory; player laser X low byte
 lda shipxhi                  ; Load a value into A; player X position, ninth bit
 adc #0                       ; Add operand and carry to A
 sta shotxhi                  ; Store A into memory; player laser X high bit
 lda #203                     ; Load a value into A
 sta shoty                    ; Store A into memory; player laser Y position
 lda #8                       ; Load a value into A
 sta laserlife                ; Store A into memory; laser sound effect countdown
 lda #0                       ; Load a value into A
 sta $d404                    ; Store A into memory
 lda #$70                     ; Load a value into A
 sta $d400                    ; Store A into memory
 lda #$27                     ; Load a value into A
 sta $d401                    ; Store A into memory
 lda #$09                     ; Load a value into A
 sta $d405                    ; Store A into memory
 lda #$30                     ; Load a value into A
 sta $d406                    ; Store A into memory
 lda #$81                     ; Load a value into A
 sta $d404                    ; Store A into memory
joyend: rts                   ; Return from subroutine


; ---------------------------------------------------------------------------
; MOTION: Update the player laser, enemy laser, formation drift, diving alien and enemy firing.
; ---------------------------------------------------------------------------
motion:
 lda shoton                   ; Load a value into A; nonzero while player laser is active
 beq noshotmove               ; Branch when zero flag is set
 lda shoty                    ; Load a value into A; player laser Y position
 cmp #45                      ; Compare A against operand
 bcc endshot                  ; Branch when carry is clear
 sec                          ; Set carry before subtraction
 sbc #5                       ; Subtract operand and borrow from A
 sta shoty                    ; Store A into memory; player laser Y position
 jmp noshotmove               ; Jump unconditionally

; ---------------------------------------------------------------------------
; ENDSHOT: Deactivate the laser once it leaves the playable area.
; ---------------------------------------------------------------------------
endshot:
 lda #0                       ; Load a value into A
 sta shoton                   ; Store A into memory; nonzero while player laser is active

; ---------------------------------------------------------------------------
; NOSHOTMOVE: Move an active enemy shot downward and turn it off below the screen.
; ---------------------------------------------------------------------------
noshotmove:
 lda enemyshoton              ; Load a value into A; nonzero while enemy bullet is active
 beq noshotenemy              ; Branch when zero flag is set
 lda enemyshoty               ; Load a value into A; enemy bullet Y position
 clc                          ; Clear carry before addition / unsigned comparison
 adc #3                       ; Add operand and carry to A
 sta enemyshoty               ; Store A into memory; enemy bullet Y position
 cmp #240                     ; Compare A against operand
 bcc noshotenemy              ; Branch when carry is clear
 lda #0                       ; Load a value into A
 sta enemyshoton              ; Store A into memory; nonzero while enemy bullet is active

; ---------------------------------------------------------------------------
; NOSHOTENEMY: Every eighth frame, adjust the formation drift and reverse direction at its limits.
; ---------------------------------------------------------------------------
noshotenemy:
 lda tick                     ; Load a value into A; frame counter used for timing
 and #7                       ; Mask A to keep selected bits
 bne nomarch                  ; Branch when zero flag is clear
 ; Keep 2-character-wide aliens inside columns 0..39.
 ; Rightmost regular alien starts at column 35, so drift <= 3.
 lda dir                      ; Load a value into A; formation travel direction
 beq marchleft                ; Branch when zero flag is set
 inc drift                    ; Increase memory byte by 1; horizontal formation offset
 lda drift                    ; Load a value into A; horizontal formation offset
 cmp #3                       ; Compare A against operand
 bcc nomarch                  ; Branch when carry is clear
 lda #0                       ; Load a value into A
 sta dir                      ; Store A into memory; formation travel direction
 jmp nomarch                  ; Jump unconditionally
marchleft:
 lda drift                    ; Load a value into A; horizontal formation offset
 beq turnright                ; Branch when zero flag is set
 dec drift                    ; Decrease memory byte by 1; horizontal formation offset
 jmp nomarch                  ; Jump unconditionally
turnright:
 lda #1                       ; Load a value into A
 sta dir                      ; Store A into memory; formation travel direction

; ---------------------------------------------------------------------------
; NOMARCH: If a dive is active, advance it along a precomputed curve and downward through the playfield.
; ---------------------------------------------------------------------------
nomarch:
 lda diveon                   ; Load a value into A; nonzero while a dive is active
 beq launch                   ; Branch when zero flag is set
 lda divey                    ; Load a value into A; diving alien Y
 clc                          ; Clear carry before addition / unsigned comparison
 adc #3                       ; Add operand and carry to A
 sta divey                    ; Store A into memory; diving alien Y
 ; smooth curved dive: left/right motion changes with dive phase
 inc divephase                ; Increase memory byte by 1; current position in the 64-step dive curve
 lda divephase                ; Load a value into A; current position in the 64-step dive curve
 and #$3f                     ; Mask A to keep selected bits
 tax                          ; Copy A into X
 lda divecurve,x              ; Load a value into A
 sta diveoffset               ; Store A into memory; signed horizontal offset from the dive curve
 clc                          ; Clear carry before addition / unsigned comparison
 adc diveorigin               ; Add operand and carry to A; diving alien starting X low byte
 sta divex                    ; Store A into memory; diving alien X low byte
 lda diveoffset               ; Load a value into A; signed horizontal offset from the dive curve
 bmi dive_negative            ; Branch when result is negative
 lda diveoriginhi             ; Load a value into A; diving alien starting X high byte
 adc #0                       ; Add operand and carry to A
 sta divexhi                  ; Store A into memory; diving alien ninth X bit
 jmp divebottom               ; Jump unconditionally

; ---------------------------------------------------------------------------
; DIVE_NEGATIVE: The dive curve offset is negative; sign-extend it to the high X byte.
; ---------------------------------------------------------------------------
dive_negative:
 lda diveoriginhi             ; Load a value into A; diving alien starting X high byte
 adc #$ff                     ; Add operand and carry to A
 sta divexhi                  ; Store A into memory; diving alien ninth X bit

; ---------------------------------------------------------------------------
; DIVEBOTTOM: Deactivate a dive when it reaches the bottom edge.
; ---------------------------------------------------------------------------
divebottom:
 lda divey                    ; Load a value into A; diving alien Y
 cmp #237                     ; Compare A against operand
 bcc launch                   ; Branch when carry is clear
 lda #0                       ; Load a value into A
 sta diveon                   ; Store A into memory; nonzero while a dive is active
 jmp launch                   ; Jump unconditionally

; ---------------------------------------------------------------------------
; LAUNCH: Periodically choose a living alien to begin a dive; do not give up merely because one candidate was destroyed.
; ---------------------------------------------------------------------------
launch:
 lda diveon                   ; Load a value into A; nonzero while a dive is active
 bne enemyfire                ; Branch when zero flag is clear
 lda tick                     ; Load a value into A; frame counter used for timing
 and #63                      ; Mask A to keep selected bits
 bne enemyfire                ; Branch when zero flag is clear
 ; Search for a surviving alien, rather than giving up when
 ; the next chosen slot has already been destroyed.
 lda divepick                 ; Load a value into A; next candidate index for diving
 clc                          ; Clear carry before addition / unsigned comparison
 adc #7                       ; Add operand and carry to A
 cmp #46                      ; Compare A against operand
 bcc divepickok               ; Branch when carry is clear
 sbc #46                      ; Subtract operand and borrow from A
divepickok:
 sta divepick                 ; Store A into memory; next candidate index for diving
 tax                          ; Copy A into X
 ldy #46                      ; Load a value into Y

; ---------------------------------------------------------------------------
; DIVE_SEARCH: Scan up to all 46 alien slots, wrapping at the end, until a surviving alien is found.
; ---------------------------------------------------------------------------
dive_search:
 lda alive,x                  ; Load a value into A
 bne dive_found               ; Branch when zero flag is clear
 inx                          ; Increase X by 1
 cpx #46                      ; Compare X against operand
 bcc dive_search_next         ; Branch when carry is clear
 ldx #0                       ; Load a value into X
dive_search_next:
 dey                          ; Decrease Y by 1
 bne dive_search              ; Branch when zero flag is clear
 jmp enemyfire                ; Jump unconditionally

; ---------------------------------------------------------------------------
; DIVE_FOUND: Remember the selected alien, find its current formation position and initialise its dive.
; ---------------------------------------------------------------------------
dive_found:
 stx divepick                 ; Store X into memory; next candidate index for diving
 stx diveindex                ; Store X into memory; index of the alien selected for a dive
 lda #1                       ; Load a value into A
 sta diveon                   ; Store A into memory; nonzero while a dive is active
 jsr enemycoords              ; Call a subroutine (return address saved on stack)
 lda ex                       ; Load a value into A; calculated alien pixel X low byte
 sta diveorigin               ; Store A into memory; diving alien starting X low byte
 sta divex                    ; Store A into memory; diving alien X low byte
 lda exhi                     ; Load a value into A; calculated alien pixel X high bit
 sta diveoriginhi             ; Store A into memory; diving alien starting X high byte
 sta divexhi                  ; Store A into memory; diving alien ninth X bit
 lda ey                       ; Load a value into A; calculated alien pixel Y
 sta divey                    ; Store A into memory; diving alien Y
 lda #0                       ; Load a value into A
 sta divephase                ; Store A into memory; current position in the 64-step dive curve

; ---------------------------------------------------------------------------
; ENEMYFIRE: Launch a new enemy bullet periodically, using the diving alien position when available.
; ---------------------------------------------------------------------------
enemyfire:
 lda enemyshoton              ; Load a value into A; nonzero while enemy bullet is active
 bne motionend                ; Branch when zero flag is clear
 lda tick                     ; Load a value into A; frame counter used for timing
 and #127                     ; Mask A to keep selected bits
 bne motionend                ; Branch when zero flag is clear
 lda #1                       ; Load a value into A
 sta enemyshoton              ; Store A into memory; nonzero while enemy bullet is active
 lda diveon                   ; Load a value into A; nonzero while a dive is active
 beq fireformation            ; Branch when zero flag is set
 lda divex                    ; Load a value into A; diving alien X low byte
 sta enemyshotx               ; Store A into memory; enemy bullet X low byte
 lda divexhi                  ; Load a value into A; diving alien ninth X bit
 sta enemyshotxhi             ; Store A into memory; enemy bullet ninth X bit
 lda divey                    ; Load a value into A; diving alien Y
 sta enemyshoty               ; Store A into memory; enemy bullet Y position
 rts                          ; Return from subroutine

; ---------------------------------------------------------------------------
; FIREFORMATION: When nothing is diving, launch a bullet from a fixed position near the formation.
; ---------------------------------------------------------------------------
fireformation:
 lda #160                     ; Load a value into A
 sta enemyshotx               ; Store A into memory; enemy bullet X low byte
 lda #0                       ; Load a value into A
 sta enemyshotxhi             ; Store A into memory; enemy bullet ninth X bit
 lda #115                     ; Load a value into A
 sta enemyshoty               ; Store A into memory; enemy bullet Y position
motionend: rts                ; Return from subroutine

; index X -> pixel coordinate of formation character (8-pixel cells)
; 0..9 cyan, 10..19 purple, 20..29 purple, 30..39 red, 40..45 flagship
; formation is drawn at screen columns 5..34; rows 5,7,9,11,13
; each row uses spacing of 3 columns, flagship row starts at column 11
; drift is applied in screen columns via +/- one cell at boundaries

; ---------------------------------------------------------------------------
; COORDS: Convert an alien index (0–45) into its formation row, column and on-screen position.
; ---------------------------------------------------------------------------
coords:
 lda #0                       ; Load a value into A
 sta rownum                   ; Store A into memory; formation row for the current alien
 txa                          ; Copy X into A
co10:
 cmp #10                      ; Compare A against operand
 bcc cofound                  ; Branch when carry is clear
 sec                          ; Set carry before subtraction
 sbc #10                      ; Subtract operand and borrow from A
 inc rownum                   ; Increase memory byte by 1; formation row for the current alien
 cmp #10                      ; Compare A against operand
 bcs co10                     ; Branch when carry is set
cofound:
 sta colnum                   ; Store A into memory; formation column for the current alien
 lda rownum                   ; Load a value into A; formation row for the current alien
 cmp #4                       ; Compare A against operand
 bne coreg                    ; Branch when zero flag is clear
 lda colnum                   ; Load a value into A; formation column for the current alien
 cmp #6                       ; Compare A against operand
 bcc coflag                   ; Branch when carry is clear
coflag:
 lda colnum                   ; Load a value into A; formation column for the current alien
 asl                          ; Shift left one bit
 clc                          ; Clear carry before addition / unsigned comparison
 adc colnum                   ; Add operand and carry to A; formation column for the current alien
 adc #12                      ; Add operand and carry to A
 jmp cocol                    ; Jump unconditionally
coreg:
 lda colnum                   ; Load a value into A; formation column for the current alien
 asl                          ; Shift left one bit
 clc                          ; Clear carry before addition / unsigned comparison
 adc #8                       ; Add operand and carry to A
 clc                          ; Clear carry before addition / unsigned comparison
 adc colnum                   ; Add operand and carry to A; formation column for the current alien
cocol:
 clc                          ; Clear carry before addition / unsigned comparison
 adc drift                    ; Add operand and carry to A; horizontal formation offset
 sta screenx                  ; Store A into memory; alien position in text columns
 lda rownum                   ; Load a value into A; formation row for the current alien
 asl                          ; Shift left one bit
 clc                          ; Clear carry before addition / unsigned comparison
 adc rownum                   ; Add operand and carry to A; formation row for the current alien
 ; row offsets 5,7,9,11,13 (not 3)
 lda rownum                   ; Load a value into A; formation row for the current alien
 asl                          ; Shift left one bit
 clc                          ; Clear carry before addition / unsigned comparison
 adc #5                       ; Add operand and carry to A
 sta screeny                  ; Store A into memory; alien position in text rows
 rts                          ; Return from subroutine

; Screen position pointer for x index; uses multiplication by 40 table

; ---------------------------------------------------------------------------
; SCREENPTR: Compute screen and colour-RAM pointers for an alien tile, including which of the two screen buffers is being drawn.
; ---------------------------------------------------------------------------
screenptr:
 jsr coords                   ; Call a subroutine (return address saved on stack)
 ldy screeny                  ; Load a value into Y; alien position in text rows
 lda rowlow,y                 ; Load a value into A
 clc                          ; Clear carry before addition / unsigned comparison
 adc screenx                  ; Add operand and carry to A; alien position in text columns
 sta ptr                      ; Store A into memory
 lda rowhigh,y                ; Load a value into A
 adc #0                       ; Add operand and carry to A
 sta ptr+1                    ; Store A into memory
 lda drawbank                 ; Load a value into A; which screen is currently being drawn
 beq screenptr_base_done      ; Branch when zero flag is set
 clc                          ; Clear carry before addition / unsigned comparison
 lda ptr+1                    ; Load a value into A
 adc #$34                     ; Add operand and carry to A
 sta ptr+1                    ; Store A into memory
screenptr_base_done:
 rts                          ; Return from subroutine

; Get pixel coordinate from screen coordinates
 enemycoords:
 jsr coords                   ; Call a subroutine (return address saved on stack)
 lda #0                       ; Load a value into A
 sta exhi                     ; Store A into memory; calculated alien pixel X high bit
 lda screenx                  ; Load a value into A; alien position in text columns
 asl                          ; Shift left one bit
 rol exhi                     ; Rotate left through carry; calculated alien pixel X high bit
 asl                          ; Shift left one bit
 rol exhi                     ; Rotate left through carry; calculated alien pixel X high bit
 asl                          ; Shift left one bit
 rol exhi                     ; Rotate left through carry; calculated alien pixel X high bit
 clc                          ; Clear carry before addition / unsigned comparison
 adc #24                      ; Add operand and carry to A
 sta ex                       ; Store A into memory; calculated alien pixel X low byte
 lda exhi                     ; Load a value into A; calculated alien pixel X high bit
 adc #0                       ; Add operand and carry to A
 sta exhi                     ; Store A into memory; calculated alien pixel X high bit
 lda screeny                  ; Load a value into A; alien position in text rows
 asl                          ; Shift left one bit
 asl                          ; Shift left one bit
 asl                          ; Shift left one bit
 clc                          ; Clear carry before addition / unsigned comparison
 adc #50                      ; Add operand and carry to A
 sta ey                       ; Store A into memory; calculated alien pixel Y
 rts                          ; Return from subroutine

; redraw whole playfield formation, avoiding the HUD and ship zone

; ---------------------------------------------------------------------------
; PAINT: Choose whether this frame should redraw the hidden buffer.
; ---------------------------------------------------------------------------
paint:
 lda tick                     ; Load a value into A; frame counter used for timing
 and #1                       ; Mask A to keep selected bits
 beq paint_force              ; Branch when zero flag is set
 jsr sprites                  ; Call a subroutine (return address saved on stack)
 rts                          ; Return from subroutine

; ---------------------------------------------------------------------------
; PAINT_FORCE: Render the hidden screen: clear, paint aliens, HUD, set sprite pointers, then switch visible screen bank.
; ---------------------------------------------------------------------------
paint_force:
 ; Render complete formation into the hidden screen, then flip.
 lda screenbank               ; Load a value into A; which screen is currently visible (double buffering)
 eor #1                       ; Toggle selected bits in A
 sta drawbank                 ; Store A into memory; which screen is currently being drawn
 ; Set base screen high byte: $04 or $38
 lda drawbank                 ; Load a value into A; which screen is currently being drawn
 beq clear_screen_a           ; Branch when zero flag is set
 lda #$38                     ; Load a value into A
 bne clear_screen_set         ; Branch when zero flag is clear

; ---------------------------------------------------------------------------
; CLEAR_SCREEN_A: Set up the correct screen-buffer base address for clearing.
; ---------------------------------------------------------------------------
clear_screen_a:
 lda #$04                     ; Load a value into A
clear_screen_set:
 sta ptr+1                    ; Store A into memory
 lda #0                       ; Load a value into A
 sta ptr                      ; Store A into memory
 ldx #4                       ; Load a value into X

; ---------------------------------------------------------------------------
; CLEAR_SCREEN_PAGES: Clear screen RAM in chunks of 256 bytes, writing blank screen codes.
; ---------------------------------------------------------------------------
clear_screen_pages:
 ldy #0                       ; Load a value into Y
 lda #$20                     ; Load a value into A
clear_screen_bytes:
 sta (ptr),y                  ; Store A into memory
 iny                          ; Increase Y by 1
 bne clear_screen_bytes       ; Branch when zero flag is clear
 inc ptr+1                    ; Increase memory byte by 1
 dex                          ; Decrease X by 1
 bne clear_screen_pages       ; Branch when zero flag is clear
 ; Regenerate HUD in BOTH buffers after clearing the hidden screen.
 ; Copying from $0400 fails whenever $0400 itself was just cleared.
 jsr hud                      ; Call a subroutine (return address saved on stack)
 ldx #0                       ; Load a value into X


; ---------------------------------------------------------------------------
; PAINTALIENS: Loop over all 46 aliens, skipping destroyed ones and the currently diving alien.
; ---------------------------------------------------------------------------
paintaliens:
 lda alive,x                  ; Load a value into A
 bne +                        ; Branch when zero flag is clear
 jmp paintnext                ; Jump unconditionally
+ lda diveon
 beq paintdraw                ; Branch when zero flag is set
 cpx diveindex                ; Compare X against operand; index of the alien selected for a dive
 bne paintdraw                ; Branch when zero flag is clear
 jmp paintnext                ; Jump unconditionally

; ---------------------------------------------------------------------------
; PAINTDRAW: Select the correct custom character tiles and colour for this alien row and animation frame.
; ---------------------------------------------------------------------------
paintdraw:
 jsr coords                   ; Call a subroutine (return address saved on stack)
 lda screenx                  ; Load a value into A; alien position in text columns
 cmp #39                      ; Compare A against operand
 bcc +                        ; Branch when carry is clear
 jmp paintnext                ; Jump unconditionally
+ jsr screenptr
 ldy #0                       ; Load a value into Y
 lda rownum                   ; Load a value into A; formation row for the current alien
 cmp #4                       ; Compare A against operand
 beq flagchar                 ; Branch when zero flag is set
 cmp #3                       ; Compare A against operand
 beq redchar                  ; Branch when zero flag is set
 cmp #0                       ; Compare A against operand
 beq cyanchar                 ; Branch when zero flag is set
 lda #$b0                     ; Load a value into A
 bne putchar                  ; Branch when zero flag is clear
cyanchar:
 lda #$a0                     ; Load a value into A
 bne putchar                  ; Branch when zero flag is clear
redchar:
 lda #$b8                     ; Load a value into A
 bne putchar                  ; Branch when zero flag is clear
flagchar:
 lda #$c0                     ; Load a value into A

; ---------------------------------------------------------------------------
; PUTCHAR: Write an alien tile into screen RAM and its matching colour into colour RAM.
; ---------------------------------------------------------------------------
putchar:
 ; 2x2 character alien, two frames per colour
 pha ; Save A on the stack while temporary calculations use the accumulator.
 lda tick                     ; Load a value into A; frame counter used for timing
 and #8                       ; Mask A to keep selected bits
 beq wingstill                ; Branch when zero flag is set
 pla ; Restore the saved value into A after the temporary calculations.
 clc                          ; Clear carry before addition / unsigned comparison
 adc #$04                     ; Add operand and carry to A
 jmp wingput                  ; Jump unconditionally

; ---------------------------------------------------------------------------
; WINGSTILL: Choose the alternative wing animation frame.
; ---------------------------------------------------------------------------
wingstill:
 pla ; Restore the saved value into A after the temporary calculations.

; ---------------------------------------------------------------------------
; WINGPUT: Place the 2×2-character (16×16-pixel) alien tiles.
; ---------------------------------------------------------------------------
wingput:
 sta tilebase                 ; Store A into memory; first custom character code for current alien artwork
 ldy #0                       ; Load a value into Y
 sta (ptr),y                  ; Store A into memory
 iny                          ; Increase Y by 1
 clc                          ; Clear carry before addition / unsigned comparison
 adc #1                       ; Add operand and carry to A
 sta (ptr),y                  ; Store A into memory
 ; second tile row, pointer += 40
 clc                          ; Clear carry before addition / unsigned comparison
 lda ptr                      ; Load a value into A
 adc #40                      ; Add operand and carry to A
 sta ptr                      ; Store A into memory
 lda ptr+1                    ; Load a value into A
 adc #0                       ; Add operand and carry to A
 sta ptr+1                    ; Store A into memory
 lda tilebase                 ; Load a value into A; first custom character code for current alien artwork
 clc                          ; Clear carry before addition / unsigned comparison
 adc #2                       ; Add operand and carry to A
 ldy #0                       ; Load a value into Y
 sta (ptr),y                  ; Store A into memory
 iny                          ; Increase Y by 1
 clc                          ; Clear carry before addition / unsigned comparison
 adc #1                       ; Add operand and carry to A
 sta (ptr),y                  ; Store A into memory
 ldy screeny                  ; Load a value into Y; alien position in text rows
 lda colorlow,y               ; Load a value into A
 sta cptr                     ; Store A into memory
 lda colorhigh,y              ; Load a value into A
 sta cptr+1                   ; Store A into memory
 ldy screenx                  ; Load a value into Y; alien position in text columns
 txa                          ; Copy X into A
 pha ; Save A on the stack while temporary calculations use the accumulator.
 ldx rownum                   ; Load a value into X; formation row for the current alien
 lda colors,x                 ; Load a value into A
 sta tilecolor                ; Store A into memory; colour RAM value for current alien
 ldy screenx                  ; Load a value into Y; alien position in text columns
 sta (cptr),y                 ; Store A into memory
 iny                          ; Increase Y by 1
 sta (cptr),y                 ; Store A into memory
 ; color second tile row
 clc                          ; Clear carry before addition / unsigned comparison
 lda cptr                     ; Load a value into A
 adc #40                      ; Add operand and carry to A
 sta cptr                     ; Store A into memory
 lda cptr+1                   ; Load a value into A
 adc #0                       ; Add operand and carry to A
 sta cptr+1                   ; Store A into memory
 ldy screenx                  ; Load a value into Y; alien position in text columns
 lda tilecolor                ; Load a value into A; colour RAM value for current alien
 sta (cptr),y                 ; Store A into memory
 iny                          ; Increase Y by 1
 sta (cptr),y                 ; Store A into memory
 pla ; Restore the saved value into A after the temporary calculations.
 tax                          ; Copy A into X
paintnext:
 inx                          ; Increase X by 1
 cpx #46                      ; Compare X against operand
 beq paintdone                ; Branch when zero flag is set
 jmp paintaliens              ; Jump unconditionally

; ---------------------------------------------------------------------------
; PAINTDONE: Finish drawing and swap the screen displayed by the VIC-II.
; ---------------------------------------------------------------------------
paintdone:
 lda drawbank                 ; Load a value into A; which screen is currently being drawn
 sta screenbank               ; Store A into memory; which screen is currently visible (double buffering)
 beq show_a                   ; Branch when zero flag is set
 lda #$e8                     ; Load a value into A
 bne show_set                 ; Branch when zero flag is clear
show_a:
 lda #$18                     ; Load a value into A
show_set:
 pha ; Save A on the stack while temporary calculations use the accumulator.
 ; The hidden screen's $3bf8 sprite pointers were erased by clearing it.
 ; Install pointers BEFORE exposing the buffer to the VIC-II.
 jsr sprites                  ; Call a subroutine (return address saved on stack)
 pla ; Restore the saved value into A after the temporary calculations.
 sta $d018                    ; Store A into memory; screen and character-set base selector
 rts                          ; Return from subroutine


; ---------------------------------------------------------------------------
; HUD_HIDDEN: Draw HUD text and digits into the hidden screen so the display swap does not flicker.
; ---------------------------------------------------------------------------
hud_hidden:
 ldx #0                       ; Load a value into X
hud_hidden_loop:
 lda $0400,x                  ; Load a value into A
 ldy drawbank                 ; Load a value into Y; which screen is currently being drawn
 beq hud_hidden_a             ; Branch when zero flag is set
 sta $3800,x                  ; Store A into memory
 jmp hud_hidden_next          ; Jump unconditionally
hud_hidden_a:
 sta $0400,x                  ; Store A into memory
hud_hidden_next:
 lda #1                       ; Load a value into A
 sta $d800,x                  ; Store A into memory
 inx                          ; Increase X by 1
 cpx #40                      ; Compare X against operand
 bne hud_hidden_loop          ; Branch when zero flag is clear
 rts                          ; Return from subroutine


; ---------------------------------------------------------------------------
; SPRITES: Configure VIC-II hardware sprites: X/Y positions, sprite data pointers, multicolour flags, colours and enable mask.
; ---------------------------------------------------------------------------
sprites:
 lda shipx                    ; Load a value into A; player X position, low 8 bits
 sta $d000                    ; Store A into memory; sprite 0 X (player)
 lda #0                       ; Load a value into A
 sta $d010                    ; Store A into memory; ninth X-position bits for sprites 0–7
 lda shipxhi                  ; Load a value into A; player X position, ninth bit
 beq sprite_x_done            ; Branch when zero flag is set
 lda #1                       ; Load a value into A
 sta $d010                    ; Store A into memory; ninth X-position bits for sprites 0–7
sprite_x_done:
 lda shotxhi                  ; Load a value into A; player laser X high bit
 beq shot_x_done              ; Branch when zero flag is set
 lda $d010                    ; Load a value into A; ninth X-position bits for sprites 0–7
 ora #4                       ; Set selected bits in A
 sta $d010                    ; Store A into memory; ninth X-position bits for sprites 0–7
shot_x_done:
 lda divexhi                  ; Load a value into A; diving alien ninth X bit
 beq dive_x_done              ; Branch when zero flag is set
 lda $d010                    ; Load a value into A; ninth X-position bits for sprites 0–7
 ora #2                       ; Set selected bits in A
 sta $d010                    ; Store A into memory; ninth X-position bits for sprites 0–7
dive_x_done:
 lda enemyshotxhi             ; Load a value into A; enemy bullet ninth X bit
 beq enemy_x_done             ; Branch when zero flag is set
 lda $d010                    ; Load a value into A; ninth X-position bits for sprites 0–7
 ora #8                       ; Set selected bits in A
 sta $d010                    ; Store A into memory; ninth X-position bits for sprites 0–7
enemy_x_done:
 lda #219                     ; Load a value into A
 sta $d001                    ; Store A into memory; sprite 0 Y (player)
 lda divex                    ; Load a value into A; diving alien X low byte
 sta $d002                    ; Store A into memory; sprite 1 X (diver)
 lda divey                    ; Load a value into A; diving alien Y
 sta $d003                    ; Store A into memory; sprite 1 Y (diver)
 lda shotx                    ; Load a value into A; player laser X low byte
 sta $d004                    ; Store A into memory; sprite 2 X (player laser)
 lda shoty                    ; Load a value into A; player laser Y position
 sta $d005                    ; Store A into memory; sprite 2 Y (player laser)
 lda enemyshotx               ; Load a value into A; enemy bullet X low byte
 sta $d006                    ; Store A into memory; sprite 3 X (enemy bullet)
 lda enemyshoty               ; Load a value into A; enemy bullet Y position
 sta $d007                    ; Store A into memory; sprite 3 Y (enemy bullet)
 lda #0                       ; Load a value into A
 sta $d017                    ; no sprite Y expansion | Store A into memory; sprite vertical expansion mask
 sta $d01d                    ; no sprite X expansion | Store A into memory; sprite horizontal expansion mask
 sta $d01b                    ; sprites in front of characters | Store A into memory; sprite priority mask
 lda #$02                     ; Load a value into A
 sta $d01c                    ; diving sprite uses 2-bit multicolour, others stay hires | Store A into memory; sprite multicolour mask
 lda #$01                     ; Load a value into A
 sta $d025                    ; shared white accent (01) | Store A into memory; shared sprite multicolour 1
 lda #$06                     ; Load a value into A
 sta $d026                    ; shared blue outline (10) | Store A into memory; shared sprite multicolour 2
 lda #$c0                     ; Load a value into A
 sta $3bf8                    ; Store A into memory
 sta $07f8                    ; Store A into memory
 ; diving sprite selected by original alien row; clamp inactive index
 ldx diveindex                ; Load a value into X; index of the alien selected for a dive
 cpx #46                      ; Compare X against operand
 bcc dive_index_valid         ; Branch when carry is clear
 ldx #0                       ; Load a value into X

; ---------------------------------------------------------------------------
; DIVE_INDEX_VALID: Look up which sprite artwork matches the selected alien row.
; ---------------------------------------------------------------------------
dive_index_valid:
 jsr coords                   ; Call a subroutine (return address saved on stack)
 lda rownum                   ; Load a value into A; formation row for the current alien
 tax                          ; Copy A into X
 lda diveptrs,x               ; Load a value into A
 sta $3bf9                    ; Store A into memory
 sta $07f9                    ; Store A into memory
 lda #$c7                     ; sprite 2 laser at $31c0 | Load a value into A
 sta $3bfa                    ; Store A into memory
 sta $07fa                    ; Store A into memory
 lda #$c6                     ; Load a value into A
 sta $3bfb                    ; Store A into memory
 sta $07fb                    ; Store A into memory
 ; Dedicated explosion sprites, with pointers in BOTH screen buffers.
 ; Three-frame explosion animations: $c8-$ca alien, $cb-$cd ship.
 lda alienboom                ; Load a value into A; remaining frames in alien explosion animation
 beq alien_frame_end          ; Branch when zero flag is set
 cmp #10                      ; Compare A against operand
 bcs alien_frame_early        ; Branch when carry is set
 cmp #5                       ; Compare A against operand
 bcs alien_frame_middle       ; Branch when carry is set
 lda #$ca                     ; Load a value into A
 bne alien_frame_store        ; Branch when zero flag is clear

; ---------------------------------------------------------------------------
; ALIEN_FRAME_EARLY: Choose first frame of the alien explosion.
; ---------------------------------------------------------------------------
alien_frame_early:
 lda #$c8                     ; Load a value into A
 bne alien_frame_store        ; Branch when zero flag is clear

; ---------------------------------------------------------------------------
; ALIEN_FRAME_MIDDLE: Choose middle frame of the alien explosion.
; ---------------------------------------------------------------------------
alien_frame_middle:
 lda #$c9                     ; Load a value into A

; ---------------------------------------------------------------------------
; ALIEN_FRAME_STORE: Write the alien explosion sprite pointer into both screen buffers.
; ---------------------------------------------------------------------------
alien_frame_store:
 sta $3bfc                    ; Store A into memory
 sta $07fc                    ; Store A into memory
alien_frame_end:
 lda playerboom               ; Load a value into A; remaining frames in player explosion animation
 beq player_frame_end         ; Branch when zero flag is set
 cmp #15                      ; Compare A against operand
 bcs player_frame_early       ; Branch when carry is set
 cmp #8                       ; Compare A against operand
 bcs player_frame_middle      ; Branch when carry is set
 lda #$cd                     ; Load a value into A
 bne player_frame_store       ; Branch when zero flag is clear

; ---------------------------------------------------------------------------
; PLAYER_FRAME_EARLY: Choose first frame of the player explosion.
; ---------------------------------------------------------------------------
player_frame_early:
 lda #$cb                     ; Load a value into A
 bne player_frame_store       ; Branch when zero flag is clear

; ---------------------------------------------------------------------------
; PLAYER_FRAME_MIDDLE: Choose middle frame of the player explosion.
; ---------------------------------------------------------------------------
player_frame_middle:
 lda #$cc                     ; Load a value into A

; ---------------------------------------------------------------------------
; PLAYER_FRAME_STORE: Write the player explosion sprite pointer into both screen buffers.
; ---------------------------------------------------------------------------
player_frame_store:
 sta $3bfd                    ; Store A into memory
 sta $07fd                    ; Store A into memory
player_frame_end:
 lda boomx                    ; Load a value into A; alien explosion X low byte
 sta $d008                    ; Store A into memory; sprite 4 X (alien explosion)
 lda boomy                    ; Load a value into A; alien explosion Y
 sta $d009                    ; Store A into memory; sprite 4 Y (alien explosion)
 ; Place the player explosion four pixels left of the ship X coordinate.
 sec                          ; Set carry before subtraction
 lda shipx                    ; Load a value into A; player X position, low 8 bits
 sbc #4                       ; Subtract operand and borrow from A
 sta $d00a                    ; Store A into memory; sprite 5 X (player explosion)
 lda shipxhi                  ; Load a value into A; player X position, ninth bit
 sbc #0                       ; Subtract operand and borrow from A
 sta playerboomxhi            ; Store A into memory; player explosion X high bit
 lda #221                     ; Load a value into A
 sta $d00b                    ; Store A into memory; sprite 5 Y (player explosion)
 ; Alien sparks alternate yellow/orange; ship flash white/red/yellow.
 lda alienboom                ; Load a value into A; remaining frames in alien explosion animation
 and #$04                     ; Mask A to keep selected bits
 beq alien_spark_yellow       ; Branch when zero flag is set
 lda #8                       ; Load a value into A
 bne alien_spark_color        ; Branch when zero flag is clear
alien_spark_yellow:
 lda #7                       ; Load a value into A

; ---------------------------------------------------------------------------
; ALIEN_SPARK_COLOR: Set the colour of the current alien explosion frame.
; ---------------------------------------------------------------------------
alien_spark_color:
 sta $d02b                    ; Store A into memory
 lda playerboom               ; Load a value into A; remaining frames in player explosion animation
 and #$04                     ; Mask A to keep selected bits
 beq player_spark_white       ; Branch when zero flag is set
 lda #2                       ; Load a value into A
 bne player_spark_color       ; Branch when zero flag is clear
player_spark_white:
 lda #1                       ; Load a value into A

; ---------------------------------------------------------------------------
; PLAYER_SPARK_COLOR: Set the colour of the current player explosion frame.
; ---------------------------------------------------------------------------
player_spark_color:
 sta $d02c                    ; Store A into memory
 ; Sprite 4 and 5 ninth X bits.
 lda boomxhi                  ; Load a value into A; alien explosion X high bit
 beq boom_low_x               ; Branch when zero flag is set
 lda $d010                    ; Load a value into A; ninth X-position bits for sprites 0–7
 ora #$10                     ; Set selected bits in A
 sta $d010                    ; Store A into memory; ninth X-position bits for sprites 0–7

; ---------------------------------------------------------------------------
; BOOM_LOW_X: Set bit 4 of the sprite-X MSB register when the alien explosion crosses pixel 255.
; ---------------------------------------------------------------------------
boom_low_x:
 lda playerboomxhi            ; Load a value into A; player explosion X high bit
 beq player_low_x             ; Branch when zero flag is set
 lda $d010                    ; Load a value into A; ninth X-position bits for sprites 0–7
 ora #$20                     ; Set selected bits in A
 sta $d010                    ; Store A into memory; ninth X-position bits for sprites 0–7

; ---------------------------------------------------------------------------
; PLAYER_LOW_X: Set bit 5 of the sprite-X MSB register when the player explosion crosses pixel 255.
; ---------------------------------------------------------------------------
player_low_x:
 lda #7                       ; Load a value into A
 sta $d027                    ; Store A into memory
 ldx rownum                   ; Load a value into X; formation row for the current alien
 lda divecolors,x             ; Load a value into A
 sta $d028                    ; Store A into memory
 lda #1                       ; Load a value into A
 sta $d029                    ; Store A into memory
 lda #10                      ; Load a value into A
 sta $d02a                    ; Store A into memory
 lda #1                       ; Load a value into A
 sta spritemask               ; Store A into memory; bitmask of enabled hardware sprites
 lda diveon                   ; Load a value into A; nonzero while a dive is active
 beq spn1                     ; Branch when zero flag is set
 lda spritemask               ; Load a value into A; bitmask of enabled hardware sprites
 ora #2                       ; Set selected bits in A
 sta spritemask               ; Store A into memory; bitmask of enabled hardware sprites
spn1:
 ldx shoton                   ; Load a value into X; nonzero while player laser is active
 beq spn2                     ; Branch when zero flag is set
 lda spritemask               ; Load a value into A; bitmask of enabled hardware sprites
 ora #4                       ; Set selected bits in A
 sta spritemask               ; Store A into memory; bitmask of enabled hardware sprites
spn2:
 ldx enemyshoton              ; Load a value into X; nonzero while enemy bullet is active
 beq spn3                     ; Branch when zero flag is set
 lda spritemask               ; Load a value into A; bitmask of enabled hardware sprites
 ora #8                       ; Set selected bits in A
 sta spritemask               ; Store A into memory; bitmask of enabled hardware sprites
spn3:
 lda alienboom                ; Load a value into A; remaining frames in alien explosion animation
 beq no_alien_boom            ; Branch when zero flag is set
 lda spritemask               ; Load a value into A; bitmask of enabled hardware sprites
 ora #$10                     ; Set selected bits in A
 sta spritemask               ; Store A into memory; bitmask of enabled hardware sprites

; ---------------------------------------------------------------------------
; NO_ALIEN_BOOM: Include the alien explosion sprite in the enable mask only while its timer is nonzero.
; ---------------------------------------------------------------------------
no_alien_boom:
 lda playerboom               ; Load a value into A; remaining frames in player explosion animation
 beq no_player_boom           ; Branch when zero flag is set
 lda spritemask               ; Load a value into A; bitmask of enabled hardware sprites
 ora #$20                     ; Set selected bits in A
 sta spritemask               ; Store A into memory; bitmask of enabled hardware sprites

; ---------------------------------------------------------------------------
; NO_PLAYER_BOOM: Include the player explosion sprite in the enable mask only while its timer is nonzero.
; ---------------------------------------------------------------------------
no_player_boom:
 lda spritemask               ; Load a value into A; bitmask of enabled hardware sprites
 sta $d015                    ; Store A into memory; sprite enable bitmask
 rts                          ; Return from subroutine


; ---------------------------------------------------------------------------
; CHECKHITS: Test player laser against diving aliens and formation aliens, then enemy projectiles and ship collisions.
; ---------------------------------------------------------------------------
checkhits:
 lda shoton                   ; Load a value into A; nonzero while player laser is active
 bne checkdiveshot            ; Branch when zero flag is clear
 jmp enemyhitplayer           ; Jump unconditionally

; ---------------------------------------------------------------------------
; CHECKDIVESHOT: Check whether the player laser overlaps the currently diving alien.
; ---------------------------------------------------------------------------
checkdiveshot:
 lda diveon                   ; Load a value into A; nonzero while a dive is active
 beq hitformation             ; Branch when zero flag is set
 ; Bullet graphic is at shotx+11, dive sprite visible from divex+4 to +19.
 clc                          ; Clear carry before addition / unsigned comparison
 lda shotx                    ; Load a value into A; player laser X low byte
 adc #11                      ; Add operand and carry to A
 sta tmpx                     ; Store A into memory
 lda shotxhi                  ; Load a value into A; player laser X high bit
 adc #0                       ; Add operand and carry to A
 sta tmpx+1                   ; Store A into memory
 sec                          ; Set carry before subtraction
 lda tmpx                     ; Load a value into A
 sbc divex                    ; Subtract operand and borrow from A; diving alien X low byte
 sta hitdx                    ; Store A into memory
 lda tmpx+1                   ; Load a value into A
 sbc divexhi                  ; Subtract operand and borrow from A; diving alien ninth X bit
 bne hitformation             ; Branch when zero flag is clear
 lda hitdx                    ; Load a value into A
 cmp #4                       ; Compare A against operand
 bcc hitformation             ; Branch when carry is clear
 cmp #20                      ; Compare A against operand
 bcs hitformation             ; Branch when carry is set
 ; Bullet spans shoty+6 through shoty+18; dive body divey+3..+17.
 lda shoty                    ; Load a value into A; player laser Y position
 clc                          ; Clear carry before addition / unsigned comparison
 adc #18                      ; Add operand and carry to A
 cmp divey                    ; Compare A against operand; diving alien Y
 bcc hitformation             ; Branch when carry is clear
 lda divey                    ; Load a value into A; diving alien Y
 clc                          ; Clear carry before addition / unsigned comparison
 adc #17                      ; Add operand and carry to A
 cmp shoty                    ; Compare A against operand; player laser Y position
 bcc hitformation             ; Branch when carry is clear
 ldx diveindex                ; Load a value into X; index of the alien selected for a dive
 jsr coords                   ; Call a subroutine (return address saved on stack)
 jsr destroy                  ; Call a subroutine (return address saved on stack)
 lda #0                       ; Load a value into A
 sta diveon                   ; Store A into memory; nonzero while a dive is active
 jmp enemyhitplayer           ; Jump unconditionally

; ---------------------------------------------------------------------------
; HITFORMATION: Search the remaining formation aliens for a laser hit.
; ---------------------------------------------------------------------------
hitformation:
 ldx #0                       ; Load a value into X

; ---------------------------------------------------------------------------
; HITLOOP: Iterate through formation slots; skip inactive aliens.
; ---------------------------------------------------------------------------
hitloop:
 lda alive,x                  ; Load a value into A
 beq hitnext                  ; Branch when zero flag is set
 lda diveon                   ; Load a value into A; nonzero while a dive is active
 beq hittry                   ; Branch when zero flag is set
 cpx diveindex                ; Compare X against operand; index of the alien selected for a dive
 beq hitnext                  ; Branch when zero flag is set

; ---------------------------------------------------------------------------
; HITTRY: Compare the laser position against the current alien hit box.
; ---------------------------------------------------------------------------
hittry:
 jsr enemycoords              ; Call a subroutine (return address saved on stack)
 ; Actual projectile centre X is shotx+11 (sprite graphic at bit 11).
 clc                          ; Clear carry before addition / unsigned comparison
 lda shotx                    ; Load a value into A; player laser X low byte
 adc #11                      ; Add operand and carry to A
 sta tmpx                     ; Store A into memory
 lda shotxhi                  ; Load a value into A; player laser X high bit
 adc #0                       ; Add operand and carry to A
 sta tmpx+1                   ; Store A into memory
 sec                          ; Set carry before subtraction
 lda tmpx                     ; Load a value into A
 sbc ex                       ; Subtract operand and borrow from A; calculated alien pixel X low byte
 sta hitdx                    ; Store A into memory
 lda tmpx+1                   ; Load a value into A
 sbc exhi                     ; Subtract operand and borrow from A; calculated alien pixel X high bit
 bne hitnext                  ; Branch when zero flag is clear
 lda hitdx                    ; Load a value into A
 cmp #16                      ; Compare A against operand
 bcs hitnext                  ; Branch when carry is set
 ; Formation enemy is 16 pixels high; bullet's painted pixels y+0..17.
 ; Overlap iff bullet top <= enemy bottom and bullet bottom >= enemy top.
 lda shoty                    ; Load a value into A; player laser Y position
 cmp ey                       ; Compare A against operand; calculated alien pixel Y
 bcc bulletabove              ; Branch when carry is clear
 sec                          ; Set carry before subtraction
 sbc ey                       ; Subtract operand and borrow from A; calculated alien pixel Y
 cmp #16                      ; Compare A against operand
 bcs hitnext                  ; Branch when carry is set
 jmp formhit                  ; Jump unconditionally
bulletabove:
 clc                          ; Clear carry before addition / unsigned comparison
 adc #18                      ; Add operand and carry to A
 cmp ey                       ; Compare A against operand; calculated alien pixel Y
 bcc hitnext                  ; Branch when carry is clear

; ---------------------------------------------------------------------------
; FORMHIT: Apply a successful hit to a formation alien.
; ---------------------------------------------------------------------------
formhit:
 jsr coords                   ; Call a subroutine (return address saved on stack)
 jsr destroy                  ; Call a subroutine (return address saved on stack)
 jmp enemyhitplayer           ; Jump unconditionally
hitnext:
 inx                          ; Increase X by 1
 cpx #46                      ; Compare X against operand
 bne hitloop                  ; Branch when zero flag is clear


; ---------------------------------------------------------------------------
; ENEMYHITPLAYER: Check whether an enemy bullet hits the player ship.
; ---------------------------------------------------------------------------
enemyhitplayer:
 lda enemyshoton              ; Load a value into A; nonzero while enemy bullet is active
 beq divehitplayer            ; Branch when zero flag is set
 lda enemyshoty               ; Load a value into A; enemy bullet Y position
 cmp #205                     ; Compare A against operand
 bcc divehitplayer            ; Branch when carry is clear
 cmp #238                     ; Compare A against operand
 bcs divehitplayer            ; Branch when carry is set
 ; Enemy shot against full 9-bit player X.
 sec                          ; Set carry before subtraction
 lda enemyshotx               ; Load a value into A; enemy bullet X low byte
 sbc shipx                    ; Subtract operand and borrow from A; player X position, low 8 bits
 sta hitdx                    ; Store A into memory
 lda enemyshotxhi             ; Load a value into A; enemy bullet ninth X bit
 sbc shipxhi                  ; Subtract operand and borrow from A; player X position, ninth bit
 bne divehitplayer            ; Branch when zero flag is clear
 lda hitdx                    ; Load a value into A
 cmp #24                      ; Compare A against operand
 bcs divehitplayer            ; Branch when carry is set
 lda #0                       ; Load a value into A
 sta enemyshoton              ; Store A into memory; nonzero while enemy bullet is active
 jsr loselife                 ; Call a subroutine (return address saved on stack)

; ---------------------------------------------------------------------------
; DIVEHITPLAYER: Check whether the diving alien collides with the player.
; ---------------------------------------------------------------------------
divehitplayer:
 lda diveon                   ; Load a value into A; nonzero while a dive is active
 beq hitsdone                 ; Branch when zero flag is set
 lda divey                    ; Load a value into A; diving alien Y
 cmp #199                     ; Compare A against operand
 bcc hitsdone                 ; Branch when carry is clear
 cmp #240                     ; Compare A against operand
 bcs hitsdone                 ; Branch when carry is set
 sec                          ; Set carry before subtraction
 lda divex                    ; Load a value into A; diving alien X low byte
 sbc shipx                    ; Subtract operand and borrow from A; player X position, low 8 bits
 sta hitdx                    ; Store A into memory
 lda divexhi                  ; Load a value into A; diving alien ninth X bit
 sbc shipxhi                  ; Subtract operand and borrow from A; player X position, ninth bit
 bne hitsdone                 ; Branch when zero flag is clear
 lda hitdx                    ; Load a value into A
 cmp #24                      ; Compare A against operand
 bcs hitsdone                 ; Branch when carry is set
 lda #0                       ; Load a value into A
 sta diveon                   ; Store A into memory; nonzero while a dive is active
 jsr loselife                 ; Call a subroutine (return address saved on stack)
hitsdone: rts                 ; Return from subroutine


; ---------------------------------------------------------------------------
; DESTROY: Remove the hit alien, start its explosion, award points and check wave completion.
; ---------------------------------------------------------------------------
destroy:
 ; Save the precise visible location of the alien being hit.
 ; Dive sprite uses divex/divey; formation uses enemycoords.
 lda diveon                   ; Load a value into A; nonzero while a dive is active
 beq boom_formation           ; Branch when zero flag is set
 cpx diveindex                ; Compare X against operand; index of the alien selected for a dive
 bne boom_formation           ; Branch when zero flag is clear
 lda divex                    ; Load a value into A; diving alien X low byte
 sta boomx                    ; Store A into memory; alien explosion X low byte
 lda divexhi                  ; Load a value into A; diving alien ninth X bit
 sta boomxhi                  ; Store A into memory; alien explosion X high bit
 lda divey                    ; Load a value into A; diving alien Y
 sta boomy                    ; Store A into memory; alien explosion Y
 jmp boom_dive_ready          ; Jump unconditionally

; ---------------------------------------------------------------------------
; BOOM_FORMATION: Determine explosion coordinates from the stationary alien’s tile position.
; ---------------------------------------------------------------------------
boom_formation:
 jsr enemycoords              ; Call a subroutine (return address saved on stack)
 lda ex                       ; Load a value into A; calculated alien pixel X low byte
 sta boomx                    ; Store A into memory; alien explosion X low byte
 lda exhi                     ; Load a value into A; calculated alien pixel X high bit
 sta boomxhi                  ; Store A into memory; alien explosion X high bit
 lda ey                       ; Load a value into A; calculated alien pixel Y
 sta boomy                    ; Store A into memory; alien explosion Y

; ---------------------------------------------------------------------------
; BOOM_READY: Apply the alien-explosion position and timer.
; ---------------------------------------------------------------------------
boom_ready:
 ; Offset the formation explosion from the character-based alien position.
 sec                          ; Set carry before subtraction
 lda boomx                    ; Load a value into A; alien explosion X low byte
 sbc #12                      ; Subtract operand and borrow from A
 sta boomx                    ; Store A into memory; alien explosion X low byte
 lda boomxhi                  ; Load a value into A; alien explosion X high bit
 sbc #0                       ; Subtract operand and borrow from A
 sta boomxhi                  ; Store A into memory; alien explosion X high bit

; ---------------------------------------------------------------------------
; BOOM_DIVE_READY: Handle the different coordinate origin of a diving sprite explosion.
; ---------------------------------------------------------------------------
boom_dive_ready:
 ; Align the alien explosion with the formation or diving hit position.
 ; Move up two scanlines to align the explosion's visible centre.
 sec                          ; Set carry before subtraction
 lda boomy                    ; Load a value into A; alien explosion Y
 sbc #2                       ; Subtract operand and borrow from A
 sta boomy                    ; Store A into memory; alien explosion Y
 lda #15                      ; Load a value into A
 sta alienboom                ; Store A into memory; remaining frames in alien explosion animation
 lda #0                       ; Load a value into A
 sta alive,x                  ; Store A into memory
 sta shoton                   ; Store A into memory; nonzero while player laser is active
 dec remaining                ; Decrease memory byte by 1; number of aliens left in this wave
 lda rownum                   ; Load a value into A; formation row for the current alien
 cmp #4                       ; Compare A against operand
 beq points60                 ; Branch when zero flag is set
 cmp #3                       ; Compare A against operand
 beq points50                 ; Branch when zero flag is set
 cmp #0                       ; Compare A against operand
 beq points30                 ; Branch when zero flag is set
 lda #40                      ; Load a value into A
 bne addscore                 ; Branch when zero flag is clear
points60: lda #60             ; Load a value into A
 bne addscore                 ; Branch when zero flag is clear
points50: lda #50             ; Load a value into A
 bne addscore                 ; Branch when zero flag is clear
points30: lda #30             ; Load a value into A

; ---------------------------------------------------------------------------
; ADDSCORE: Add awarded points to the 16-bit score and compare with the stored high score.
; ---------------------------------------------------------------------------
addscore:
 clc                          ; Clear carry before addition / unsigned comparison
 adc scorelo                  ; Add operand and carry to A; low byte of current 16-bit score
 sta scorelo                  ; Store A into memory; low byte of current 16-bit score
 lda scorehi                  ; Load a value into A; high byte of current 16-bit score
 adc #0                       ; Add operand and carry to A
 sta scorehi                  ; Store A into memory; high byte of current 16-bit score
 lda #0                       ; Load a value into A
 sta $d40b                    ; Store A into memory
 lda #$ff                     ; Load a value into A
 sta $d407                    ; Store A into memory
 lda #$1a                     ; Load a value into A
 sta $d408                    ; Store A into memory
 lda #$08                     ; Load a value into A
 sta $d40c                    ; Store A into memory
 lda #$a0                     ; Load a value into A
 sta $d40d                    ; Store A into memory
 lda #$81                     ; Load a value into A
 sta $d40b                    ; Store A into memory
 lda #12                      ; Load a value into A
 sta boomlife                 ; Store A into memory; explosion sound countdown
 ; Preserve the best score between games.
 lda scorehi                  ; Load a value into A; high byte of current 16-bit score
 cmp highhi                   ; Compare A against operand; high byte of session high score
 bcc score_not_record         ; Branch when carry is clear
 bne score_new_record         ; Branch when zero flag is clear
 lda scorelo                  ; Load a value into A; low byte of current 16-bit score
 cmp highlo                   ; Compare A against operand; low byte of session high score
 bcc score_not_record         ; Branch when carry is clear

; ---------------------------------------------------------------------------
; SCORE_NEW_RECORD: Copy the new score into the high-score bytes when the current score exceeds the record.
; ---------------------------------------------------------------------------
score_new_record:
 lda scorelo                  ; Load a value into A; low byte of current 16-bit score
 sta highlo                   ; Store A into memory; low byte of session high score
 lda scorehi                  ; Load a value into A; high byte of current 16-bit score
 sta highhi                   ; Store A into memory; high byte of session high score
score_not_record:
 jsr hud                      ; Call a subroutine (return address saved on stack)
 lda remaining                ; Load a value into A; number of aliens left in this wave
 bne destroyend               ; Branch when zero flag is clear
 jsr newwave                  ; Call a subroutine (return address saved on stack)
destroyend: rts               ; Return from subroutine

; ---------------------------------------------------------------------------
; LOSELIFE: Start player explosion, reduce lives and set game-over state when no lives remain.
; ---------------------------------------------------------------------------
loselife:
 lda #23                      ; Load a value into A
 sta playerboom               ; Store A into memory; remaining frames in player explosion animation
 dec lives                    ; Decrease memory byte by 1; player lives remaining
 bne lifeok                   ; Branch when zero flag is clear
 lda #0                       ; Load a value into A
 sta gamestate                ; Store A into memory; 1 during play, 0 after game over
 rts                          ; Return from subroutine
lifeok:
 lda #0                       ; Load a value into A
 sta shoton                   ; Store A into memory; nonzero while player laser is active
 sta enemyshoton              ; Store A into memory; nonzero while enemy bullet is active
 sta diveon                   ; Store A into memory; nonzero while a dive is active
 jsr hud                      ; Call a subroutine (return address saved on stack)
 rts                          ; Return from subroutine


; ---------------------------------------------------------------------------
; HUD: Prepare the score/lives HUD for display.
; ---------------------------------------------------------------------------
hud:
 ldx #0                       ; Load a value into X
hudloop:
 lda hudtext,x                ; Load a value into A
 beq hudnumbers               ; Branch when zero flag is set
 sta $0400,x                  ; Store A into memory
 sta $3800,x                  ; Store A into memory
 inx                          ; Increase X by 1
 bne hudloop                  ; Branch when zero flag is clear

; ---------------------------------------------------------------------------
; HUDNUMBERS: Convert the score and high score to printable decimal digits.
; ---------------------------------------------------------------------------
hudnumbers:
 lda scorelo                  ; Load a value into A; low byte of current 16-bit score
 sta tmp                      ; Store A into memory
 lda scorehi                  ; Load a value into A; high byte of current 16-bit score
 sta tmp+1                    ; Store A into memory
 jsr convert_digits           ; Call a subroutine (return address saved on stack)
 jsr print_score_digits       ; Call a subroutine (return address saved on stack)
 lda highlo                   ; Load a value into A; low byte of session high score
 sta tmp                      ; Store A into memory
 lda highhi                   ; Load a value into A; high byte of session high score
 sta tmp+1                    ; Store A into memory
 jsr convert_digits           ; Call a subroutine (return address saved on stack)
 jsr print_high_digits        ; Call a subroutine (return address saved on stack)
 lda lives                    ; Load a value into A; player lives remaining
 clc                          ; Clear carry before addition / unsigned comparison
 adc #$30                     ; Add operand and carry to A
 sta $0427                    ; Store A into memory
 sta $3827                    ; Store A into memory
 rts                          ; Return from subroutine

; Input: tmp 16-bit binary. Output: digit0..digit4.

; ---------------------------------------------------------------------------
; CONVERT_DIGITS: Convert a 16-bit unsigned number to decimal using repeated subtraction rather than division.
; ---------------------------------------------------------------------------
convert_digits:
 lda #0                       ; Load a value into A
 sta digit0                   ; Store A into memory; first decimal digit in score conversion
 sta digit1                   ; Store A into memory; second decimal digit in score conversion
 sta digit2                   ; Store A into memory; third decimal digit in score conversion
 sta digit3                   ; Store A into memory; fourth decimal digit in score conversion
 sta digit4                   ; Store A into memory; fifth decimal digit in score conversion
hundred00:
 lda tmp+1                    ; Load a value into A
 cmp #$27                     ; Compare A against operand
 bcc thouscheck               ; Branch when carry is clear
 bne dosub10000               ; Branch when zero flag is clear
 lda tmp                      ; Load a value into A
 cmp #$10                     ; Compare A against operand
 bcc thouscheck               ; Branch when carry is clear
dosub10000:
 sec                          ; Set carry before subtraction
 lda tmp                      ; Load a value into A
 sbc #$10                     ; Subtract operand and borrow from A
 sta tmp                      ; Store A into memory
 lda tmp+1                    ; Load a value into A
 sbc #$27                     ; Subtract operand and borrow from A
 sta tmp+1                    ; Store A into memory
 inc digit0                   ; Increase memory byte by 1; first decimal digit in score conversion
 jmp hundred00                ; Jump unconditionally
thouscheck:
 lda tmp+1                    ; Load a value into A
 cmp #$03                     ; Compare A against operand
 bcc hundredscheck            ; Branch when carry is clear
 bne dosub1000                ; Branch when zero flag is clear
 lda tmp                      ; Load a value into A
 cmp #$e8                     ; Compare A against operand
 bcc hundredscheck            ; Branch when carry is clear
dosub1000:
 sec                          ; Set carry before subtraction
 lda tmp                      ; Load a value into A
 sbc #$e8                     ; Subtract operand and borrow from A
 sta tmp                      ; Store A into memory
 lda tmp+1                    ; Load a value into A
 sbc #$03                     ; Subtract operand and borrow from A
 sta tmp+1                    ; Store A into memory
 inc digit1                   ; Increase memory byte by 1; second decimal digit in score conversion
 jmp thouscheck               ; Jump unconditionally
hundredscheck:
 lda tmp+1                    ; Load a value into A
 bne dosub100                 ; Branch when zero flag is clear
 lda tmp                      ; Load a value into A
 cmp #100                     ; Compare A against operand
 bcc tenscheck                ; Branch when carry is clear
dosub100:
 sec                          ; Set carry before subtraction
 lda tmp                      ; Load a value into A
 sbc #100                     ; Subtract operand and borrow from A
 sta tmp                      ; Store A into memory
 lda tmp+1                    ; Load a value into A
 sbc #0                       ; Subtract operand and borrow from A
 sta tmp+1                    ; Store A into memory
 inc digit2                   ; Increase memory byte by 1; third decimal digit in score conversion
 jmp hundredscheck            ; Jump unconditionally
tenscheck:
 lda tmp                      ; Load a value into A
 cmp #10                      ; Compare A against operand
 bcc unitscheck               ; Branch when carry is clear
 sec                          ; Set carry before subtraction
 sbc #10                      ; Subtract operand and borrow from A
 sta tmp                      ; Store A into memory
 inc digit3                   ; Increase memory byte by 1; fourth decimal digit in score conversion
 jmp tenscheck                ; Jump unconditionally
unitscheck:
 lda tmp                      ; Load a value into A
 sta digit4                   ; Store A into memory; fifth decimal digit in score conversion
 rts                          ; Return from subroutine


; ---------------------------------------------------------------------------
; PRINT_SCORE_DIGITS: Write the five score digits to the appropriate screen addresses.
; ---------------------------------------------------------------------------
print_score_digits:
 lda digit0                   ; Load a value into A; first decimal digit in score conversion
 clc                          ; Clear carry before addition / unsigned comparison
 adc #$30                     ; Add operand and carry to A
 sta $0406                    ; Store A into memory
 sta $3806                    ; Store A into memory
 lda digit1                   ; Load a value into A; second decimal digit in score conversion
 clc                          ; Clear carry before addition / unsigned comparison
 adc #$30                     ; Add operand and carry to A
 sta $0407                    ; Store A into memory
 sta $3807                    ; Store A into memory
 lda digit2                   ; Load a value into A; third decimal digit in score conversion
 clc                          ; Clear carry before addition / unsigned comparison
 adc #$30                     ; Add operand and carry to A
 sta $0408                    ; Store A into memory
 sta $3808                    ; Store A into memory
 lda digit3                   ; Load a value into A; fourth decimal digit in score conversion
 clc                          ; Clear carry before addition / unsigned comparison
 adc #$30                     ; Add operand and carry to A
 sta $0409                    ; Store A into memory
 sta $3809                    ; Store A into memory
 lda digit4                   ; Load a value into A; fifth decimal digit in score conversion
 clc                          ; Clear carry before addition / unsigned comparison
 adc #$30                     ; Add operand and carry to A
 sta $040a                    ; Store A into memory
 sta $380a                    ; Store A into memory
 rts                          ; Return from subroutine


; ---------------------------------------------------------------------------
; PRINT_HIGH_DIGITS: Write the five high-score digits to the appropriate screen addresses.
; ---------------------------------------------------------------------------
print_high_digits:
 lda digit0                   ; Load a value into A; first decimal digit in score conversion
 clc                          ; Clear carry before addition / unsigned comparison
 adc #$30                     ; Add operand and carry to A
 sta $041a                    ; Store A into memory
 sta $381a                    ; Store A into memory
 lda digit1                   ; Load a value into A; second decimal digit in score conversion
 clc                          ; Clear carry before addition / unsigned comparison
 adc #$30                     ; Add operand and carry to A
 sta $041b                    ; Store A into memory
 sta $381b                    ; Store A into memory
 lda digit2                   ; Load a value into A; third decimal digit in score conversion
 clc                          ; Clear carry before addition / unsigned comparison
 adc #$30                     ; Add operand and carry to A
 sta $041c                    ; Store A into memory
 sta $381c                    ; Store A into memory
 lda digit3                   ; Load a value into A; fourth decimal digit in score conversion
 clc                          ; Clear carry before addition / unsigned comparison
 adc #$30                     ; Add operand and carry to A
 sta $041d                    ; Store A into memory
 sta $381d                    ; Store A into memory
 lda digit4                   ; Load a value into A; fifth decimal digit in score conversion
 clc                          ; Clear carry before addition / unsigned comparison
 adc #$30                     ; Add operand and carry to A
 sta $041e                    ; Store A into memory
 sta $381e                    ; Store A into memory
 rts                          ; Return from subroutine


; ---------------------------------------------------------------------------
; EXPLOSION_TICK: Reduce alien and player explosion timers once per frame.
; ---------------------------------------------------------------------------
explosion_tick:
 lda alienboom                ; Load a value into A; remaining frames in alien explosion animation
 beq explosion_player         ; Branch when zero flag is set
 dec alienboom                ; Decrease memory byte by 1; remaining frames in alien explosion animation
explosion_player:
 lda playerboom               ; Load a value into A; remaining frames in player explosion animation
 beq explosion_done           ; Branch when zero flag is set
 dec playerboom               ; Decrease memory byte by 1; remaining frames in player explosion animation
explosion_done:
 rts                          ; Return from subroutine


; ---------------------------------------------------------------------------
; SOUNDTICK: Update SID sound effects and stop voices when their timers expire.
; ---------------------------------------------------------------------------
soundtick:
 lda laserlife                ; Load a value into A; laser sound effect countdown
 beq boomtick                 ; Branch when zero flag is set
 dec laserlife                ; Decrease memory byte by 1; laser sound effect countdown
 bne boomtick                 ; Branch when zero flag is clear
 lda #0                       ; Load a value into A
 sta $d404                    ; Store A into memory
boomtick:
 lda boomlife                 ; Load a value into A; explosion sound countdown
 beq sounddone                ; Branch when zero flag is set
 dec boomlife                 ; Decrease memory byte by 1; explosion sound countdown
 bne sounddone                ; Branch when zero flag is clear
 lda #0                       ; Load a value into A
 sta $d40b                    ; Store A into memory
sounddone: rts                ; Return from subroutine

gameover_text: !byte 7,1,13,5,32,15,22,5,18
!byte 0
title_text: !byte 7,1,12,1,24,9,1,14,32,55,57
!byte 0
prompt_text: !byte 16,18,5,19,19,32,16,32,20,15,32,16,12,1,25
!byte 0
hudtext: !scr "1up   00000   high score  00000  lives  "
!byte 0
colors: !byte 11,12,12,10,15 ; VIC multicolor character flag plus row colour
divecolors: !byte 3,4,4,2,7 ; cyan, purple, purple, red, yellow
rowlow:
!for .i,0,24 { !byte <($0400+.i*40) }
rowhigh:
!for .i,0,24 { !byte >($0400+.i*40) }
colorlow:
!for .i,0,24 { !byte <($d800+.i*40) }
colorhigh:
!for .i,0,24 { !byte >($d800+.i*40) }
; VARIABLE screenbank: which screen is currently visible (double buffering).
screenbank: !byte 0
; VARIABLE drawbank: which screen is currently being drawn.
drawbank: !byte 0
; VARIABLE gamestate: 1 during play, 0 after game over.
gamestate: !byte 0
; VARIABLE shipx: player X position, low 8 bits.
shipx: !byte 0
; VARIABLE shipxhi: player X position, ninth bit.
shipxhi: !byte 0
; VARIABLE shotxhi: player laser X high bit.
shotxhi: !byte 0
; VARIABLE exhi: calculated alien pixel X high bit.
exhi: !byte 0
hitdx: !byte 0
tmpx: !word 0
; VARIABLE divexhi: diving alien ninth X bit.
divexhi: !byte 0
; VARIABLE enemyshotxhi: enemy bullet ninth X bit.
enemyshotxhi: !byte 0
; VARIABLE shotx: player laser X low byte.
shotx: !byte 0
; VARIABLE shoty: player laser Y position.
shoty: !byte 0
; VARIABLE shoton: nonzero while player laser is active.
shoton: !byte 0
; VARIABLE enemyshotx: enemy bullet X low byte.
enemyshotx: !byte 0
; VARIABLE enemyshoty: enemy bullet Y position.
enemyshoty: !byte 0
; VARIABLE enemyshoton: nonzero while enemy bullet is active.
enemyshoton: !byte 0
; VARIABLE divex: diving alien X low byte.
divex: !byte 0
; VARIABLE divey: diving alien Y.
divey: !byte 0
; VARIABLE diveon: nonzero while a dive is active.
diveon: !byte 0
; VARIABLE diveindex: index of the alien selected for a dive.
diveindex: !byte 0
; VARIABLE ex: calculated alien pixel X low byte.
ex: !byte 0
; VARIABLE ey: calculated alien pixel Y.
ey: !byte 0
; VARIABLE screenx: alien position in text columns.
screenx: !byte 0
; VARIABLE screeny: alien position in text rows.
screeny: !byte 0
; VARIABLE rownum: formation row for the current alien.
rownum: !byte 0
; VARIABLE colnum: formation column for the current alien.
colnum: !byte 0
tmp: !word 0
; VARIABLE alive: 46 flags; nonzero means the corresponding alien is alive.
alive: !fill 46,0
; VARIABLE remaining: number of aliens left in this wave.
remaining: !byte 0
; VARIABLE lives: player lives remaining.
lives: !byte 0
; VARIABLE scorelo: low byte of current 16-bit score.
scorelo: !byte 0
; VARIABLE scorehi: high byte of current 16-bit score.
scorehi: !byte 0
; VARIABLE highlo: low byte of session high score.
highlo: !byte 0
; VARIABLE highhi: high byte of session high score.
highhi: !byte 0
; VARIABLE wave: current wave number.
wave: !byte 0
; VARIABLE tick: frame counter used for timing.
tick: !byte 0
; VARIABLE drift: horizontal formation offset.
drift: !byte 0
; VARIABLE dir: formation travel direction.
dir: !byte 0
formationstep: !byte 0
; VARIABLE divephase: current position in the 64-step dive curve.
divephase: !byte 0
; VARIABLE diveorigin: diving alien starting X low byte.
diveorigin: !byte 0
; VARIABLE diveoriginhi: diving alien starting X high byte.
diveoriginhi: !byte 0
; VARIABLE diveoffset: signed horizontal offset from the dive curve.
diveoffset: !byte 0
; VARIABLE divepick: next candidate index for diving.
divepick: !byte 0
; VARIABLE digit0: first decimal digit in score conversion.
digit0: !byte 0
; VARIABLE digit1: second decimal digit in score conversion.
digit1: !byte 0
; VARIABLE digit2: third decimal digit in score conversion.
digit2: !byte 0
; VARIABLE digit3: fourth decimal digit in score conversion.
digit3: !byte 0
; VARIABLE digit4: fifth decimal digit in score conversion.
digit4: !byte 0
; VARIABLE laserlife: laser sound effect countdown.
laserlife: !byte 0
; VARIABLE boomlife: explosion sound countdown.
boomlife: !byte 0
; VARIABLE spritemask: bitmask of enabled hardware sprites.
spritemask: !byte 0
; VARIABLE alienboom: remaining frames in alien explosion animation.
alienboom: !byte 0
; VARIABLE playerboom: remaining frames in player explosion animation.
playerboom: !byte 0
; VARIABLE playerboomxhi: player explosion X high bit.
playerboomxhi: !byte 0
; VARIABLE boomx: alien explosion X low byte.
boomx: !byte 0
; VARIABLE boomxhi: alien explosion X high bit.
boomxhi: !byte 0
; VARIABLE boomy: alien explosion Y.
boomy: !byte 0
; VARIABLE tilebase: first custom character code for current alien artwork.
tilebase: !byte 0
; VARIABLE tilecolor: colour RAM value for current alien.
tilecolor: !byte 0


; Copy C64 character ROM into RAM charset $2000, then replace alien glyphs.
; CPU sees ROM at $d000 while VIC sees RAM at $2000.

; ---------------------------------------------------------------------------
; CHARSET_INIT: Temporarily map the character ROM into CPU memory, copy glyphs to RAM, then copy custom alien characters.
; ---------------------------------------------------------------------------
charset_init:
 lda #$33                     ; Load a value into A
 sta $01                      ; Store A into memory
 ldx #0                       ; Load a value into X

; ---------------------------------------------------------------------------
; CHARSET_COPY: Copy eight 256-byte pages of the character ROM to RAM. The !for directive expands this at assembly time.
; ---------------------------------------------------------------------------
charset_copy:
!for .i,0,7 {
 lda $d000+(.i*256),x         ; Load a value into A; sprite 0 X (player)
 sta $2000+(.i*256),x         ; Store A into memory
 sta $2800+(.i*256),x         ; Store A into memory
}
 inx                          ; Increase X by 1
 bne charset_copy             ; Branch when zero flag is clear
 lda #$37                     ; Load a value into A
 sta $01                      ; Store A into memory
 ldx #0                       ; Load a value into X

; ---------------------------------------------------------------------------
; CUSTOM_COPY: Copy the custom alien glyph bitmap bytes into the selected RAM character set.
; ---------------------------------------------------------------------------
custom_copy:
 lda alienfont,x              ; Load a value into A
 sta $2500,x                  ; Store A into memory
 lda alienfont+$100,x         ; Load a value into A
 sta $2600,x                  ; Store A into memory
 inx                          ; Increase X by 1
 bne custom_copy              ; Branch when zero flag is clear
 rts                          ; Return from subroutine

; Signed-offset table for a looping curved dive, 64 frames.

; ---------------------------------------------------------------------------
; DIVECURVE: A 64-entry table of signed horizontal offsets for a diving alien; $FE means -2, $FC means -4.
; ---------------------------------------------------------------------------
divecurve:
!byte $00,$02,$04,$06,$08,$09,$0b,$0d,$0e,$0f,$11,$12,$12,$13,$14,$14,$14,$14,$14,$13,$12,$12,$11,$0f,$0e,$0d,$0b,$09,$08,$06,$04,$02,$00,$fe,$fc,$fa,$f8,$f7,$f5,$f3,$f2,$f1,$ef,$ee,$ee,$ed,$ec,$ec,$ec,$ec,$ec,$ed,$ee,$ee,$ef,$f1,$f2,$f3,$f5,$f7,$f8,$fa,$fc,$fe

; ---------------------------------------------------------------------------
; ALIENFONT: Raw bitmap data for the custom alien characters. Each character uses 8 bytes (one per pixel row).
; ---------------------------------------------------------------------------
alienfont:
; 40 multicolour character tiles: 5 alien types x 2 wing frames x 4 tiles.
!byte $00,$03,$0b,$2b,$bb,$3d,$2d,$0d,$00,$00,$80,$a0,$b8,$50,$50,$40
!byte $2d,$39,$89,$08,$08,$00,$00,$00,$50,$50,$48,$40,$80,$00,$00,$00
!byte $00,$03,$0b,$0f,$8f,$ed,$3d,$0d,$00,$00,$80,$c0,$c8,$5b,$50,$40
!byte $2d,$39,$89,$08,$08,$00,$00,$00,$50,$50,$48,$40,$80,$00,$00,$00
!byte $00,$02,$03,$0b,$2b,$b9,$3d,$2d,$00,$80,$c0,$e0,$e8,$5e,$5c,$58
!byte $0d,$2d,$31,$01,$08,$00,$00,$00,$50,$58,$4c,$40,$20,$00,$00,$00
!byte $00,$02,$03,$2b,$bb,$3d,$2d,$0d,$00,$80,$c0,$e8,$ee,$5c,$58,$50
!byte $2d,$31,$81,$01,$08,$00,$00,$00,$58,$4c,$42,$40,$20,$00,$00,$00
!byte $00,$02,$03,$0b,$0f,$3d,$bd,$2d,$00,$80,$c0,$e0,$f0,$5c,$5e,$58
!byte $0d,$29,$21,$01,$08,$00,$00,$00,$50,$58,$48,$40,$20,$00,$00,$00
!byte $00,$03,$0b,$2b,$bb,$bd,$2d,$0d,$00,$00,$80,$a0,$b8,$52,$50,$40
!byte $2d,$39,$89,$08,$08,$00,$00,$00,$50,$50,$48,$40,$80,$00,$00,$00
!byte $00,$03,$0b,$0f,$0f,$ad,$3d,$0d,$00,$00,$80,$c0,$c8,$5a,$50,$40
!byte $2d,$39,$89,$08,$08,$00,$00,$00,$50,$50,$48,$40,$80,$00,$00,$00
!byte $00,$02,$03,$0b,$2b,$f9,$3d,$2d,$00,$80,$c0,$e0,$e8,$5f,$5c,$58
!byte $0d,$2d,$31,$01,$08,$00,$00,$00,$50,$58,$4c,$40,$20,$00,$00,$00
!byte $00,$02,$03,$2b,$3b,$3d,$2d,$0d,$00,$80,$c0,$e8,$ec,$5c,$58,$50
!byte $2d,$31,$81,$01,$08,$00,$00,$00,$58,$4c,$42,$40,$20,$00,$00,$00
!byte $00,$02,$03,$0b,$0f,$bd,$bd,$2d,$00,$80,$c0,$e0,$f0,$5e,$5e,$58
!byte $0d,$29,$21,$01,$08,$00,$00,$00,$50,$58,$48,$40,$20,$00,$00,$00
!byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
!byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
!byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
!byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
!byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
!byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
!byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
!byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
!byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
!byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
!byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
!byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00

; ---------------------------------------------------------------------------
; DIVEPTRS: Sprite pointer values for the five alien rows, indexed by row number.
; ---------------------------------------------------------------------------
diveptrs: !byte $c1,$c2,$c3,$c4,$c5

*=$3000
; Eight 64-byte-aligned VIC-II sprites, 21 rows x 3 bytes + pad.
; Sprite 0, pointer $c0
 !byte $00,$00,$00
 !byte $00,$00,$00
 !byte $00,$00,$00
 !byte $00,$00,$00
 !byte $00,$00,$00
 !byte $00,$00,$00
 !byte $01,$80,$00
 !byte $03,$c0,$00
 !byte $07,$e0,$00
 !byte $0f,$f0,$00
 !byte $1f,$f8,$00
 !byte $3f,$fc,$00
 !byte $7f,$fe,$00
 !byte $ff,$ff,$00
 !byte $7f,$fe,$00
 !byte $3f,$fc,$00
 !byte $19,$98,$00
 !byte $31,$8c,$00
 !byte $60,$06,$00
 !byte $00,$00,$00
 !byte $00,$00,$00
 !byte 0
; Sprite 1, pointer $c1
; Multicolour sprite silhouette corresponding to the formation alien
!byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$30,$00,$00
!byte $b8,$00,$02,$ba,$00,$0b,$bb,$80,$03,$d5,$00,$02,$d5,$00,$00,$d4
!byte $00,$02,$d5,$00,$03,$95,$00,$08,$94,$80,$00,$84,$00,$00,$88,$00
!byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
; Sprite 2, pointer $c2
; Multicolour sprite silhouette corresponding to the formation alien
!byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$28,$00,$00
!byte $3c,$00,$00,$be,$00,$02,$be,$80,$0b,$95,$e0,$03,$d5,$c0,$02,$d5
!byte $80,$00,$d5,$00,$02,$d5,$80,$03,$14,$c0,$00,$14,$00,$00,$82,$00
!byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
; Sprite 3, pointer $c3
; Multicolour sprite silhouette corresponding to the formation alien
!byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$28,$00,$00
!byte $3c,$00,$00,$be,$00,$00,$ff,$00,$03,$d5,$c0,$0b,$d5,$e0,$02,$d5
!byte $80,$00,$d5,$00,$02,$95,$80,$02,$14,$80,$00,$14,$00,$00,$82,$00
!byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
; Sprite 4, pointer $c4
; Multicolour sprite silhouette corresponding to the formation alien
!byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$30,$00,$00
!byte $b8,$00,$00,$fc,$00,$00,$fc,$80,$0a,$d5,$a0,$03,$d5,$00,$00,$d4
!byte $00,$02,$d5,$00,$03,$95,$00,$08,$94,$80,$00,$84,$00,$00,$88,$00
!byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
; Sprite 5, pointer $c5
; Multicolour sprite silhouette corresponding to the formation alien
!byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$28,$00,$00
!byte $3c,$00,$02,$be,$80,$03,$be,$c0,$03,$d5,$c0,$02,$d5,$80,$00,$d5
!byte $00,$02,$d5,$80,$03,$14,$c0,$08,$14,$20,$00,$14,$00,$00,$82,$00
!byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
; Sprite 6, pointer $c6
 !byte $00,$00,$00
 !byte $00,$00,$00
 !byte $00,$00,$00
 !byte $00,$00,$00
 !byte $00,$00,$00
 !byte $00,$00,$00
 !byte $01,$80,$00
 !byte $01,$80,$00
 !byte $03,$c0,$00
 !byte $01,$80,$00
 !byte $01,$80,$00
 !byte $00,$00,$00
 !byte $00,$00,$00
 !byte $00,$00,$00
 !byte $00,$00,$00
 !byte $00,$00,$00
 !byte $00,$00,$00
 !byte $00,$00,$00
 !byte $00,$00,$00
 !byte $00,$00,$00
 !byte $00,$00,$00
 !byte 0
; Sprite 7, pointer $c7
 !byte $00,$00,$00
 !byte $00,$00,$00
 !byte $00,$00,$00
 !byte $00,$10,$00
 !byte $00,$10,$00
 !byte $00,$10,$00
 !byte $00,$10,$00
 !byte $00,$10,$00
 !byte $00,$10,$00
 !byte $00,$10,$00
 !byte $00,$10,$00
 !byte $00,$10,$00
 !byte $00,$10,$00
 !byte $00,$10,$00
 !byte $00,$10,$00
 !byte $00,$10,$00
 !byte $00,$00,$00
 !byte $00,$00,$00
 !byte $00,$00,$00
 !byte $00,$00,$00
 !byte $00,$00,$00
 !byte 0

; V23: six independently aligned 64-byte explosion animation frames.
; Alien: $c8,$c9,$ca. Player: $cb,$cc,$cd.
*=$3200
; alien explosion frame 1 (64 bytes)
!byte $00,$00,$00,$00,$00,$00,$00,$00
!byte $00,$00,$00,$00,$00,$00,$00,$00
!byte $00,$00,$00,$08,$00,$00,$2c,$00
!byte $00,$ff,$00,$00,$7e,$00,$00,$ff
!byte $00,$00,$7e,$00,$00,$ff,$00,$00
!byte $2c,$00,$00,$08,$00,$00,$00,$00
!byte $00,$00,$00,$00,$00,$00,$00,$00
!byte $00,$00,$00,$00,$00,$00,$00,$00
; alien explosion frame 2 (64 bytes)
!byte $00,$00,$00,$00,$00,$00,$00,$00
!byte $00,$00,$00,$00,$00,$91,$00,$00
!byte $52,$00,$00,$4a,$00,$03,$00,$c0
!byte $00,$81,$00,$00,$00,$00,$07,$00
!byte $e0,$00,$00,$00,$00,$81,$00,$03
!byte $00,$c0,$00,$4a,$00,$00,$4a,$00
!byte $00,$89,$00,$00,$00,$00,$00,$00
!byte $00,$00,$00,$00,$00,$00,$00,$00
; alien explosion frame 3 (64 bytes)
!byte $00,$10,$00,$02,$10,$80,$01,$10
!byte $80,$01,$00,$80,$00,$00,$00,$18
!byte $00,$18,$04,$00,$20,$00,$00,$00
!byte $00,$00,$00,$00,$00,$00,$28,$00
!byte $0a,$00,$00,$00,$00,$00,$00,$00
!byte $00,$00,$0c,$00,$30,$10,$00,$08
!byte $00,$00,$00,$00,$80,$80,$01,$08
!byte $80,$01,$08,$80,$00,$08,$00,$00
; player explosion frame 1 (64 bytes)
!byte $00,$00,$00,$00,$00,$00,$00,$00
!byte $00,$00,$00,$00,$00,$00,$00,$00
!byte $00,$00,$00,$00,$00,$00,$3c,$00
!byte $00,$7e,$00,$00,$ff,$00,$00,$ff
!byte $00,$00,$ff,$00,$00,$7e,$00,$00
!byte $3c,$00,$00,$00,$00,$00,$00,$00
!byte $00,$00,$00,$00,$00,$00,$00,$00
!byte $00,$00,$00,$00,$00,$00,$00,$00
; player explosion frame 2 (64 bytes)
!byte $00,$00,$00,$00,$06,$00,$01,$ce
!byte $00,$01,$ff,$00,$01,$bb,$78,$01
!byte $93,$f8,$3f,$83,$30,$38,$00,$30
!byte $18,$00,$60,$0e,$00,$78,$0e,$00
!byte $0e,$18,$00,$1e,$38,$00,$f8,$3f
!byte $00,$60,$1f,$00,$60,$03,$23,$70
!byte $03,$77,$f0,$03,$de,$70,$03,$1c
!byte $00,$00,$0c,$00,$00,$00,$00,$00
; player explosion frame 3 (64 bytes)
!byte $0f,$bf,$00,$0f,$f3,$fc,$0c,$61
!byte $fc,$0c,$01,$8c,$1c,$00,$0c,$fc
!byte $00,$0c,$c0,$00,$1c,$80,$00,$1f
!byte $c0,$00,$03,$e0,$00,$01,$70,$00
!byte $01,$70,$00,$03,$e0,$00,$0f,$c0
!byte $00,$0e,$c0,$00,$0c,$fc,$00,$06
!byte $fe,$00,$06,$0e,$00,$fe,$06,$31
!byte $fe,$06,$f9,$80,$07,$df,$80,$00

; ============================================================================
; BITMAP SPLASH SCREEN
; ============================================================================
; The C64 sees screen codes at $8C00 and bitmap bytes at $A000 in VIC bank 2.
; Bitmap pixels use 00=background, 01=screen high nibble, 10=screen low nibble,
; 11=colour RAM. The fixed palette is black, yellow, red and white.
; The CPU can keep BASIC ROM visible while the VIC reads its underlying RAM.
; Load the PRG into RAM before RUN; VICE RAM-injection autostart is suitable.
; attract still polls P. begin_play restores bank 0 and character mode.
!if * > $8000 { !error "Game data overlaps bitmap setup" }
* = $8000
draw_bitmap_splash:
 lda #$0b ; Blank the display while changing its memory layout.
 sta $d011 ; Clear bitmap mode and disable the screen during setup.
 lda #0 ; Use black for the border and disable all hardware sprites.
 sta $d020 ; Black border around the bitmap.
 sta $d015 ; No ship, attacker or explosion appears over the splash.
 lda #1 ; Disable the KERNAL cursor's periodic character/colour writes.
 sta $cc ; P is still read through the KERNAL keyboard routines.
 lda $dd02 ; Read CIA2 port direction without changing unrelated pins.
 ora #3 ; Make both VIC bank-select pins outputs.
 sta $dd02 ; Apply the bank-pin direction bits.
 lda $dd00 ; Read CIA2 output so unrelated serial bits are preserved.
 and #$fc ; Clear the two inverted VIC bank bits.
 ora #1 ; Inverted bank bits 01 select $8000–$BFFF.
 sta $dd00 ; Select VIC bank 2.
 lda #$38 ; Screen offset $0C00 and bitmap offset $2000 within the bank.
 sta $d018 ; Screen at $8C00; bitmap at $A000.
 lda #$18 ; Enable multicolour and retain forty-column width.
 sta $d016 ; Each bitmap pixel is a two-bit, double-width pixel.
 lda #TITLE_BACKGROUND ; The asset declares the background colour number.
 sta $d021 ; Pixel pair 00 uses this global background.
 ldx #0 ; Copy the first 768 per-cell colour values in three pages.
splash_colour_pages:
 !for .p,0,2 {
  lda title_colour_data+.p*256,x ; Read one colour value from the asset.
  sta $d800+.p*256,x ; Write its low nibble to physical colour RAM.
 }
 inx ; Advance within each of the three 256-byte pages.
 bne splash_colour_pages ; X wrapping to zero ends the page copies.
 ldx #0 ; Copy the remaining 232 values to make exactly 1000 cells.
splash_colour_tail:
 lda title_colour_data+768,x ; Read the last partial page.
 sta $db00,x ; Continue at colour RAM offset 768.
 inx ; Advance to the next cell.
 cpx #232 ; The screen contains 40 × 25 = 1000 colour entries.
 bne splash_colour_tail ; Stop before writing beyond the visible screen.
 lda #$3b ; Screen on, bitmap mode on, normal 25-row vertical settings.
 sta $d011 ; Display the completed multicolour bitmap.
 rts ; Return through title_screen to startup and the P-input loop.
restore_character_display:
 lda #$0b ; Blank the screen before switching from bitmap to text.
 sta $d011 ; Disable bitmap mode while the display is off.
 lda $dd00 ; Preserve unrelated CIA2 output bits.
 and #$fc ; Clear VIC bank-select bits.
 ora #3 ; Inverted bits 11 select bank 0, $0000–$3FFF.
 sta $dd00 ; Restore access to the game's screen, font and sprites.
 lda #$1b ; Enable the display with bitmap mode clear.
 sta $d011 ; Gameplay and game-over code choose their own character settings.
 rts ; Continue the caller's normal display initialization.
!if * > $8c00 { !error "Splash setup overlaps the screen matrix" }

; BEGIN TITLE BITMAP ASSET
TITLE_BACKGROUND = 0
; Bitmap-mode screen matrix: high/low nibbles select pixel colours 01/10.
* = $8c00
title_screen_data:
    !byte $72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72
    !byte $72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72
    !byte $72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72
    !byte $72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72
    !byte $72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72
    !byte $72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72
    !byte $72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72
    !byte $72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72
    !byte $72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72
    !byte $72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72
    !byte $72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72
    !byte $72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72
    !byte $72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72
    !byte $72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72
    !byte $72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72
    !byte $72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72
    !byte $72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72
    !byte $72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72
    !byte $72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72
    !byte $72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72
    !byte $72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72
    !byte $72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72
    !byte $72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72
    !byte $72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72
    !byte $72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72
    !byte $72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72
    !byte $72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72
    !byte $72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72
    !byte $72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72
    !byte $72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72
    !byte $72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72,$72
    !byte $72,$72,$72,$72,$72,$72,$72,$72
; Third per-cell colour: copied into physical colour RAM when intro starts.
* = $9000
title_colour_data:
    !byte $01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01
    !byte $01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01
    !byte $01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01
    !byte $01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01
    !byte $01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01
    !byte $01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01
    !byte $01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01
    !byte $01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01
    !byte $01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01
    !byte $01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01
    !byte $01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01
    !byte $01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01
    !byte $01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01
    !byte $01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01
    !byte $01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01
    !byte $01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01
    !byte $01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01
    !byte $01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01
    !byte $01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01
    !byte $01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01
    !byte $01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01
    !byte $01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01
    !byte $01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01
    !byte $01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01
    !byte $01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01
    !byte $01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01
    !byte $01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01
    !byte $01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01
    !byte $01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01
    !byte $01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01
    !byte $01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01
    !byte $01,$01,$01,$01,$01,$01,$01,$01
; 8000 bitmap bytes; VIC bank 2 reads RAM underneath BASIC ROM.
* = $a000
title_bitmap_data:
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$03,$0c,$0c,$0c,$0c,$0c,$03,$00,$f0,$00,$00,$f3,$33,$33,$f3,$00,$f0,$f0,$f0,$0c,$0c,$fc,$0c,$00
    !byte $c0,$c0,$c0,$c0,$c0,$c0,$ff,$00,$0f,$0f,$0f,$30,$30,$3f,$30,$00,$0c,$0c,$03,$c3,$c3,$cc,$cc,$00,$33,$30,$c0,$c0,$c0,$30,$33,$00
    !byte $f0,$c0,$c0,$c0,$c0,$c0,$f0,$00,$3c,$3c,$3c,$c3,$c3,$ff,$c3,$00,$30,$3c,$3c,$33,$33,$33,$30,$00,$c0,$c0,$c0,$c0,$c0,$c0,$c0,$00
    !byte $03,$00,$00,$00,$00,$00,$00,$00,$fc,$0c,$30,$30,$30,$f0,$c0,$00,$3c,$c3,$c3,$ff,$03,$0f,$fc,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$0a,$0a,$2a,$00,$00,$00,$00,$aa,$aa,$aa,$a0
    !byte $00,$00,$00,$00,$a0,$aa,$aa,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$02
    !byte $00,$00,$00,$00,$2a,$aa,$aa,$a0,$00,$00,$00,$00,$a8,$a8,$a8,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$aa,$aa,$aa,$a0,$00,$00,$00,$00,$80,$80,$80,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$0a,$0a,$2a,$2a,$00,$00,$00,$00,$aa,$aa,$aa,$00,$00,$00,$00,$00,$00,$80,$80,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$aa,$aa,$aa,$20,$00,$00,$00,$00,$a0,$a0,$a0,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$2a,$2a,$aa,$a8,$00,$00,$00,$00,$a8,$a8,$a8,$00,$00,$00,$00,$00,$0a,$2a,$2a,$08,$00,$00,$00,$00,$a0,$a8,$a8,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$02,$02,$0a,$00,$00,$00,$00,$aa,$aa,$aa,$80,$00,$00,$00,$00,$a0,$a0,$a0,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$02,$02,$02,$02,$00,$00,$00,$00,$a8,$a8,$a8,$80,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$02,$0a,$0a,$0a,$00,$00,$00,$00,$a8,$a8,$a8,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$02,$02,$02,$0a,$0a,$0a,$aa,$a8,$a0,$a2,$81,$85,$85,$15,$00,$25,$95,$55,$55,$55,$55,$55
    !byte $a8,$55,$55,$55,$55,$55,$55,$55,$00,$80,$50,$58,$54,$55,$55,$55,$00,$00,$00,$00,$00,$00,$00,$80,$02,$02,$02,$0a,$0a,$0a,$0a,$2a
    !byte $a0,$89,$85,$85,$25,$15,$15,$15,$00,$55,$55,$55,$55,$55,$55,$55,$00,$40,$40,$40,$40,$60,$60,$60,$00,$00,$02,$02,$02,$02,$02,$02
    !byte $80,$85,$85,$85,$85,$85,$a5,$15,$00,$54,$54,$54,$54,$54,$54,$54,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$02,$02,$02,$28,$a8,$a2,$a1,$a1,$a1,$85,$85,$00,$55,$55,$55,$55,$55,$55,$55,$00,$50,$54,$54,$54,$54,$54,$54
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$20,$05,$05,$05,$01,$01,$01,$01,$00,$55,$55,$55,$55,$55,$55,$55,$02,$02,$0a,$0a,$8a,$4a,$4a,$48
    !byte $a0,$a1,$81,$85,$05,$15,$15,$95,$00,$55,$55,$55,$55,$55,$56,$54,$08,$48,$42,$41,$01,$21,$21,$21,$00,$55,$55,$55,$55,$55,$55,$55
    !byte $00,$80,$40,$80,$80,$00,$00,$00,$0a,$0a,$0a,$2a,$28,$28,$28,$a8,$80,$25,$15,$15,$95,$55,$55,$55,$00,$55,$55,$55,$55,$55,$55,$55
    !byte $00,$00,$00,$00,$00,$80,$80,$80,$02,$02,$0a,$0a,$0a,$0a,$0a,$08,$00,$15,$15,$15,$15,$15,$95,$55,$00,$40,$40,$60,$50,$50,$50,$58
    !byte $0a,$08,$08,$08,$28,$28,$28,$28,$00,$95,$55,$55,$55,$55,$55,$55,$00,$40,$40,$40,$40,$40,$40,$40,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$0a,$0a,$28,$28,$28,$28,$28,$22,$15,$15,$55,$55,$55,$55,$55,$55,$55,$55,$58,$50,$62,$4a,$4a,$4a
    !byte $55,$a5,$01,$01,$a0,$a8,$a8,$80,$55,$55,$55,$55,$55,$55,$00,$00,$40,$40,$40,$40,$40,$40,$02,$02,$28,$28,$a8,$a2,$a1,$a1,$a1,$89
    !byte $55,$55,$55,$55,$55,$55,$55,$55,$55,$55,$55,$55,$55,$55,$15,$15,$50,$50,$50,$50,$50,$50,$50,$50,$02,$02,$02,$0a,$0a,$0a,$0a,$0a
    !byte $15,$15,$15,$15,$15,$15,$15,$95,$58,$58,$50,$50,$50,$50,$50,$50,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $02,$0a,$0a,$0a,$2a,$28,$28,$28,$85,$05,$15,$15,$15,$95,$55,$55,$55,$55,$55,$55,$55,$55,$59,$59,$54,$54,$54,$54,$54,$56,$56,$55
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$02,$00,$00,$00,$00,$00,$00,$00,$55,$55,$55,$55,$95,$15,$15,$15,$40,$50,$51,$51,$55,$55,$55,$55
    !byte $55,$55,$55,$55,$55,$55,$55,$55,$54,$50,$50,$40,$40,$80,$00,$00,$a1,$a1,$a1,$89,$85,$85,$85,$85,$55,$55,$55,$55,$55,$56,$54,$54
    !byte $00,$00,$02,$02,$02,$02,$0a,$0a,$a1,$a1,$a1,$89,$85,$85,$85,$25,$55,$55,$55,$55,$55,$55,$54,$54,$55,$55,$55,$55,$55,$55,$55,$55
    !byte $40,$40,$40,$40,$40,$40,$40,$40,$08,$08,$08,$28,$28,$28,$28,$2a,$55,$55,$55,$55,$55,$55,$55,$55,$54,$54,$54,$56,$55,$55,$55,$55
    !byte $2a,$21,$21,$21,$21,$21,$21,$81,$55,$55,$55,$55,$55,$55,$55,$55,$40,$40,$80,$80,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$21,$21,$21,$21,$a1,$a1,$a1,$a9,$55,$55,$55,$55,$55,$55,$55,$55,$4a,$88,$08,$08,$08,$00,$00,$00
    !byte $00,$15,$55,$55,$55,$55,$55,$55,$00,$55,$55,$55,$55,$55,$55,$55,$02,$02,$4a,$8a,$8a,$0a,$28,$28,$85,$85,$85,$15,$15,$15,$95,$55
    !byte $55,$56,$54,$54,$54,$58,$52,$52,$15,$15,$15,$15,$15,$15,$25,$a5,$50,$50,$50,$50,$50,$58,$58,$54,$08,$08,$08,$08,$08,$28,$28,$28
    !byte $95,$55,$55,$55,$55,$55,$55,$55,$50,$50,$60,$40,$40,$40,$40,$40,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$02,$02,$02,$0a
    !byte $a8,$a1,$a1,$a1,$89,$85,$85,$85,$55,$55,$55,$55,$55,$55,$55,$56,$41,$41,$41,$81,$21,$21,$21,$21,$55,$55,$55,$55,$55,$55,$55,$55
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$02,$02,$0a,$0a,$2a,$2a,$25,$85,$85,$85,$85,$85,$25,$15,$55,$55,$55,$55,$55,$55,$55,$55
    !byte $54,$54,$50,$50,$40,$40,$40,$40,$02,$02,$02,$02,$02,$02,$02,$02,$85,$85,$85,$85,$a5,$25,$15,$15,$54,$54,$54,$54,$54,$54,$54,$58
    !byte $0a,$0a,$2a,$28,$28,$a8,$a2,$a1,$15,$15,$15,$55,$55,$55,$55,$55,$54,$58,$50,$50,$50,$60,$48,$4a,$55,$55,$55,$55,$55,$55,$95,$95
    !byte $40,$40,$40,$40,$40,$60,$60,$50,$22,$21,$21,$21,$21,$a1,$a1,$a1,$55,$55,$55,$55,$55,$55,$55,$55,$55,$55,$55,$55,$55,$95,$15,$15
    !byte $41,$41,$49,$65,$55,$55,$55,$55,$55,$55,$55,$55,$56,$54,$54,$54,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$89,$05,$05,$05,$05,$05,$09,$01,$55,$55,$55,$55,$55,$55,$55,$55,$00,$00,$00,$08,$2a,$2a,$08,$80
    !byte $55,$55,$09,$05,$85,$85,$25,$15,$55,$55,$55,$55,$56,$54,$54,$54,$28,$28,$21,$21,$21,$a1,$85,$85,$55,$55,$55,$55,$55,$55,$55,$55
    !byte $50,$40,$55,$55,$55,$55,$55,$55,$25,$05,$55,$55,$55,$55,$55,$55,$54,$54,$54,$54,$54,$54,$54,$54,$28,$2a,$21,$21,$21,$21,$21,$a1
    !byte $55,$55,$55,$55,$55,$55,$55,$55,$40,$40,$40,$4a,$aa,$2a,$00,$00,$00,$00,$00,$a8,$a8,$a8,$00,$00,$0a,$0a,$0a,$2a,$28,$28,$28,$02
    !byte $25,$15,$15,$15,$55,$55,$55,$55,$54,$54,$55,$55,$55,$55,$55,$55,$01,$01,$55,$55,$55,$55,$55,$55,$55,$55,$55,$55,$55,$55,$55,$55
    !byte $00,$00,$02,$02,$82,$8a,$4a,$4a,$a8,$a8,$a0,$a1,$81,$85,$85,$25,$15,$55,$55,$55,$55,$55,$55,$55,$55,$55,$55,$55,$55,$55,$55,$15
    !byte $40,$50,$50,$50,$50,$54,$54,$54,$02,$02,$0a,$0a,$0a,$0a,$0a,$08,$15,$15,$15,$15,$15,$15,$95,$55,$50,$52,$52,$52,$52,$52,$52,$52
    !byte $a1,$a1,$85,$85,$85,$85,$15,$15,$55,$55,$55,$55,$55,$55,$55,$55,$40,$00,$55,$55,$55,$55,$55,$55,$95,$15,$55,$55,$55,$55,$55,$55
    !byte $50,$50,$50,$50,$50,$50,$50,$52,$a1,$a9,$85,$85,$85,$85,$85,$85,$55,$55,$55,$56,$56,$54,$54,$54,$15,$25,$05,$05,$05,$01,$01,$01
    !byte $55,$55,$55,$55,$55,$55,$55,$55,$54,$54,$54,$54,$54,$58,$58,$50,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$01,$01,$01,$00,$00,$00,$00,$00,$55,$55,$55,$55,$55,$95,$15,$05,$62,$55,$55,$55,$55,$55,$55,$55
    !byte $55,$55,$55,$55,$55,$55,$55,$54,$54,$52,$52,$62,$40,$80,$00,$00,$85,$25,$15,$15,$15,$55,$55,$55,$55,$55,$55,$54,$50,$50,$50,$50
    !byte $55,$55,$55,$00,$00,$00,$00,$00,$55,$55,$55,$05,$05,$05,$09,$09,$54,$54,$54,$54,$56,$56,$55,$55,$a1,$a1,$a9,$89,$05,$05,$05,$05
    !byte $55,$55,$55,$55,$55,$55,$55,$55,$55,$55,$55,$55,$55,$55,$55,$55,$55,$55,$55,$55,$55,$55,$55,$55,$41,$41,$41,$49,$45,$45,$45,$55
    !byte $55,$55,$55,$55,$55,$55,$54,$54,$55,$55,$55,$00,$00,$00,$00,$00,$55,$55,$55,$00,$00,$00,$00,$00,$55,$55,$55,$55,$55,$55,$55,$55
    !byte $4a,$48,$48,$40,$41,$41,$45,$45,$15,$95,$55,$55,$55,$55,$55,$55,$55,$54,$54,$50,$50,$60,$40,$80,$15,$05,$05,$05,$05,$01,$01,$01
    !byte $54,$55,$55,$55,$55,$55,$55,$55,$08,$08,$08,$08,$00,$40,$40,$42,$55,$55,$55,$55,$55,$55,$55,$55,$62,$48,$48,$48,$40,$41,$41,$41
    !byte $15,$95,$55,$55,$55,$55,$55,$55,$55,$55,$55,$50,$40,$40,$40,$40,$55,$55,$55,$00,$00,$00,$00,$00,$55,$55,$55,$15,$15,$15,$25,$25
    !byte $52,$52,$52,$52,$58,$58,$54,$54,$85,$85,$a5,$25,$15,$15,$15,$15,$54,$54,$54,$54,$54,$58,$50,$50,$01,$00,$00,$00,$00,$00,$00,$00
    !byte $55,$55,$55,$55,$55,$15,$15,$15,$50,$50,$50,$50,$50,$50,$50,$60,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$00,$00,$00,$00,$00,$00,$00,$55,$a8,$00,$00,$00,$00,$00,$00
    !byte $60,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$55,$00,$00,$00,$00,$00,$00,$00,$40,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$01,$00,$00,$00,$00,$00,$00,$00,$56,$00,$00,$00,$00,$00,$00,$00,$05,$00,$00,$00,$00,$00,$00,$00
    !byte $55,$00,$00,$00,$00,$00,$00,$00,$55,$00,$00,$00,$00,$00,$00,$00,$55,$00,$00,$00,$00,$00,$00,$00,$15,$00,$00,$00,$00,$00,$00,$00
    !byte $54,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$55,$00,$00,$00,$00,$00,$00,$00
    !byte $45,$00,$00,$00,$00,$00,$00,$00,$55,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$02,$00,$00,$00,$00,$00,$00,$00
    !byte $55,$00,$00,$00,$00,$00,$00,$00,$40,$00,$00,$00,$00,$00,$00,$00,$55,$00,$00,$00,$00,$00,$00,$00,$81,$00,$00,$00,$00,$00,$00,$00
    !byte $55,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$05,$00,$00,$00,$00,$00,$00,$00
    !byte $58,$00,$00,$00,$00,$00,$00,$00,$15,$00,$00,$00,$00,$00,$00,$00,$50,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $25,$00,$00,$00,$00,$00,$00,$00,$40,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $0a,$2a,$2a,$28,$28,$22,$21,$21,$aa,$aa,$aa,$00,$00,$55,$55,$55,$aa,$aa,$aa,$00,$00,$55,$55,$55,$a0,$a0,$a0,$00,$00,$55,$55,$55
    !byte $02,$0a,$2a,$2a,$2a,$28,$20,$21,$aa,$aa,$aa,$80,$02,$15,$55,$55,$80,$a0,$a8,$00,$a0,$54,$55,$55,$00,$00,$00,$00,$00,$00,$00,$40
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $01,$01,$01,$01,$01,$00,$00,$00,$55,$55,$55,$55,$55,$00,$00,$0a,$55,$55,$55,$55,$55,$05,$25,$15,$55,$55,$55,$56,$54,$54,$54,$50
    !byte $09,$05,$05,$15,$15,$15,$95,$55,$55,$55,$55,$55,$54,$50,$42,$4a,$55,$55,$55,$55,$95,$25,$85,$85,$40,$50,$50,$50,$50,$58,$58,$58
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$02,$2a,$28,$28,$a8,$a8,$a1,$a1,$a1,$15,$15,$55,$55,$55,$55,$55,$55,$50,$50,$40,$40,$40,$00,$00,$00
    !byte $55,$55,$55,$55,$55,$55,$95,$15,$4a,$4a,$4a,$40,$5a,$55,$55,$55,$85,$05,$15,$15,$55,$55,$55,$55,$50,$50,$50,$50,$50,$40,$40,$40
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $02,$02,$0a,$0a,$0a,$2a,$28,$28,$89,$85,$85,$25,$15,$15,$95,$55,$56,$54,$54,$58,$50,$50,$60,$40,$00,$00,$00,$00,$00,$00,$00,$02
    !byte $15,$05,$05,$01,$a0,$a8,$a0,$a1,$55,$55,$55,$55,$55,$55,$55,$55,$55,$55,$54,$54,$50,$50,$60,$40,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $a8,$a0,$01,$01,$01,$05,$05,$00,$55,$55,$55,$55,$55,$54,$54,$00,$40,$40,$00,$00,$00,$00,$00,$00,$02,$02,$00,$00,$00,$00,$00,$00
    !byte $a1,$89,$05,$25,$15,$15,$15,$00,$55,$55,$55,$54,$54,$50,$50,$00,$80,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$03,$03,$00,$00,$30,$30,$f0,$f0,$30,$fc,$30,$00
    !byte $3f,$f0,$c0,$ff,$c3,$c3,$3c,$00,$00,$00,$00,$00,$00,$00,$00,$00,$03,$03,$03,$0c,$0c,$0f,$0c,$00,$c3,$c3,$c3,$33,$33,$f3,$33,$00
    !byte $00,$00,$00,$00,$00,$00,$fc,$00,$fc,$30,$30,$30,$30,$30,$fc,$00,$3f,$30,$30,$3f,$30,$30,$3f,$00,$cc,$0f,$0f,$cc,$0c,$0c,$cc,$00
    !byte $30,$33,$33,$f0,$f0,$f3,$30,$00,$f0,$0c,$00,$fc,$0c,$0c,$f0,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$0f,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$0c,$0c,$0c,$0f,$03,$03,$03,$00,$0c,$0c,$cc,$3c,$30,$30,$30,$00,$3c,$3c,$3c,$c3,$c3,$ff,$c3,$00
    !byte $ff,$0c,$0c,$0c,$0c,$0c,$0c,$00,$c3,$0c,$0c,$0c,$0c,$0c,$03,$00,$f3,$03,$03,$03,$03,$03,$f3,$00,$0c,$0c,$0c,$fc,$0c,$0c,$0c,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$ff,$0c,$0c,$0c,$0c,$0c,$0c,$00,$cc,$0c,$0c,$0f,$0c,$0c,$0c,$00,$33,$33,$33,$f3,$33,$33,$33,$00
    !byte $fc,$00,$00,$fc,$00,$00,$fc,$00,$00,$00,$00,$00,$00,$00,$00,$00,$3f,$30,$30,$30,$30,$30,$3f,$00,$0f,$c3,$c3,$c3,$c3,$c3,$0f,$00
    !byte $c3,$03,$00,$00,$00,$00,$c0,$00,$0c,$0c,$f0,$f0,$f0,$f0,$f0,$00,$ff,$c0,$c0,$ff,$c0,$c0,$ff,$00,$3f,$30,$30,$3f,$33,$30,$30,$00
    !byte $03,$cc,$cc,$03,$c0,$cc,$33,$00,$c0,$30,$00,$f0,$30,$30,$c0,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$03,$00,$fc,$0c,$0c,$0c,$0c,$0c,$fc,$00
    !byte $3c,$c3,$c3,$c3,$c3,$c3,$3c,$00,$c0,$33,$33,$0c,$0c,$0c,$0c,$00,$c3,$0c,$0c,$03,$00,$0c,$03,$00,$cf,$30,$00,$f0,$30,$30,$c0,$00
    !byte $fc,$c0,$c0,$c0,$c0,$c0,$c0,$00,$fc,$30,$30,$30,$30,$30,$fc,$00,$0f,$30,$30,$30,$30,$30,$0f,$00,$cc,$0c,$0f,$0f,$0c,$0c,$cc,$00
    !byte $30,$c0,$00,$00,$c0,$c0,$30,$00,$00,$00,$00,$00,$00,$00,$00,$00,$fc,$c3,$c3,$fc,$c0,$c0,$c0,$00,$0f,$30,$30,$30,$30,$30,$0f,$00
    !byte $0f,$cc,$cc,$cf,$cc,$cc,$0c,$00,$cf,$30,$30,$c0,$f0,$30,$0c,$00,$fc,$c0,$c0,$c0,$c0,$c0,$c0,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $0f,$30,$00,$03,$0f,$3c,$3f,$00,$00,$c0,$c3,$c0,$00,$00,$c3,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $c3,$ff,$ff,$ff,$ff,$c3,$c3,$00,$0f,$30,$30,$30,$30,$30,$0f,$00,$0c,$cc,$c3,$c3,$c3,$c3,$03,$00,$33,$33,$c3,$c3,$c3,$c3,$c3,$00
    !byte $fc,$00,$00,$fc,$00,$00,$fc,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$0c,$0c,$ff,$0c,$0c,$00,$00,$00,$00,$00,$c0,$00,$00,$00
    !byte $03,$03,$03,$03,$03,$03,$03,$00,$fc,$00,$00,$fc,$00,$00,$00,$00,$fc,$30,$30,$30,$30,$30,$fc,$00,$3f,$30,$30,$3f,$33,$30,$30,$00
    !byte $0f,$cc,$cc,$0f,$cc,$cc,$3f,$00,$f0,$00,$00,$f0,$00,$00,$f0,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$fc,$c3,$c3,$fc,$c0,$c0,$c0,$00
    !byte $3f,$30,$30,$3f,$33,$30,$30,$00,$0f,$cc,$cc,$0f,$cc,$cc,$3f,$00,$f0,$03,$03,$f0,$00,$03,$f0,$00,$f0,$0c,$00,$fc,$0c,$0c,$f0,$00
    !byte $3c,$c3,$c0,$3f,$03,$c3,$3c,$00,$00,$00,$00,$00,$00,$00,$00,$00,$0f,$0c,$0c,$0f,$0c,$0c,$0c,$00,$c0,$30,$30,$c0,$00,$00,$00,$00
    !byte $03,$00,$00,$00,$00,$00,$00,$00,$ff,$30,$30,$30,$30,$30,$30,$00,$0f,$30,$30,$30,$30,$30,$0f,$00,$00,$c0,$c0,$c0,$c0,$c0,$00,$00
    !byte $03,$03,$03,$03,$03,$03,$03,$00,$f0,$0c,$0c,$f0,$00,$00,$00,$00,$c0,$c0,$c0,$c0,$c0,$c0,$ff,$00,$0f,$0f,$0f,$30,$30,$3f,$30,$00
    !byte $30,$0c,$0c,$c3,$c3,$c3,$c3,$00,$30,$c0,$c0,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$0f,$30,$30,$30,$30,$30,$0f,$00,$c3,$0f,$0c,$0f,$0c,$0c,$c3,$00,$f0,$00,$00,$f0,$33,$33,$c0,$00
    !byte $30,$30,$f0,$f0,$30,$fc,$30,$00,$00,$00,$00,$00,$00,$00,$00,$00,$3f,$30,$30,$3f,$30,$30,$3f,$00,$0f,$c3,$c3,$03,$c3,$c3,$cf,$00
    !byte $cf,$00,$00,$00,$00,$00,$c0,$00,$fc,$c0,$c0,$c0,$c0,$c0,$c0,$00,$c3,$ff,$ff,$ff,$ff,$c3,$c3,$00,$0f,$0f,$0f,$30,$30,$3f,$30,$00
    !byte $0f,$0c,$0c,$cf,$cc,$cc,$cc,$00,$c0,$30,$30,$c0,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$3c,$c3,$c0,$3f,$03,$c3,$3c,$00
    !byte $3f,$30,$30,$3f,$30,$30,$30,$00,$0c,$cc,$cc,$0c,$0c,$0c,$0f,$00,$00,$00,$00,$03,$03,$03,$f3,$00,$f0,$f0,$f0,$0c,$0c,$fc,$0c,$00
    !byte $3c,$c3,$c0,$3f,$03,$c3,$3c,$00,$30,$30,$30,$3f,$30,$30,$30,$00,$c0,$c0,$c0,$c0,$c0,$c0,$c0,$00,$00,$03,$03,$00,$00,$03,$00,$00
    !byte $f0,$0c,$00,$fc,$0c,$0c,$f0,$00,$3f,$c0,$c0,$c0,$c0,$c0,$3f,$00,$3f,$30,$30,$3f,$33,$30,$30,$00,$0f,$cc,$cc,$0f,$cc,$cc,$3f,$00
    !byte $f3,$03,$03,$f3,$03,$03,$f3,$00,$fc,$00,$00,$fc,$00,$00,$fc,$00,$c3,$f3,$f3,$cf,$cf,$cf,$c3,$00,$00,$00,$00,$00,$00,$00,$00,$00
    !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
!if * != $bf40 { !error "Title bitmap must contain exactly 8000 bytes" }
; END TITLE BITMAP ASSET
