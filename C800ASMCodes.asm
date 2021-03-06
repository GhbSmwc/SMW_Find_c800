;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;Macros
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
function GetC800IndexHorizLvl(RAM13D7, XPos, YPos) = (RAM13D7*(XPos/16))+(YPos*16)+(XPos%16)
function GetC800IndexVertiLvl(XPos, YPos) = (512*(YPos/16))+(256*(XPos/16))+((YPos%16)*16)+(XPos%16)
;Make sure you have [math round on] to prevent unexpected rounded numbers.
;Horizontal level example:
; LDA #$30
; STA.l $7EC800+GetC800IndexHorizLvl($01B0, $01, $01)
; LDA #$01
; STA.l $7FC800+GetC800IndexHorizLvl($01B0, $01, $01)
;Vertical level example:
; LDA #$30
; STA.l $7EC800+GetC800IndexVertiLvl($01, $01)
; LDA #$01
; STA.l $7FC800+GetC800IndexVertiLvl($01, $01)
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;Defines
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
 if !sa1 == 0
  !Scratchram_WriteArrayC800 = $7F844A
 else
  !Scratchram_WriteArrayC800 = $400198
 endif
 ;^[15 bytes] To be used in a routine [Write2DArrayC800]
 ; due to a subroutine used within a subroutine have a conflicting scratch RAM
 ; and was necessary to keep track of the positioning of the tile during a loop.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;Routines
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;Routines include:
;-GetLevelMap16IndexByMap16Position
;-GetMap16PositionByLevelMap16Index
;-MathMul16_16
;-MathDiv
;-Write2DArrayC800
;-WriteHorizLineArrayC800
;-WriteVertiLineArrayC800
;-IndexLevelDimension
;
;This is mainly useful for:
;-Block generation during level load via UberasmTool. For example: remember that a locked gate is unlocked
; stores its block index (2 bytes) instead of coordinates (4 bytes total), which means storing what block
; in the level grid takes halves the space stored in RAM to remember what block in the level.
;-Somewhat an alternative to Akaginite's GetBlock routine, since both search for a block in a level.
; And because layer 2 data format is exactly the same as layer 1, it should be a breeze (take the
; starting address layer 2, and index from there). Not to mention at the time of writing, it hasn't been
; updated to work with LM v3.00
;-Can be used to find a block placed anywhere in the level (such as a mushroom block in block form and not
; sprite, from SMB2) via looping using only the index as a loop count as opposed to using the coordinates,
; which the prior is faster, for example:
;	SearchBlock130:
;	REP #$10
;	LDX #$37FF
;
;	.Loop
;	LDA $7FC800,x		;\Obtain 16-bit map16 block number into A
;	XBA			;|
;	LDA $7EC800,x		;/
;	REP #$20
;	CMP #$0130		;\If the block it is on isn't $0130, check another block (as in, "previous"
;	BNE ..Next		;/since this is a countdown loop)
;
;	..BlockFound
;	STA $00
;	SEP #$20
;	JSL GetMap16PositionByLevelMap16Index
;	BRA .Done
;
;	..Next
;	SEP #$20
;	DEX
;	BPL .Loop
;
;	.Done
;	SEP #$30
;	RTL
;Note that if there are multiple, will choose the last index holding $0130 to obtain the coordinate.

if defined("sa1")
	!sa1 = 0			; SA-1 flag
	!dp = $0000			; Direct Page remap ($0000 - LoROM/FastROM, $3000 - SA-1 ROM)
	!addr = $0000			; Address remap ($0000 - LoROM/FastROM, $6000 - SA-1 ROM)
	!bank = $800000			; Long address remap ($800000 - FastROM, $000000 - SA-1 ROM)
	!bank8 = $80			; Bank byte remap ($80 - FastROM, $00 - SA-1 ROM)

	if read1($00FFD5) == $23	; SA-1 detection code
		sa1rom
		!sa1 = 1		; SA-1 Pack v1.10+ identifier
		!dp = $3000
		!addr = $6000
		!bank = $000000
		!bank8 = $00
	endif
endif

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;Obtain level map16 ($7EC800/$7FC800) indexing via block
;;coordinates.
;;
;;Input:
;; -$00 to $01: X position, in units of full blocks (increments by
;;  one means a full 16x16 block, unlike $9A-$9B, which are pixels).
;; -$02 to $03: Same as above but for Y position
;;Output:
;; -$00-$01: The index of the blocks.
;; -Carry: Set if coordinate points to outside of level.
;;Overwritten:
;  -If SA-1 not applied:
;; --$04 to $0B: copy of $00 due to math routines.
;; -If SA-1 applied:
;; --None overwritten
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;Things to note: A level screen is ALWAYS 16 blocks wide
;(regardless of the level dimension), thus, index can be written
;as in binary as %00YYYYYYYYYYXXXX as an offset from the first
;block of every screen column. The tile data are ordered like
;this:
;1) As the index increases, it goes from left to right within
;   the row of 16 blocks (within a level screen boundary). After
;   the 16th, the next block is wrapped back to the left and on
;   the next row of blocks below. This is known as
;   "Row-Major order".
;2) Once the last block within a screen is reach (bottom right),
;   the next block would be on the screen BELOW the screen the
;   previous block is on (not the next screen), if not, then go
;   to the second column repeating the "downwards, then next column"
;   order. This order is known as "Column-Major order".
;
;Input bit info:
; $00-$01: %0000000XXXXXxxxx (%00000000000Xxxxx for vertical level)
;  Uppercase X: What screen column.
;  Lowercase x: What block within the row of 16 blocks.
; $02-$03: %000000yyyyyyyyyy (%0000000YYYYYyyyy for vertical level)
;  Lowercase y: What row of 16x16 blocks. Note currently
;  as of LM3.03, the highest value for Y (bottommost block) is
;  $037F (%0000001101111111) for horizontal levels, and $01BF
;(%0000000110111111) for vertical levels.
;
;Horizontal level:
; Formula:
;  Index = (BlocksPerScrnCol * floor(XPos/16)) + (YPos*16) + (XPos MOD 16).
;Vertical level:
; Formula:
;  Index = (512 * floor(YPos/16)) + (256 * floor(XPos/16)) + ((YPos MOD 16)*16) + (XPos MOD 16)
;
; Thankfully, each screen is a number power of 2 for the number of blocks per screen: 512 ($0200)
; (which is 2^9), and so does its width and height (2^5 = 32 and 2^4 = 16) which means screen
; unit handling is easier than horizontal levels. The bit format of the index is %YYYYYXyyyyxxxx

GetLevelMap16IndexByMap16Position:
	;Check level format
	LDA $5B
	LSR
	BCS .VerticalLevel
	
	.HorizontalLevel
	;Check if the given position is outside the level.
	REP #$20
	LDA $13D7|!addr				;\Check if Y position is past the bottom of the level.
	LSR #4					;|
	CMP $02					;|
	BEQ .Invalid				;|
	BCC .Invalid				;/
	
	LDA $00					;\Check if X position is past the last screen column of the level
	LSR #4					;|>%0000000XXXXXxxxx -> %00000000000XXXXX
	SEP #$20				;|>%000XXXXX
	CMP $5E					;|>Compare with the last screen number +1
	BCS .Invalid				;/If that or higher, mark as invalid.
	
	;Obtain number of blocks per screen column.
	;Thankfully, $13D7 is also the number of blocks per screen column, because
	;$13D7 is the level height, in unit of pixels, dividing that by 16 ($10,
	;or LSR #4) gives the units in blocks, multiply that by 16 (ASL #4) will
	;give you the number of blocks per screen column. But because you are
	;multiplying by 16 then dividing by 16, this cancel each other out.
	if !sa1 == 0
		REP #$20
		LDA $02				;\Move $02-$03 to $0A-$0B (Y pos)
		STA $0A				;/
		LDA $00				;\Move $00-$01 to $08-$09 (X pos)
		STA $08				;/
		LSR #4				;\what screen column
		STA $00				;/
		LDA $13D7|!addr			;\blocks per screen column
		STA $02				;/
		JSL MathMul16_16		;>$04-$05: Total number of blocks of all screen columns to the left of (exclude at) the coordinate point.
		REP #$20			
		LDA $0A				;\$02-$03 (now $0A-$0B if SA-1): %000000yyyyyyyyyy becomes %00yyyyyyyyyy0000
		ASL #4				;|
		STA $02				;/
		LDA $08				;\(%000000000000xxxx | %00yyyyyyyyyy0000) + (RAM_13D7 * %XXXXX)
		AND.w #%0000000000001111	;|in this order
		ORA $02				;|
		CLC				;|
		ADC $04				;/
	else
		LDA #$00			;\ Multiplication Mode.
		STA $2250			;/

		REP #$20				;
		LDA $00 			;\what screen column
		LSR #4				;|
		STA $2251			;/
		LDA $13D7|!addr			;\Blocks per screen column
		STA $2253			;/
		NOP				;\ ... Wait 5 cycles!
		BRA $00 			;/$2306-$2307: Total number of blocks of all screen columns to the left of (exclude at) the coordinate point.
		
		LDA $02				;\$02-$03: %000000yyyyyyyyyy becomes %00yyyyyyyyyy0000
		ASL #4				;|
		STA $02				;/
		
		LDA $00				;\(%000000000000xxxx | %00yyyyyyyyyy0000) + (RAM_13D7 * %XXXXX)
		AND.w #%0000000000001111	;|in this order
		ORA $02				;|
		CLC				;|
		ADC $2306			;/
	endif
	STA $00					;>Output
	SEP #$20
	CLC
	RTL
	
	.Invalid
	SEP #$21
	RTL
	
	.VerticalLevel
	;$00-$01: %00000000 000Xxxxx
	;$02-$03: %0000000Y YYYYyyyy
	;Rearrange to:
	;$00-$01: %00YYYYYX yyyyxxxx
	
	
	
	;Check if the given position is outside the level.
	REP #$20
	LDA $00					;\(1) X valid ranges from $0000 to $001F
	CMP #$0020				;|
	BCS .Invalid1				;/
	LDA $02					;\Check if Y position is past the last screen of the level
	LSR #4					;|%0000000YYYYYyyyy -> %00000000000YYYYY
	SEP #$20				;|
	CMP $5F					;|>Last screen + 1
	BCS .Invalid1				;/
	
	REP #$20
	LDA $00					;
	AND.w #%0000000000010000		;>(2) what halves of the screen
	ASL #4					;>A: %00000000 000X0000 -> %0000000X 00000000
	ORA $00					;>A: %0000000X 00000000 -> %0000000X 000-xxxx
	AND.w #%0000000100001111		;>A: %0000000X 000-xxxx -> %0000000X 0000xxxx
	STA $00					;>$00 now have all X position bits done.
	
	LDA $02					;>$02: %0000000Y YYYYyyyy
	ASL #4					;>A:   %000YYYYY yyyy0000
	SEP #$20				;>A:   %000YYYYY [yyyy0000]
	ORA $00					;>A:   %yyyy0000 || %0000xxxx -> %yyyyxxxx
	STA $00					;>$00 low bits Y position done.
	REP #$20
	LDA $02					;>$02: %0000000Y YYYYyyyy
	AND.w #%0000000111110000		;>A:   %0000000Y YYYY0000
	ASL #5					;>A:   %00YYYYY0 00000000
	ORA $00					;>A:   %00YYYYY0 00000000 || %0000000X yyyyxxxx
	STA $00					;>$00 is %00YYYYYX yyyyxxxx
	SEP #$20
	CLC
	RTL
	
	.Invalid1
	SEP #$21
	RTL
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;Obtain block coordinate from $7EC800/$7FC800 indexing.
;;
;;Input:
;; -$00 to $01: The index of $7EC800/$7FC800. Index above $37FF is
;;  invalid.
;;Output:
;; -$00 to $01: X position (in units of blocks, each increment
;;  means a full block).
;; -$02 to $03: Y position, same as above but vertical position.
;; -Carry: Set if index is invalid or would be at a location
;;  outside the level boundary.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;Computation as follows:
;Horizontal level:
; XPos = (floor(BlockIndex/BlocksPerScreenCol)*16) + (Index MOD 16)
; YPos = floor((BlockIndex MOD BlocksPerScreenCol)/16)
;
; BlocksPerScreenCol is basically RAM $13D7, it not only holds the
; height of the level in pixels, it also holds the number of
; blocks per screen column.
;Vertical level:
; XPos = (floor((BlockIndex MOD 512)/256)*16) + (BlockIndex MOD 16)
; YPos = (floor(BlockIndex/512)*16) + (floor(BlockIndex/16) MOD 16)
;
; In boolean bitwise operation, you simply rearrange the group
; of bits due to the width and height as well as the number of
; blocks per screen are powers of 2.
GetMap16PositionByLevelMap16Index:
	REP #$20
	LDA $00
	CMP #$3800
	BCS .Invalid
	SEP #$20
	LDA $5B
	LSR
	REP #$20
	BCS .VerticalLevel

	.HorizontalLevel
	if !sa1 == 0
		LDA $13D7|!addr			;\Index divide by number of blocks per screen column
		STA $02				;|
		JSL MathDiv			;/Q ($00-$01) = %00000000000XXXXX, R ($02-$03) = %00yyyyyyyyyyxxxx
		REP #$20			;
		LDA $00				;\$00-$01: %00000000000XXXXX -> %0000000XXXXX0000 (part of converting to X position by convert to block units)
		ASL #4				;|
		STA $00				;/
		LDA $02				;>$02-$03: %00yyyyyyyyyyxxxx
		AND.w #%0000000000001111	;>A: %000000000000xxxx
		ORA $00				;>OR with %0000000XXXXX0000
		STA $00				;>$00-$01:%0000000XXXXXxxxx ((ScreenColumnPassed*16) + XPosWithinCol)
		LDA $02				;\$02-$03: %00yyyyyyyyyyxxxx -> %000000yyyyyyyyyy (divide Y by 16)
		LSR #4				;|
		STA $02				;/
	else
		SEP #$20
		LDA #$01			;\Divide mode
		STA $2250			;/
		REP #$20
		LDA $00				;\Index divide by number of blocks per screen column
		STA $2251			;|
		LDA $13D7|!addr			;|
		STA $2253			;/Q ($2306-$2307) = %00000000000XXXXX, R ($2308-$2309) = %00yyyyyyyyyyxxxx
		NOP				;\Wait 5 cycles.
		BRA $00				;/
		LDA $2308			;\$2308-$2309 is a portion of the screen column (%00yyyyyyyyyyxxxx)
		LSR #4				;|>Divide by 16 (%00yyyyyyyyyyxxxx -> %000000yyyyyyyyyy)
		STA $02				;/
		LDA $2308			;\%00yyyyyyyyyyxxxx -> %000000000000xxxx
		AND.w #%0000000000001111	;|
		STA $00				;/
		LDA $2306			;>$2306-$2307 (quotient) = %00000000000XXXXX
		ASL #4				;>A: %00000000000XXXXX -> %0000000XXXXX0000 ((ScreenColumnPassed*16)...)
		ORA $00				;>A: (... + BlockXPosWithinColumn)
		STA $00				;>(ScreenColumnPassed*16) + BlockXPosWithinColumn (%0000000XXXXX0000 + %00000000000XXXXX)
	endif
	LDA $00					;\Screen column the block coordinate is on
	LSR #4					;/
	SEP #$20
	CMP $5E					;>If past the last screen, mark as invalid.
	BCS .Invalid
	
	.Valid
	CLC				;>Mark that this is a valid coordinate.
	RTL
	
	.Invalid
	SEP #$21
	RTL
;Rearrange this:
; $00-$01: %00YYYYYX yyyyxxxx
;to:
; $00-$01: %00000000 000Xxxxx
; $02-$03: %0000000Y YYYYyyyy
	.VerticalLevel
	LDA $00					;>$00-$01: %00YYYYYX yyyyxxxx
	AND.w #%0000000011110000		;>A:       %00000000 yyyy0000
	LSR #4					;>A:       %00000000 0000yyyy
	STA $02					;>$02-$03: %00000000 0000yyyy
	LDA $00					;>$00-$01: %00YYYYYX yyyyxxxx
	AND.w #%0011111000000000		;>A:       %00YYYYY0 00000000
	LSR #5					;>A:       %0000000Y YYYY0000
	ORA $02					;>A:       %0000000Y YYYYyyyy
	STA $02					;>$02-$03: %0000000Y YYYYyyyy ;>Y pos done.
	LDA $00					;>$00-$01: %00YYYYYX yyyyxxxx ;\Make room to place the high bit X position
	AND.w #%0000000100001111		;>A:       %0000000X 0000xxxx ;|next to the low 4 bits of X position.
	STA $00					;>$00-$01: %0000000X 0000xxxx ;/
	AND.w #%0000000100000000		;>A:       %0000000X 00000000
	LSR #4					;>A:       %00000000 000X0000
	ORA $00					;>A:       %0000000X 000Xxxxx ;>Note the duplicated X position high bit
	AND.w #%0000000000011111		;>A:       %0000000X 000Xxxxx ;>fix the high bit problem.
	STA $00					;>$00-$01: %00000000 000Xxxxx ;>X pos done.
	
	LDA $02
	LSR #4
	SEP #$20
	CMP $5F
	BCS .Invalid
	RTL
if !sa1 == 0
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; 16bit * 16bit unsigned Multiplication
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Argusment
; $00-$01 : Multiplicand
; $02-$03 : Multiplier
; Return values
; $04-$07 : Product
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

MathMul16_16:	REP #$20
		LDY $00
		STY $4202
		LDY $02
		STY $4203
		STZ $06
		LDY $03
		LDA $4216
		STY $4203
		STA $04
		LDA $05
		REP #$11
		ADC $4216
		LDY $01
		STY $4202
		SEP #$10
		CLC
		LDY $03
		ADC $4216
		STY $4203
		STA $05
		LDA $06
		CLC
		ADC $4216
		STA $06
		SEP #$20
		RTL
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; unsigned 16bit / 16bit Division
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Arguments
; $00-$01 : Dividend
; $02-$03 : Divisor
; Return values
; $00-$01 : Quotient
; $02-$03 : Remainder
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

MathDiv:	REP #$20
		ASL $00
		LDY #$0F
		LDA.w #$0000
-		ROL A
		CMP $02
		BCC +
		SBC $02
+		ROL $00
		DEY
		BPL -
		STA $02
		SEP #$20
		RTL
endif
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;Write a 2D array of blocks into $C800 (does not work with layer 2 blocks if layer 2 level).
;
; !Scratchram_WriteArrayC800 usage range: 00 to +14 ($00 to $0E)
;
;Input:
; -!Scratchram_WriteArrayC800+00 to !Scratchram_WriteArrayC800+02: Table location containing low bytes
; -!Scratchram_WriteArrayC800+03 to !Scratchram_WriteArrayC800+05: Table location containing high bytes
; -!Scratchram_WriteArrayC800+06:                                  Number of blocks, minus 1, to transfer the 2D array table.
; -!Scratchram_WriteArrayC800+07:                                  Number of blocks wide, minus 1, to transfer the 2D array table.
; -!Scratchram_WriteArrayC800+08 to !Scratchram_WriteArrayC800+09: Block array X position to place in $C800 table.
; -!Scratchram_WriteArrayC800+10 to !Scratchram_WriteArrayC800+11: Block array Y position to place in $C800 table.
;
;Overwritten:
; -!Scratchram_WriteArrayC800+12:                                  Number of blocks left as the loop processes each line (copied from +07).
; -!Scratchram_WriteArrayC800+13 to !Scratchram_WriteArrayC800+14: X position during a loop, initially copied from (+08)
;
;Example:
; load:
;  LDA.b #Table0     : STA !Scratchram_WriteArrayC800+00	;\Table location
;  LDA.b #Table0>>8  : STA !Scratchram_WriteArrayC800+01	;|
;  LDA.b #Table0>>16 : STA !Scratchram_WriteArrayC800+02	;|
;  LDA.b #Table1     : STA !Scratchram_WriteArrayC800+03	;|
;  LDA.b #Table1>>8  : STA !Scratchram_WriteArrayC800+04	;|
;  LDA.b #Table1>>16 : STA !Scratchram_WriteArrayC800+05	;/
;  
;  LDA.b #(Table0_end-Table0)-1				;\Table size, minus 1
;  STA !Scratchram_WriteArrayC800+06			;/
;  LDA.b #(Table0_endOfRow-Table0)-1			;\How many items in each row, minus 1
;  STA !Scratchram_WriteArrayC800+07			;/
;  
;  REP #$20						;\Position
;  LDA #$001E						;|
;  STA !Scratchram_WriteArrayC800+08			;|
;  LDA #$0010						;|
;  STA !Scratchram_WriteArrayC800+10			;|
;  SEP #$20						;/
;  JSL WriteBlockArrayToC800_WriteArrayC800
;  RTL
;  Table0:
;  db $0000,$0001,$0002               ;>Top row
;  .endOfRow                          ;>This label used for find how many items each row.
;  db $0010,$0011,$0012               ;>Second row
;  db $0020,$0021,$0022               ;>Third row
;  .end
;  Table1:
;  db $0000>>8,$0000>>8,$0000>>8
;  db $0000>>8,$0000>>8,$0000>>8
;  db $0000>>8,$0000>>8,$0000>>8
;  .end
;  ;Protip on creating tables: Just focus on making 4-digit hex numbers table using "db" ($xxxx), make sure all numbers are
;  ;like that, and once you're done, create a copy of that, and add ">>8" so that it will take the upper 8 bits of the map16
;  ;numbers.
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
Write2DArrayC800:
	LDA !Scratchram_WriteArrayC800+7		;\Line counter backup
	STA !Scratchram_WriteArrayC800+12		;/
	REP #$20
	LDA !Scratchram_WriteArrayC800+08		;\Tracking X position
	STA !Scratchram_WriteArrayC800+13		;/
	SEP #$20
	REP #$10					;>16-bit XY (due to X needed to be 16-bit for the C800 indexing)
	LDY #$0000					;>Y = what item in table.
	
	.Loop
	LDA !Scratchram_WriteArrayC800+00 : STA $00	;\Transfer table address to $00 (low byte).
	LDA !Scratchram_WriteArrayC800+01 : STA $01	;|
	LDA !Scratchram_WriteArrayC800+02 : STA $02	;/
	LDA [$00],y					;>Load an item from 2D table
	PHY						;>Push Y, what byte was selected in table
	PHA						;>Push A, what byte value in table.
	REP #$20					;\>16-bit A
	LDA !Scratchram_WriteArrayC800+13		;|Write tile (low byte)
	STA $00						;|
	LDA !Scratchram_WriteArrayC800+10		;|
	STA $02						;|
	SEP #$30					;|>8-bit AXY
	JSL GetLevelMap16IndexByMap16Position		;|
	REP #$10					;|>16-bit XY
	LDX $00						;|>X = block index
	PLA						;|>Restore A, what byte value in table
	BCS +						;|>Failsafe (don't write blocks outside of level)
	if !sa1 == 0
		STA $7EC800,x				;|
	else
		STA $40C800,x				;/
	endif
	LDA !Scratchram_WriteArrayC800+03 : STA $00	;\Transfer table address to $00 (high byte).
	LDA !Scratchram_WriteArrayC800+04 : STA $01	;|
	LDA !Scratchram_WriteArrayC800+05 : STA $02	;/
	+
	PLY						;>Restore Y (what item in table).
	BCS ..Next					;>Failsafe (don't write blocks outside of level)
	LDA [$00],y					;\Write high byte
	if !sa1 == 0
		STA $7FC800,x				;|
	else
		STA $41C800,x				;/
	endif
	
	..Next
	INY
	LDA !Scratchram_WriteArrayC800+12		;\Decrement number of blocks in the current line to process
	SEC						;|
	SBC #$01					;|
	STA !Scratchram_WriteArrayC800+12		;/
	;BPL ...HorizontalLineIncomplete		;>Once 0 -> $FF, newline, otherwise continue on the line.
	BCS ...HorizontalLineIncomplete
	
	...HorizontalLineComplete
	;Next line, go back to the left and down a line
	LDA !Scratchram_WriteArrayC800+07		;\Reset the "line of blocks left"
	STA !Scratchram_WriteArrayC800+12		;/
	REP #$20
	LDA !Scratchram_WriteArrayC800+08		;\Reset X position
	STA !Scratchram_WriteArrayC800+13		;/
	LDA !Scratchram_WriteArrayC800+10		;\Move down a line
	INC						;|
	STA !Scratchram_WriteArrayC800+10		;/
	SEP #$20
	BRA ...NextBlockInTable
	
	...HorizontalLineIncomplete
	;Continue onwards on the line.
	REP #$20
	LDA !Scratchram_WriteArrayC800+13		;\Move over to the right
	INC						;|
	STA !Scratchram_WriteArrayC800+13		;/
	SEP #$20
	
	...NextBlockInTable
	LDA !Scratchram_WriteArrayC800+06		;\Decrease number of blocks left
	SEC						;|
	SBC #$01					;|>Used SEB : SBC instead of BPL/BMI
	STA !Scratchram_WriteArrayC800+06		;/so you can use up to 255 indexes (256-array)
	;BPL .Loop					;>Loop till all blocks in table are all copied.
	BCC +
	JMP .Loop
	+
	RTL
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;Write a horizontal line of blocks into $C800 (does not work with layer 2 blocks if layer 2 level).
;
; !Scratchram_WriteArrayC800 usage range: 00 to +10 ($00 to $0A)
;
; -!Scratchram_WriteArrayC800+00 to !Scratchram_WriteArrayC800+02: Table location containing low bytes
; -!Scratchram_WriteArrayC800+03 to !Scratchram_WriteArrayC800+05: Table location containing high bytes
; -!Scratchram_WriteArrayC800+06:                                  Number of blocks, minus 1.
; -!Scratchram_WriteArrayC800+07 to !Scratchram_WriteArrayC800+08: Block array X position to place in $C800 table.
; -!Scratchram_WriteArrayC800+09 to !Scratchram_WriteArrayC800+10: Block array Y position to place in $C800 table.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
WriteHorizLineArrayC800:
	REP #$10
	LDY #$0000
	
	.Loop
	LDA !Scratchram_WriteArrayC800+00 : STA $00	;\Transfer table address to $00 (low byte).
	LDA !Scratchram_WriteArrayC800+01 : STA $01	;|
	LDA !Scratchram_WriteArrayC800+02 : STA $02	;/
	LDA [$00],y					;>Load an item from 2D table
	PHY						;>Push Y, what byte was selected in table
	PHA						;>Push A, what byte value in table.
	REP #$20					;\>16-bit A
	LDA !Scratchram_WriteArrayC800+07		;|Write tile (low byte)
	STA $00						;|
	LDA !Scratchram_WriteArrayC800+09		;|
	STA $02						;|
	SEP #$30					;|>8-bit AXY
	JSL GetLevelMap16IndexByMap16Position		;|
	REP #$10					;|>16-bit XY
	LDX $00						;|>X = block index
	PLA						;|>Restore A, what byte value in table
	BCS +						;|>Failsafe (don't write blocks outside of level)
	if !sa1 == 0
		STA $7EC800,x				;|
	else
		STA $40C800,x				;/
	endif
	LDA !Scratchram_WriteArrayC800+03 : STA $00	;\Transfer table address to $00 (high byte).
	LDA !Scratchram_WriteArrayC800+04 : STA $01	;|
	LDA !Scratchram_WriteArrayC800+05 : STA $02	;/
	+
	PLY						;>Restore Y (what item in table).
	BCS ..Next					;>Failsafe (don't write blocks outside of level)
	LDA [$00],y					;\Write high byte
	if !sa1 == 0
		STA $7FC800,x				;|
	else
		STA $41C800,x				;/
	endif
	..Next
	INY
	REP #$20
	LDA !Scratchram_WriteArrayC800+07		;\Next block to the right
	INC						;|
	STA !Scratchram_WriteArrayC800+07		;/
	SEP #$20					
	LDA !Scratchram_WriteArrayC800+06		;\Subtract number of blocks
	SEC						;|
	SBC #$01					;|
	STA !Scratchram_WriteArrayC800+06		;/
	BCS .Loop					;>If unsigned underflow ($00->$FF), break loop.
	RTL
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;Write a vertical line of blocks into $C800 (does not work with layer 2 blocks if layer 2 level).
;
; !Scratchram_WriteArrayC800 usage range: 00 to +10 ($00 to $0A)
;
; -!Scratchram_WriteArrayC800+00 to !Scratchram_WriteArrayC800+02: Table location containing low bytes
; -!Scratchram_WriteArrayC800+03 to !Scratchram_WriteArrayC800+05: Table location containing high bytes
; -!Scratchram_WriteArrayC800+06:                                  Number of blocks, minus 1.
; -!Scratchram_WriteArrayC800+07 to !Scratchram_WriteArrayC800+08: Block array X position to place in $C800 table.
; -!Scratchram_WriteArrayC800+09 to !Scratchram_WriteArrayC800+10: Block array Y position to place in $C800 table.
;Same as the horizontal line of blocks.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
WriteVertiLineArrayC800:
	REP #$10
	LDY #$0000
	
	.Loop
	LDA !Scratchram_WriteArrayC800+00 : STA $00	;\Transfer table address to $00 (low byte).
	LDA !Scratchram_WriteArrayC800+01 : STA $01	;|
	LDA !Scratchram_WriteArrayC800+02 : STA $02	;/
	LDA [$00],y					;>Load an item from 2D table
	PHY						;>Push Y, what byte was selected in table
	PHA						;>Push A, what byte value in table.
	REP #$20					;\>16-bit A
	LDA !Scratchram_WriteArrayC800+07		;|Write tile (low byte)
	STA $00						;|
	LDA !Scratchram_WriteArrayC800+09		;|
	STA $02						;|
	SEP #$30					;|>8-bit AXY
	JSL GetLevelMap16IndexByMap16Position		;|
	REP #$10					;|>16-bit XY
	LDX $00						;|>X = block index
	PLA						;|>Restore A, what byte value in table
	BCS +						;|>Failsafe (don't write blocks outside of level)
	if !sa1 == 0
		STA $7EC800,x				;|
	else
		STA $40C800,x				;/
	endif
	LDA !Scratchram_WriteArrayC800+03 : STA $00	;\Transfer table address to $00 (high byte).
	LDA !Scratchram_WriteArrayC800+04 : STA $01	;|
	LDA !Scratchram_WriteArrayC800+05 : STA $02	;/
	+
	PLY						;>Restore Y (what item in table).
	BCS ..Next					;>Failsafe (don't write blocks outside of level)
	LDA [$00],y					;\Write high byte
	if !sa1 == 0
		STA $7FC800,x				;|
	else
		STA $41C800,x				;/
	endif
	..Next
	INY
	REP #$20
	LDA !Scratchram_WriteArrayC800+09		;\Next block downwards
	INC						;|
	STA !Scratchram_WriteArrayC800+09		;/
	SEP #$20					
	LDA !Scratchram_WriteArrayC800+06		;\Subtract number of blocks
	SEC						;|
	SBC #$01					;|
	STA !Scratchram_WriteArrayC800+06		;/
	BCS .Loop					;>If unsigned underflow ($00->$FF), break loop.
	RTL
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;Index what horizontal level dimension currently set by LM that the
;;player is in.
;;
;;Output:
;; X (8-bit) = The index number, times 2 (Index = $01 means X = $02).
;;             corresponding to what setting in LM's
;;             "Change Properties in Header" -> "Horizontal Level mode"'s
;;             drop-down box. Some examples:
;;
;;             $00 = LVL height = 01B tiles, H-Screens=20 -> X = $00
;;             $01 = LVL height = 01C tiles, H-Screens=20 -> X = $02
;;             $02 = LVL height = 01D tiles, H-Screens=1E -> X = $04
;;             ...
;;             Returns $FE should no setting be found (can be used as
;;             a failsafe detection for invalid level dimension).
;;
;;Protip: If you are searching where the layer 2 data starts at,
;;Cheatsheet provided (example):
;; FindLayer2Data:
;;  ;Y = What index from the top-left starting block.
;;  JSL IndexLevelDimension
;;  CPX #$38                      ;\Setting $1C is 1 screen wide, and a layer 2 level of that
;;  BCS .Invalid                  ;/is a black screen in LM.
;;  REP #$20
;;  LDA Layer2DataStartTable,x    ;\$00 = the starting location of layer 2.
;;  STA $00                       ;/
;;  SEP #$20
;;  if !sa1 == 0
;;   LDA $7E : STA $02
;;  else
;;   LDA $40 : STA $02
;;  endif
;;  LDA [$00],y  ;>Note that there is no [$xx],x, only [$xx,x]. A now contains the low byte.
;;  ;[...]       ;>Do stuff involving low byte
;;  INC $02      ;>switch to high byte
;;  LDA [$00]    ;>A now contains the high byte
;;  ;[...]       ;>Do stuff involving high byte
;;  .Invalid
;;  RTL
;;  Layer2DataStartTable:
;;  dw $E300  ;>Setting $00 (Index value: $00)
;;  dw $E400  ;>Setting $01 (Index value: $02)
;;  dw $E330  ;>Setting $02 (Index value: $04)
;;  dw $E400  ;>Setting $03 (Index value: $06)
;;  dw $E3A0  ;>Setting $04 (Index value: $08)
;;  dw $E3C0  ;>Setting $05 (Index value: $0A)
;;  dw $E480  ;>Setting $06 (Index value: $0C)
;;  dw $E380  ;>Setting $07 (Index value: $0E)
;;  dw $E4E0  ;>Setting $08 (Index value: $10)
;;  dw $E380  ;>Setting $09 (Index value: $12)
;;  dw $E560  ;>Setting $0A (Index value: $14)
;;  dw $E390  ;>Setting $0B (Index value: $16)
;;  dw $E540  ;>Setting $0C (Index value: $18)
;;  dw $E400  ;>Setting $0D (Index value: $1A)
;;  dw $E580  ;>Setting $0E (Index value: $1C)
;;  dw $E400  ;>Setting $0F (Index value: $1E)
;;  dw $E5C0  ;>Setting $10 (Index value: $20)
;;  dw $E3C0  ;>Setting $11 (Index value: $22)
;;  dw $E660  ;>Setting $12 (Index value: $24)
;;  dw $E3D0  ;>Setting $13 (Index value: $26)
;;  dw $E6F0  ;>Setting $14 (Index value: $28)
;;  dw $E400  ;>Setting $15 (Index value: $2A)
;;  dw $E800  ;>Setting $16 (Index value: $2C)
;;  dw $E3F0  ;>Setting $17 (Index value: $2E)
;;  dw $E990  ;>Setting $18 (Index value: $30)
;;  dw $E400  ;>Setting $19 (Index value: $32)
;;  dw $ED40  ;>Setting $1A (Index value: $34)
;;  dw $E400  ;>Setting $1B (Index value: $36)
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
	IndexLevelDimension:
	REP #$20
	LDX.b #(LevelDimensionHeightsEnd-LevelDimensionHeights)-2	;>Start at last item.
	
	.Loop
	LDA $13D7|!addr			;>Current level height
	CMP LevelDimensionHeights,x
	BEQ .HeightFound
	
	..Next
	DEX #2
	BPL .Loop
	
	.HeightFound
	SEP #$20
	RTL
	
	LevelDimensionHeights:
	dw $01B0		;>Setting $00 (index = $00)
	dw $01C0		;>Setting $01 (index = $02)
	dw $01D0		;>Setting $02 (index = $04)
	dw $0200		;>Setting $03 (index = $06)
	dw $0220		;>Setting $04 (index = $08)
	dw $0250		;>Setting $05 (index = $0A)
	dw $0260		;>Setting $06 (index = $0C)
	dw $0280		;>Setting $07 (index = $0E)
	dw $02A0		;>Setting $08 (index = $10)
	dw $02C0		;>Setting $09 (index = $12)
	dw $02F0		;>Setting $0A (index = $14)
	dw $0310		;>Setting $0B (index = $16)
	dw $0340		;>Setting $0C (index = $18)
	dw $0380		;>Setting $0D (index = $1A)
	dw $03B0		;>Setting $0E (index = $1C)
	dw $0400		;>Setting $0F (index = $1E)
	dw $0440		;>Setting $10 (index = $20)
	dw $04A0		;>Setting $11 (index = $22)
	dw $0510		;>Setting $12 (index = $24)
	dw $0590		;>Setting $13 (index = $26)
	dw $0630		;>Setting $14 (index = $28)
	dw $0700		;>Setting $15 (index = $2A)
	dw $0800		;>Setting $16 (index = $2C)
	dw $0950		;>Setting $17 (index = $2E)
	dw $0B30		;>Setting $18 (index = $30)
	dw $0E00		;>Setting $19 (index = $32)
	dw $12A0		;>Setting $1A (index = $34)
	dw $1C00		;>Setting $1B (index = $36)
	dw $3800		;>Setting $1C (index = $38)
	LevelDimensionHeightsEnd: