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
;;Index what horizontal level dimension currently set by LM that the
;;player is in.
;;
;;Output:
;; X (8-bit) = The index number (increments of 2 for every item setting),
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
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;Obtain level map16 ($7EC800/$7FC800) indexing via block
;;coordinates.
;;
;;Input:
;; -$00 to $01: X position, in units of blocks
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
;  Index = (RAM_13D7 * %XXXXX) + (%00yyyyyyyyyy0000 || %000000000000xxxx)
;  In formal writing:
;   Index = (BlocksPerScrnCol * floor(XPos/16)) + (YPos*16) + (XPos MOD 16)
;Vertical level:
; Formula:
;  Index = ($0200 * %YYYYY) + (%X00000000 && $0100) + (%yyyy << 4) + (%xxxx)
;  In formal writing:
;   Index = 512 * floor(YPos/16) + (256 * floor(XPos/16)) + ((YPos MOD 16)*16) + (XPos MOD 16)
;
; || = OR boolean operation
; && = AND boolean operation
; << = leftshift boolean operation (<< 4 means shift bits left 4 times)

GetLevelMap16IndexByMap16Position:
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
	SEP #$20
	SEC
	RTL
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;Obtain block coordinate from $7EC800/$7FC800 indexing.
;;
;;Input:
;; -$00 to $01: The index of $7EC800/$7FC800. Index above $37FF is
;;  invalid.
;;Output:
;; -$00 to $01: X position (in units of blocks).
;; -$02 to $03: Y position, same as above.
;; -Carry: Set if index is invalid.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;Computation as follows:
;ScreenColumnPassed = floor(Index/RAM_13D7)			;>Number of screen column passed (%00000000000XXXXX)
;PartialScreenColumn = Index MOD RAM_13D7			;>the screen column after the last screen column passed (%00yyyyyyyyyyxxxx)
;BlockYPos = floor(PartialScreenColumn/16)			;>Y position (%00yyyyyyyyyyxxxx -> %000000yyyyyyyyyy)
;BlockXPosWithinColumn = (PartialScreenColumn Mod 16)		;>X position within a screen column (%00yyyyyyyyyyxxxx -> %000000000000xxxx)
;BlockXPos = (ScreenColumnPassed*16) + BlockXPosWithinColumn	;>X Position (%0000000XXXXXxxxx)
GetMap16PositionByLevelMap16Index:
	REP #$20
	LDA $00
	CMP #$3800
	BCS .Invalid
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
	SEP #$20
	CLC				;>Mark that this is a valid coordinate.
	RTL
	
	.Invalid
	SEP #$20
	SEC
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