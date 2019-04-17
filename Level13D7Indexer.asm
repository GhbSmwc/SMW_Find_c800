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
;; $00-$01: X position, in units of blocks
;; $02-$03: Same as above but for Y position
;;Output:
;; A (16-bit): The index of the blocks.
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
; $00-$01: %0000000XXXXXxxxx
;  Uppercase X: What screen column.
;  Lowercase x: What block within the row of 16 blocks.
; $02-$03: %000000yyyyyyyyyy
;  Lowercase y: What row of 16x16 blocks. Note currently
;  as of LM3.03, the highest value for Y (bottomost block) is
;  $037F (%0000001101111111).
;
;
;Formula:
; Index = (RAM_13D7 * %XXXXX) + %00yyyyyyyyyy0000 + %000000000000xxxx
;

GetLevelMap16IndexByPosition:
	;Check if the given position is outside the level.
	
	;Obtain number of blocks per screen column.
	;Thankfully, $13D7 is also the number of blocks per screen column, because
	;$13D7 is the level height, in unit of pixels, dividing that by 16 ($10,
	;or LSR #4) gives the units in blocks, multiply that by 16 (ASL #4) will
	;give you the number of blocks per screen column. But because you are
	;multiplying by 16 then dividing by 16, this cancel each other out.
	LDA $13D7|!addr