*-----------------------------------------------------------
* Title      : LisaMandelbrot Solo
* Written by : Tom Stepleton
* Date       : 22 November 2017
* Description:
*   A standalone "bare metal" assembly program that plots
*   the Mandelbrot set on a Lisa's display. Once it
*   finishes plotting the set the first time, the program
*   plots the set again, with its horizontal position
*   shifted slightly, scrolling new lines up from the bottom
*   of the screen. This process continues indefinitely.
*
*   See the accompanying README.md file for more details.
*
*   LisaMandelbrot Solo may be useful for power supply
*   burn-in tests, or for other tasks where it could be
*   useful to have the Lisa running "hands off" for a while
*   without the screen dimming. However, there is no
*   guarantee that LisaMandelbrot is suitable for avoiding
*   screen burn-in (or any other sort of damage) under these
*   or any other circumstances.
*
*   LisaMandelbrot Solo and any supporting programs,
*   software libraries, and documentation distributed
*   alongside it are released into the public domain without
*   any warranty. See the UNLICENSE file for details.
*-----------------------------------------------------------


    PAGE
* LisaMandelbrot Solo equates ==============================

    ; LisaMandelbrot Solo configuration constants.

    ; Set the following EQU nonzero for LisaMandelbrot Solo to eject the
    ; diskette on startup. For Boot ROM H systems only, but it doesn't seem to
    ; do any harm on a Boot ROM D Lisa 1 system (nothing happens). Recommended
    ; if loading from a 3.5" floppy disk.
kDoEject    EQU  1

    ; Set the following EQU nonzero for LisaMandelbrot Solo to draw a
    ; horizontal line of gray pixels at the bottom of the screen
    ; immediately after it scrolls the screen up by one line. This may not be
    ; desirable in "screen-saver-like" settings, since the average illumination
    ; of bottom-row pixels may not match the average illumination of pixels
    ; elsewhere on the screen.
kGreyBar    EQU  1

    ; How many times LisaMandelbrot Solo should iterate the equation
    ; z := z*z + c before deciding that c is inside the Mandelbrot set.
kIterations EQU  40

    ; Other LisaMandelbrot Solo constants.

kDiskMem    EQU  $00FCC001           ; Shared disk controller memory
kEjectDisk  EQU  $00FE1E56           ; Eject floppy disk ROM command

kScreenPtr  EQU  $0110               ; ROM-set pointer to start of video memory

kLeftReal   EQU  $8000               ; Least real coordinate: -2
kTopImag    EQU  $40B20000           ; Greatest imaginary coordinate: 1.0109i
kRightReal  EQU  $3EFC               ; Greatest real coordinate: 0.9841
kBottomImag EQU  $BF4E0000           ; Least imaginary coordinate: -1.0109i

kTopLeft    EQU  kTopImag+kLeftReal  ; Top left complex coordinate

kIncrImag   EQU  $FFA50000           ; Per-row imaginary coordinate increment
kIncrReal   EQU  $0044               ; Per-column real coordinate increment


    PAGE
* LisaMandelbrot Solo section definitions ==================

    ORG     $800                     ; Program code starts here


    PAGE
* LisaMandelbrot Solo macros ===============================

    ; mFixMul -- 16-bit signed fixed-point multiply
    ; Args:
    ;   \1: Source argument, word; bits are sign,1,1/2,1/4,1/8,...
    ;   \2: Dest. argument, word; same scheme
    ; Notes:
    ;   \2's MSWord will be the extended sign of the result.
mFixMul     MACRO
      MULS.W  \1,\2                  ; Perform multiply
      ; Arithmetic-shift the result 14-bits rightward

      ; This straightforward implementation of a 14-place arithmetic shift is
      ; expected to take 44 cycles.
;     ASR.L   #7,\2                  ; First half of shift
;     ASR.L   #7,\2                  ; Second half of shift

      ; This implementation of the shift is expected to take 32 cycles for a
      ; negative number and 42 cycles for other numbers. 
      BMI.S   .n\@                   ; Was the result <0? Jump to handle it
      ANDI.W  #$C000,\2              ; "Extend" the + sign
      BRA.S   .r\@                   ; Jump to rotate number into the LSWord
.n\@  ORI.W   #$3FFF,\2              ; "Extend" the - sign
.r\@  SWAP.W  \2                     ; Rotate part 1: swap "rotates" 16 places
      ROL.L   #2,\2                  ; Rotate part 2: back up two places
            ENDM

    ; mFixBOf -- Branch on overflow of 16-bit signed fixed-point w/extended sign
    ; Args:
    ;   \1: Longword whose LSWord should be checked for overflow
    ;   \2: Where to branch on overflow
    ; Notes:
    ;   Contents of \1 will be destroyed if an overflow is detected
mFixBOf     MACRO
      ROL.L   #1,\1                  ; Rotate "sign bit" into MSWord
      SWAP.W  \1                     ; LSWord to MSWord for sign analysis
      ADDQ.W  #1,\1                  ; Add one; overflow now iff > 1
      CMPI.W  #1,\1                  ; Well, are we > 1?
      BHI.S   \2                     ; Yes, jump
      SUBQ.W  #1,\1                  ; No, restore original value part 1
      SWAP.W  \1                     ; Part 2
      ROR.L   #1,\1                  ; Part 3
            ENDM


    PAGE
* LisaMandelbrot Solo code =================================

MANDEL:
    ; D0    complex number
    ; D1-D4 scratch
    ; D5    shifting accumulator for pixels to put on the screen
    ; A0    screen pointer
    ; A1    end of screen pointer

            IFNE kDoEject
    ; Eject the floppy disk.
    LEA     kDiskMem,A0              ; Disk shared memory into A0
    JSR     kEjectDisk               ; Eject the disk
            ENDC

    ; Initialisation.
    MOVEA.L kScreenPtr,A0            ; Point A0 to the top of the screen buffer
    MOVEA.L A0,A1                    ; Copy it to A1 as well
    ADDA.L  #$7FF8,A1                ; Point A1 just past the end of the buffer

    ; Outer, middle, and inner loops. Outer loop loops over Mandelbrots; inner
    ; loop loops over bytes to write to the display.
    MOVEQ.L #$1,D5                   ; Prepare pixel accumulator
.lo MOVE.L  #kTopLeft,D0             ;   Set c for top left corner

    ; Is the current point in the set?
.li MOVE.W  #(kIterations-1),D1      ;     Do <=40 iterations of mandelbration
    BSR.B   MANDITER                 ;     Call mandelbrator

    ; Add verdict to the accumulator. If the accumulator is full (as marked by
    ; a sentinel bit arriving in bit location 8), write the byte to the screen.
    ; If we have filled the screen, scroll the display by one line.
    ROXL.W  #1,D5                    ;     Rotate the set membership bit into D5
    BTST.L  #8,D5                    ;     Have we filled the accumulator?
    BEQ.S   .no                      ;     No, jump ahead
    MOVE.B  D5,(A0)+                 ;     Yes, copy dots to the screen
    MOVEQ.L #$1,D5                   ;     Reset pixel accumulator
    CMPA.L  A1,A0                    ;     Have we filled the screen?
    BLO.S   .no                      ;     No, jump ahead
    BSR.B   SCROLL                   ;     Yes, scroll the display one line...
    SUBA.L  #90,A0                   ;     ...and rewind screen pointer one line

    ; Update c. If it passes the right and/or bottom edges of the complex number
    ; bounds, snap c back to the left and/or top edges.
.no ADDI.W  #kIncrReal,D0            ;     Add real part increment to c
    CMP.W   #kRightReal,D0           ;     Past the rightmost bound?
    BLE.S   .li                      ;     No, we're in bounds for real part
    MOVE.W  #kLeftReal,D0            ;     Yes, snap real part to left...
    ADDI.L  #kIncrImag,D0            ;     ...and increment imaginary part
    CMP.L   #kBottomImag,D0          ;     Past the bottom bound?
    BGE.S   .li                      ;     No, in bounds for imaginary part
    SUB.L   #13,A0                   ;   Yes, rewind screen ptr for horiz offset
    BRA.S   .lo                      ;   And back to top left


SCROLL:
    ; SCROLL -- Scroll the screen up one line
    ; Args:
    ;   $0110: ROM-set pointer to start of video memory
    ;   A1: end of screen pointer
    ; Notes:
    ;   Trashes A3-A4
    MOVEA.L kScreenPtr,A3            ; Point A3 to the top of the screen buffer
    LEA.L   90(A3),A4                ; Point A4 one line ahead of A3
.lc MOVE.B  (A4)+,(A3)+              ; Copy next line's byte to current line
    CMPA.L  A1,A4                    ; Are we at the end of the screen?
    BLO.S   .lc                      ; No, not yet
            IFEQ kGreyBar
.lx MOVE.B  #$55,(A3)+               ; Fill dot pattern into last line
    CMPA.L  A1,A3                    ; Are we at the end of the screen?
    BLO.S   .lx                      ; No, not yet
            ENDC
    RTS                              ; Back to caller


    ; MANDITER -- Iterate the equation z' = z^2 + c
    ; Args:
    ;   D0: c; imaginary part in MSWord, real in LSWord
    ;   D1: number of iterations minus one (word)
    ; Notes:
    ;   Trashes D1-D4.
    ;   Inputs should be in (-2,2)+(-2i,2i).
    ;   On return, X flag means that z has not diverged in D1+1 iterations.
MANDITER:
    ; Initialisation
    MOVE.L  D0,D2                    ; D2 is z; initialise with c

    ; Equation iteration -- part 1, compute real part
.it MOVE.W  D2,D3                    ; copy real part to D3
    mFixMul D2,D3                    ; square it
    SWAP.W  D2                       ; swap real/imaginary parts of z
    MOVE.W  D2,D4                    ; copy imaginary part to D4
    mFixMul D2,D4                    ; square it
    SUB.L   D4,D3                    ; subtract imaginary^2 from real^2 into D3
    MOVE.W  D0,D4                    ; copy c real part to D4
    EXT.L   D4                       ; extend its sign to longword
    ADD.L   D4,D3                    ; add to D3, which is now z' real part
    mFixBOf D3,.no                   ; reject if real part is overflowed

    ; Equation iteration -- part 2, compute imaginary part
    MOVE.W  D2,D4                    ; copy imaginary part to D4
    SWAP.W  D2                       ; unswap real/imaginary parts of z
    mFixMul D2,D4                    ; multiply real and imaginary into D4
    ASL.L   #1,D4                    ; multiply that result by 2
    MOVE.W  D3,D2                    ; update D2 with z' real from earlier
    SWAP.W  D0                       ; swap real/imaginary parts of c
    MOVE.W  D0,D3                    ; copy c imaginary part to D3
    EXT.L   D3                       ; extend its sign to longword
    ADD.L   D4,D3                    ; add in D4 to obtain z' imaginary part
    SWAP.W  D0                       ; unswap real/imaginary parts of c
    mFixBOf D3,.no                   ; reject if imaginary part is overflowed
    SWAP.W  D2                       ; swap real/imaginary parts of z
    MOVE.W  D3,D2                    ; update D2 with z' imaginary
    SWAP.W  D2                       ; unswap real/imaginary parts of z'

    ; If we're here, we either loop again or accept c
    DBRA    D1,.it                   ; Loop again if iterations are left
    ORI.B   #$10,CCR                 ; Set X bit to note set membership
    RTS                              ; Back to caller

    ; If we're here, we reject c
.no ANDI.B  #$EF,CCR                 ; Clear X bit to note set non-membership
    RTS                              ; Back to caller


    PAGE
* LisaMandelbrot Solo numerical data =======================


    PAGE
* LisaMandelbrot Solo scratch data allocation ==============


    PAGE
* LisaMandelbrot Solo strings ==============================


    PAGE
* End of LisaMandelbrot Solo source ========================

    ; Designates MANDEL as the beginning of the program.
    END    MANDEL


*~Font name~Courier New~
*~Font size~10~
*~Tab type~1~
*~Tab size~4~
