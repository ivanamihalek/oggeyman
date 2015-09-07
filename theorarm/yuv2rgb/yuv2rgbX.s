@ YUV-> RGB conversion code Copyright (C) 2008 Robin Watts (robin;wss.co.uk).
@
@ Licensed under the GPL. If you need it under another license, contact me
@ and ask.
@
@  This program is free software ; you can redistribute it and/or modify
@  it under the terms of the GNU General Public License as published by
@  the Free Software Foundation ; either version 2 of the License, or
@  (at your option) any later version.
@
@  This program is distributed in the hope that it will be useful,
@  but WITHOUT ANY WARRANTY ; without even the implied warranty of
@  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
@  GNU General Public License for more details.
@
@  You should have received a copy of the GNU General Public License
@  along with this program ; if not, write to the Free Software
@  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307 USA
@
@
@ The algorithm used here is based heavily on one created by Sophie Wilson
@ of Acorn/e-14/Broadcomm. Many thanks.
@
@ Additional tweaks (in the fast fixup code) are from Paul Gardiner.
@
@ The old implementation of YUV -> RGB did:
@
@ R = CLAMP((Y-16)*1.164 +           1.596*V)
@ G = CLAMP((Y-16)*1.164 - 0.391*U - 0.813*V)
@ B = CLAMP((Y-16)*1.164 + 2.018*U          )
@
@ Were going to bend that here as follows:
@
@ R = CLAMP(y +           1.596*V)
@ G = CLAMP(y - 0.383*U - 0.813*V)
@ B = CLAMP(y + 1.976*U          )
@
@ where y = 0               for       Y <=  16,
@       y = (  Y-16)*1.164, for  16 < Y <= 239,
@       y = (239-16)*1.164, for 239 < Y
@
@ i.e. We clamp Y to the 16 to 239 range (which it is supposed to be in
@ anyway). We then pick the B_U factor so that B never exceeds 511. We then
@ shrink the G_U factor in line with that to avoid a colour shift as much as
@ possible.
@
@ Were going to use tables to do it faster, but rather than doing it using
@ 5 tables as as the above suggests, were going to do it using just 3.
@
@ We do this by working in parallel within a 32 bit word, and using one
@ table each for Y U and V.
@
@ Source Y values are    0 to 255, so    0.. 260 after scaling
@ Source U values are -128 to 127, so  -49.. 49(G), -253..251(B) after
@ Source V values are -128 to 127, so -204..203(R), -104..103(G) after
@
@ So total summed values:
@ -223 <= R <= 481, -173 <= G <= 431, -253 <= B < 511
@
@ We need to pack R G and B into a 32 bit word, and because of Bs range we
@ need 2 bits above the valid range of B to detect overflow, and another one
@ to detect the sense of the overflow. We therefore adopt the following
@ representation:
@
@ osGGGGGgggggosBBBBBbbbosRRRRRrrr
@
@ Each such word breaks down into 3 ranges.
@
@ osGGGGGggggg   osBBBBBbbb   osRRRRRrrr
@
@ Thus we have 8 bits for each B and R table entry, and 10 bits for G (good
@ as G is the most noticable one). The s bit for each represents the sign,
@ and o represents the overflow.
@
@ For R and B we pack the table by taking the 11 bit representation of their
@ values, and toggling bit 10 in the U and V tables.
@
@ For the green case we calculate 4*G (thus effectively using 10 bits for the
@ valid range) truncate to 12 bits. We toggle bit 11 in the Y table.

@ Theorarm library
@ Copyright (C) 2009 Robin Watts for Pinknoise Productions Ltd

    .text

	.global	yuv420_2_rgb565
	.global	yuv420_2_rgb565_PROFILE
	.global	yuv2rgb_table

@ void yuv420_2_rgb565
@  uint8_t *dst_ptr
@  uint8_t *y_ptr
@  uint8_t *u_ptr
@  uint8_t *v_ptr
@  int      width
@  int      height
@  int      y_span
@  int      uv_span
@  int      dst_span
@  int     *tables
@  int      dither

 .set DITH1,	7
 .set DITH2,	6

yuv420_2_rgb565_PROFILE:		@ Symbol exposed for profiling purposes
CONST_mask:
	.word	0x07E0F81F
CONST_flags:
	.word	0x40080100
yuv420_2_rgb565:
	@ r0 = dst_ptr
	@ r1 = y_ptr
	@ r2 = u_ptr
	@ r3 = v_ptr
	@ <> = width
	@ <> = height
	@ <> = y_span
	@ <> = uv_span
	@ <> = dst_span
	@ <> = y_table
	@ <> = dither
	STMFD	r13!,{r4-r11,r14}

	LDR	r8, [r13,#10*4]		@ r8 = height
	LDR	r10,[r13,#11*4]		@ r10= y_span
	LDR	r9, [r13,#13*4]		@ r9 = dst_span
	LDR	r14,[r13,#14*4]		@ r14= y_table
	LDR	r11,[r13,#15*4]		@ r11= dither
	LDR	r4, CONST_mask
	LDR	r5, CONST_flags
	ANDS	r11,r11,#3
	BEQ	asm0
	CMP	r11, #2
	BEQ	asm3
	BGT	asm2
asm1:
	@  Dither: 1 2
	@          3 0
	LDR	r11,[r13,#9*4]		@ r11= width
	SUBS	r8, r8, #1
	BLT	end
	BEQ	trail_row1
yloop1:
	SUB	r8, r8, r11,LSL #16	@ r8 = height-(width<<16)
	ADDS	r8, r8, #1<<16		@ if (width == 1)
	BGE	trail_pair1		@    just do 1 column
xloop1:
	LDRB	r11,[r2], #1		@ r11 = u  = *u_ptr++
	LDRB	r12,[r3], #1		@ r12 = v  = *v_ptr++
	LDRB	r7, [r1, r10]		@ r7  = y2 = y_ptr[stride]
	LDRB	r6, [r1], #1		@ r6  = y0 = *y_ptr++
	ADD	r11,r11,#256
	ADD	r12,r12,#512
	WLDRW	wr0,[r14,r11,LSL #2]	@ wr0 = u  = u_table[u]
	WLDRW	wr1,[r14,r12,LSL #2]	@ wr1 = v  = v_table[v]
	WLDRW	wr2,[r14,r7, LSL #2]	@ wr2 = y2 = y_table[y2]
	WLDRW	wr3,[r14,r6, LSL #2]	@ wr3 = y0 = y_table[y0]
	@ Stall
	WADDW	wr0,wr0,wr1		@ wr0 = uv = u+v

	WADDW	wr1,wr0,wr15		@ wr1 = uv1 += dither1
	WADDW	wr2,wr2,wr1		@ wr2 = y2 += uv1
	WADDW	wr3,wr3,wr1		@ wr3 = y0 += uv1
	WADDW	wr3,wr3,wr14		@ wr3 = y0 += dither2
	TMRC	r7,wr2
	TMRC	r6,wr3
	ANDS	r12,r7, r5
	TSTEQ	r6, r5
	BNE	fix101
return101:
	AND	r7, r4, r7, LSR #3
	ORR	r7, r7, r7, LSR #16
	STRH	r7, [r0, r9]
	AND	r6, r4, r6, LSR #3
	LDRB	r12,[r1, r10]		@ r12 = y3 = y_ptr[stride]
	LDRB	r7, [r1], #1		@ r6  = y1 = *y_ptr++
	ORR	r6, r6, r6, LSR #16
	LDR	r12,[r14, r12,LSL #2]	@ r7  = y3 = y_table[y2]
	STRH	r6, [r0], #2
	LDR	r6, [r14, r7, LSL #2]	@ r6  = y1 = y_table[y0]

	ADD	r7, r12,r11		@ r7  = y3 + uv
	ADD	r6, r6, r11		@ r6  = y1 + uv
	ADD	r6, r6, r5, LSR #DITH2	@ r6  = y1 + uv + dither2
	ANDS	r12,r7, r5
	TSTEQ	r6, r5
	BNE	fix102
return102:
	AND	r7, r4, r7, LSR #3
	AND	r6, r4, r6, LSR #3
	ORR	r7, r7, r7, LSR #16
	ORR	r6, r6, r6, LSR #16
	STRH	r7, [r0, r9]
	STRH	r6, [r0], #2
	ADDS	r8, r8, #2<<16
	BLT	xloop1
	MOVS	r8, r8, LSL #16		@ Clear the top 16 bits of r8
	MOV	r8, r8, LSR #16		@ If the C bit is clear we still have
	BCC	trail_pair1		@ 1 more pixel pair to do
end_xloop1:
	LDR	r11,[r13,#9*4]		@ r11= width
	LDR	r12,[r13,#12*4]		@ r12= uv_stride
	ADD	r0, r0, r9, LSL #1
	SUB	r0, r0, r11,LSL #1
	ADD	r1, r1, r10,LSL #1
	SUB	r1, r1, r11
	SUB	r2, r2, r11,LSR #1
	SUB	r3, r3, r11,LSR #1
	ADD	r2, r2, r12
	ADD	r3, r3, r12

	SUBS	r8, r8, #2
	BGT	yloop1

	LDMLTFD	r13!,{r4-r11,pc}
trail_row1:
	@ We have a row of pixels left to do
	SUB	r8, r8, r11,LSL #16	@ r8 = height-(width<<16)
	ADDS	r8, r8, #1<<16		@ if (width == 1)
	BGE	trail_pix1		@    just do 1 pixel
xloop12:
	LDRB	r11,[r2], #1		@ r11 = u  = *u_ptr++
	LDRB	r12,[r3], #1		@ r12 = v  = *v_ptr++
	LDRB	r6, [r1], #1		@ r6  = y0 = *y_ptr++
	LDRB	r7, [r1], #1		@ r7  = y1 = *y_ptr++
	ADD	r11,r11,#256
	ADD	r12,r12,#512
	LDR	r11,[r14,r11,LSL #2]	@ r11 = u  = u_table[u]
	LDR	r12,[r14,r12,LSL #2]	@ r12 = v  = v_table[v]
	LDR	r7, [r14,r7, LSL #2]	@ r7  = y1 = y_table[y1]
	LDR	r6, [r14,r6, LSL #2]	@ r6  = y0 = y_table[y0]
	ADD	r11,r11,r12		@ r11 = uv = u+v

	ADD	r6, r6, r11		@ r6  = y0 + uv
	ADD	r6, r6, r5, LSR #DITH1	@ r6  = y0 + uv + dither1
	ADD	r7, r7, r11		@ r7  = y1 + uv
	ADD	r7, r7, r5, LSR #DITH2	@ r7  = y1 + uv + dither2
	ANDS	r12,r7, r5
	TSTEQ	r6, r5
	BNE	fix104
return104:
	AND	r6, r4, r6, LSR #3
	ORR	r6, r6, r6, LSR #16
	STRH	r6, [r0], #2
	AND	r7, r4, r7, LSR #3
	ORR	r7, r7, r7, LSR #16
	STRH	r7, [r0], #2
	ADDS	r8, r8, #2<<16
	BLT	xloop12
	MOVS	r8, r8, LSL #16		@ Clear the top 16 bits of r8
	MOV	r8, r8, LSR #16		@ If the C bit is clear we still have
	BCC	trail_pix1		@ 1 more pixel pair to do
end:
	LDMFD	r13!,{r4-r11,pc}
trail_pix1:
	@ We have a single extra pixel to do
	LDRB	r11,[r2], #1		@ r11 = u  = *u_ptr++
	LDRB	r12,[r3], #1		@ r12 = v  = *v_ptr++
	LDRB	r6, [r1], #1		@ r6  = y0 = *y_ptr++
	ADD	r11,r11,#256
	ADD	r12,r12,#512
	LDR	r11,[r14,r11,LSL #2]	@ r11 = u  = u_table[u]
	LDR	r12,[r14,r12,LSL #2]	@ r12 = v  = v_table[v]
	LDR	r6, [r14,r6, LSL #2]	@ r6  = y0 = y_table[y0]
	ADD	r11,r11,r12		@ r11 = uv = u+v

	ADD	r11,r11,r5, LSR #DITH1	@ (dither 1/4)
	ADD	r6, r6, r11		@ r6  = y0 + uv + dither1
	ANDS	r12,r6, r5
	BNE	fix105
return105:
	AND	r6, r4, r6, LSR #3
	ORR	r6, r6, r6, LSR #16
	STRH	r6, [r0], #2

	LDMFD	r13!,{r4-r11,pc}

trail_pair1:
	@ We have a pair of pixels left to do
	LDRB	r11,[r2]		@ r11 = u  = *u_ptr++
	LDRB	r12,[r3]		@ r12 = v  = *v_ptr++
	LDRB	r7, [r1, r10]		@ r7  = y2 = y_ptr[stride]
	LDRB	r6, [r1], #1		@ r6  = y0 = *y_ptr++
	ADD	r11,r11,#256
	ADD	r12,r12,#512
	LDR	r11,[r14,r11,LSL #2]	@ r11 = u  = u_table[u]
	LDR	r12,[r14,r12,LSL #2]	@ r12 = v  = v_table[v]
	LDR	r7, [r14,r7, LSL #2]	@ r7  = y2 = y_table[y2]
	LDR	r6, [r14,r6, LSL #2]	@ r6  = y0 = y_table[y0]
	ADD	r11,r11,r12		@ r11 = uv = u+v

	ADD	r11,r11,r5, LSR #DITH1
	ADD	r7, r7, r11		@ r7  = y2 + uv + dither1
	ADD	r6, r6, r11		@ r6  = y0 + uv
	ADD	r7, r7, r5, LSR #DITH2	@ r7  = y2 + uv + dither3
	ANDS	r12,r7, r5
	TSTEQ	r6, r5
	BNE	fix103
return103:
	AND	r7, r4, r7, LSR #3
	ORR	r7, r7, r7, LSR #16
	STRH	r7, [r0, r9]
	AND	r6, r4, r6, LSR #3
	ORR	r6, r6, r6, LSR #16
	STRH	r6, [r0], #2
	B	end_xloop1
fix101:
	@ r7 and r6 are the values, at least one of which has overflowed
	@ r12 = r7 & mask = .s......s......s......
	SUB	r12,r12,r12,LSR #8	@ r12 = ..SSSSSS.SSSSSS.SSSSSS
	ORR	r7, r7, r12		@ r7 |= ..SSSSSS.SSSSSS.SSSSSS
	BIC	r12,r5, r7, LSR #1	@ r12 = .o......o......o......
	ADD	r7, r7, r12,LSR #8	@ r7  = fixed value

	AND	r12, r6, r5		@ r12 = .S......S......S......
	SUB	r12,r12,r12,LSR #8	@ r12 = ..SSSSSS.SSSSSS.SSSSSS
	ORR	r6, r6, r12		@ r6 |= ..SSSSSS.SSSSSS.SSSSSS
	BIC	r12,r5, r6, LSR #1	@ r12 = .o......o......o......
	ADD	r6, r6, r12,LSR #8	@ r6  = fixed value
	B	return101
fix102:
	@ r7 and r6 are the values, at least one of which has overflowed
	@ r12 = r7 & mask = .s......s......s......
	SUB	r12,r12,r12,LSR #8	@ r12 = ..SSSSSS.SSSSSS.SSSSSS
	ORR	r7, r7, r12		@ r7 |= ..SSSSSS.SSSSSS.SSSSSS
	BIC	r12,r5, r7, LSR #1	@ r12 = .o......o......o......
	ADD	r7, r7, r12,LSR #8	@ r7  = fixed value

	AND	r12, r6, r5		@ r12 = .S......S......S......
	SUB	r12,r12,r12,LSR #8	@ r12 = ..SSSSSS..SSSSS.SSSSSS
	ORR	r6, r6, r12		@ r6 |= ..SSSSSS..SSSSS.SSSSSS
	BIC	r12,r5, r6, LSR #1	@ r12 = .o......o......o......
	ADD	r6, r6, r12,LSR #8	@ r6  = fixed value
	B	return102
fix103:
	@ r7 and r6 are the values, at least one of which has overflowed
	@ r12 = r7 & mask = .s......s......s......
	SUB	r12,r12,r12,LSR #8	@ r12 = ..SSSSSS.SSSSSS.SSSSSS
	ORR	r7, r7, r12		@ r7 |= ..SSSSSS.SSSSSS.SSSSSS
	BIC	r12,r5, r7, LSR #1	@ r12 = .o......o......o......
	ADD	r7, r7, r12,LSR #8	@ r7  = fixed value

	AND	r12, r6, r5		@ r12 = .S......S......S......
	SUB	r12,r12,r12,LSR #8	@ r12 = ..SSSSSS.SSSSSS.SSSSSS
	ORR	r6, r6, r12		@ r6 |= ..SSSSSS.SSSSSS.SSSSSS
	BIC	r12,r5, r6, LSR #1	@ r12 = .o......o......o......
	ADD	r6, r6, r12,LSR #8	@ r6  = fixed value
	B	return103
fix104:
	@ r7 and r6 are the values, at least one of which has overflowed
	@ r12 = r7 & mask = .s......s......s......
	SUB	r12,r12,r12,LSR #8	@ r12 = ..SSSSSS.SSSSSS.SSSSSS
	ORR	r7, r7, r12		@ r7 |= ..SSSSSS.SSSSSS.SSSSSS
	BIC	r12,r5, r7, LSR #1	@ r12 = .o......o......o......
	ADD	r7, r7, r12,LSR #8	@ r7  = fixed value

	AND	r12, r6, r5		@ r12 = .S......S......S......
	SUB	r12,r12,r12,LSR #8	@ r12 = ..SSSSSS.SSSSSS.SSSSSS
	ORR	r6, r6, r12		@ r6 |= ..SSSSSS.SSSSSS.SSSSSS
	BIC	r12,r5, r6, LSR #1	@ r12 = .o......o......o......
	ADD	r6, r6, r12,LSR #8	@ r6  = fixed value
	B	return104
fix105:
	@ r6 is the value, which has has overflowed
	@ r12 = r7 & mask = .s......s......s......
	SUB	r12,r12,r12,LSR #8	@ r12 = ..SSSSSS.SSSSSS.SSSSSS
	ORR	r6, r6, r12		@ r6 |= ..SSSSSS.SSSSSS.SSSSSS
	BIC	r12,r5, r6, LSR #1	@ r12 = .o......o......o......
	ADD	r6, r6, r12,LSR #8	@ r6  = fixed value
	B	return105

@------------------------------------------------------------------------
asm0:
	@  Dither: 0 3
	@          2 1
	LDR	r11,[r13,#9*4]		@ r11= width
	SUBS	r8, r8, #1
	BLT	end
	BEQ	trail_row0
yloop0:
	SUB	r8, r8, r11,LSL #16	@ r8 = height-(width<<16)
	ADDS	r8, r8, #1<<16		@ if (width == 1)
	BGE	trail_pair0		@    just do 1 column
xloop0:
	LDRB	r11,[r2], #1		@ r11 = u  = *u_ptr++
	LDRB	r12,[r3], #1		@ r12 = v  = *v_ptr++
	LDRB	r7, [r1, r10]		@ r7  = y2 = y_ptr[stride]
	LDRB	r6, [r1], #1		@ r6  = y0 = *y_ptr++
	ADD	r11,r11,#256
	ADD	r12,r12,#512
	LDR	r11,[r14,r11,LSL #2]	@ r11 = u  = u_table[u]
	LDR	r12,[r14,r12,LSL #2]	@ r12 = v  = v_table[v]
	LDR	r7, [r14,r7, LSL #2]	@ r7  = y2 = y_table[y2]
	LDR	r6, [r14,r6, LSL #2]	@ r6  = y0 = y_table[y0]
	ADD	r11,r11,r12		@ r11 = uv = u+v

	ADD	r7, r7, r11		@ r7  = y2 + uv
	ADD	r6, r6, r11		@ r6  = y0 + uv
	ADD	r7, r7, r5, LSR #DITH2	@ r7  = y2 + uv + dither2
	ANDS	r12,r7, r5
	TSTEQ	r6, r5
	BNE	fix001
return001:
	AND	r7, r4, r7, LSR #3
	ORR	r7, r7, r7, LSR #16
	STRH	r7, [r0, r9]
	AND	r6, r4, r6, LSR #3
	LDRB	r12,[r1, r10]		@ r12 = y3 = y_ptr[stride]
	LDRB	r7, [r1], #1		@ r6  = y1 = *y_ptr++
	ORR	r6, r6, r6, LSR #16
	LDR	r12,[r14, r12,LSL #2]	@ r7  = y3 = y_table[y2]
	STRH	r6, [r0], #2
	LDR	r6, [r14, r7, LSL #2]	@ r6  = y1 = y_table[y0]

	ADD	r11,r11,r5, LSR #DITH1
	ADD	r7, r12,r11		@ r7  = y3 + uv + dither1
	ADD	r6, r6, r11		@ r6  = y1 + uv + dither1
	ADD	r6, r6, r5, LSR #DITH2	@ r6  = y1 + uv + dither3
	ANDS	r12,r7, r5
	TSTEQ	r6, r5
	BNE	fix002
return002:
	AND	r7, r4, r7, LSR #3
	AND	r6, r4, r6, LSR #3
	ORR	r7, r7, r7, LSR #16
	ORR	r6, r6, r6, LSR #16
	STRH	r7, [r0, r9]
	STRH	r6, [r0], #2
	ADDS	r8, r8, #2<<16
	BLT	xloop0
	MOVS	r8, r8, LSL #16		@ Clear the top 16 bits of r8
	MOV	r8, r8, LSR #16		@ If the C bit is clear we still have
	BCC	trail_pair0		@ 1 more pixel pair to do
end_xloop0:
	LDR	r11,[r13,#9*4]		@ r11= width
	LDR	r12,[r13,#12*4]		@ r12= uv_stride
	ADD	r0, r0, r9, LSL #1
	SUB	r0, r0, r11,LSL #1
	ADD	r1, r1, r10,LSL #1
	SUB	r1, r1, r11
	SUB	r2, r2, r11,LSR #1
	SUB	r3, r3, r11,LSR #1
	ADD	r2, r2, r12
	ADD	r3, r3, r12

	SUBS	r8, r8, #2
	BGT	yloop0

	LDMLTFD	r13!,{r4-r11,pc}
trail_row0:
	@ We have a row of pixels left to do
	SUB	r8, r8, r11,LSL #16	@ r8 = height-(width<<16)
	ADDS	r8, r8, #1<<16		@ if (width == 1)
	BGE	trail_pix0		@    just do 1 pixel
xloop02:
	LDRB	r11,[r2], #1		@ r11 = u  = *u_ptr++
	LDRB	r12,[r3], #1		@ r12 = v  = *v_ptr++
	LDRB	r6, [r1], #1		@ r6  = y0 = *y_ptr++
	LDRB	r7, [r1], #1		@ r7  = y1 = *y_ptr++
	ADD	r11,r11,#256
	ADD	r12,r12,#512
	LDR	r11,[r14,r11,LSL #2]	@ r11 = u  = u_table[u]
	LDR	r12,[r14,r12,LSL #2]	@ r12 = v  = v_table[v]
	LDR	r7, [r14,r7, LSL #2]	@ r7  = y1 = y_table[y1]
	LDR	r6, [r14,r6, LSL #2]	@ r6  = y0 = y_table[y0]
	ADD	r11,r11,r12		@ r11 = uv = u+v

	ADD	r6, r6, r11		@ r6  = y0 + uv
	ADD	r7, r7, r11		@ r7  = y1 + uv
	ADD	r7, r7, r5, LSR #DITH1	@ r7  = y1 + uv + dither1
	ADD	r7, r7, r5, LSR #DITH2	@ r7  = y1 + uv + dither3
	ANDS	r12,r7, r5
	TSTEQ	r6, r5
	BNE	fix004
return004:
	AND	r6, r4, r6, LSR #3
	ORR	r6, r6, r6, LSR #16
	STRH	r6, [r0], #2
	AND	r7, r4, r7, LSR #3
	ORR	r7, r7, r7, LSR #16
	STRH	r7, [r0], #2
	ADDS	r8, r8, #2<<16
	BLT	xloop02
	MOVS	r8, r8, LSL #16		@ Clear the top 16 bits of r8
	MOV	r8, r8, LSR #16		@ If the C bit is clear we still have
	BCC	trail_pix0		@ 1 more pixel pair to do

	LDMFD	r13!,{r4-r11,pc}
trail_pix0:
	@ We have a single extra pixel to do
	LDRB	r11,[r2], #1		@ r11 = u  = *u_ptr++
	LDRB	r12,[r3], #1		@ r12 = v  = *v_ptr++
	LDRB	r6, [r1], #1		@ r6  = y0 = *y_ptr++
	ADD	r11,r11,#256
	ADD	r12,r12,#512
	LDR	r11,[r14,r11,LSL #2]	@ r11 = u  = u_table[u]
	LDR	r12,[r14,r12,LSL #2]	@ r12 = v  = v_table[v]
	LDR	r6, [r14,r6, LSL #2]	@ r6  = y0 = y_table[y0]
	@ Stall (on Xscale)
	ADD	r11,r11,r12		@ r11 = uv = u+v

	ADD	r6, r6, r11		@ r6  = y0 + uv
	ANDS	r12,r6, r5
	BNE	fix005
return005:
	AND	r6, r4, r6, LSR #3
	ORR	r6, r6, r6, LSR #16
	STRH	r6, [r0], #2

	LDMFD	r13!,{r4-r11,pc}

trail_pair0:
	@ We have a pair of pixels left to do
	LDRB	r11,[r2]		@ r11 = u  = *u_ptr++
	LDRB	r12,[r3]		@ r12 = v  = *v_ptr++
	LDRB	r7, [r1, r10]		@ r7  = y2 = y_ptr[stride]
	LDRB	r6, [r1], #1		@ r6  = y0 = *y_ptr++
	ADD	r11,r11,#256
	ADD	r12,r12,#512
	LDR	r11,[r14,r11,LSL #2]	@ r11 = u  = u_table[u]
	LDR	r12,[r14,r12,LSL #2]	@ r12 = v  = v_table[v]
	LDR	r7, [r14,r7, LSL #2]	@ r7  = y2 = y_table[y2]
	LDR	r6, [r14,r6, LSL #2]	@ r6  = y0 = y_table[y0]
	ADD	r11,r11,r12		@ r11 = uv = u+v

	ADD	r7, r7, r11		@ r7  = y2 + uv
	ADD	r6, r6, r11		@ r6  = y0 + uv
	ADD	r7, r7, r5, LSR #DITH2	@ r7  = y2 + uv + dither2
	ANDS	r12,r7, r5
	TSTEQ	r6, r5
	BNE	fix003
return003:
	AND	r7, r4, r7, LSR #3
	ORR	r7, r7, r7, LSR #16
	STRH	r7, [r0, r9]
	AND	r6, r4, r6, LSR #3
	ORR	r6, r6, r6, LSR #16
	STRH	r6, [r0], #2
	B	end_xloop0
fix001:
	@ r7 and r6 are the values, at least one of which has overflowed
	@ r12 = r7 & mask = .s......s......s......
	SUB	r12,r12,r12,LSR #8	@ r12 = ..SSSSSS.SSSSSS.SSSSSS
	ORR	r7, r7, r12		@ r7 |= ..SSSSSS.SSSSSS.SSSSSS
	BIC	r12,r5, r7, LSR #1	@ r12 = .o......o......o......
	ADD	r7, r7, r12,LSR #8	@ r7  = fixed value

	AND	r12, r6, r5		@ r12 = .S......S......S......
	SUB	r12,r12,r12,LSR #8	@ r12 = ..SSSSSS.SSSSSS.SSSSSS
	ORR	r6, r6, r12		@ r6 |= ..SSSSSS.SSSSSS.SSSSSS
	BIC	r12,r5, r6, LSR #1	@ r12 = .o......o......o......
	ADD	r6, r6, r12,LSR #8	@ r6  = fixed value
	B	return001
fix002:
	@ r7 and r6 are the values, at least one of which has overflowed
	@ r12 = r7 & mask = .s......s......s......
	SUB	r12,r12,r12,LSR #8	@ r12 = ..SSSSSS.SSSSSS.SSSSSS
	ORR	r7, r7, r12		@ r7 |= ..SSSSSS.SSSSSS.SSSSSS
	BIC	r12,r5, r7, LSR #1	@ r12 = .o......o......o......
	ADD	r7, r7, r12,LSR #8	@ r7  = fixed value

	AND	r12, r6, r5		@ r12 = .S......S......S......
	SUB	r12,r12,r12,LSR #8	@ r12 = ..SSSSSS..SSSSS.SSSSSS
	ORR	r6, r6, r12		@ r6 |= ..SSSSSS..SSSSS.SSSSSS
	BIC	r12,r5, r6, LSR #1	@ r12 = .o......o......o......
	ADD	r6, r6, r12,LSR #8	@ r6  = fixed value
	B	return002
fix003:
	@ r7 and r6 are the values, at least one of which has overflowed
	@ r12 = r7 & mask = .s......s......s......
	SUB	r12,r12,r12,LSR #8	@ r12 = ..SSSSSS.SSSSSS.SSSSSS
	ORR	r7, r7, r12		@ r7 |= ..SSSSSS.SSSSSS.SSSSSS
	BIC	r12,r5, r7, LSR #1	@ r12 = .o......o......o......
	ADD	r7, r7, r12,LSR #8	@ r7  = fixed value

	AND	r12, r6, r5		@ r12 = .S......S......S......
	SUB	r12,r12,r12,LSR #8	@ r12 = ..SSSSSS.SSSSSS.SSSSSS
	ORR	r6, r6, r12		@ r6 |= ..SSSSSS.SSSSSS.SSSSSS
	BIC	r12,r5, r6, LSR #1	@ r12 = .o......o......o......
	ADD	r6, r6, r12,LSR #8	@ r6  = fixed value
	B	return003
fix004:
	@ r7 and r6 are the values, at least one of which has overflowed
	@ r12 = r7 & mask = .s......s......s......
	SUB	r12,r12,r12,LSR #8	@ r12 = ..SSSSSS.SSSSSS.SSSSSS
	ORR	r7, r7, r12		@ r7 |= ..SSSSSS.SSSSSS.SSSSSS
	BIC	r12,r5, r7, LSR #1	@ r12 = .o......o......o......
	ADD	r7, r7, r12,LSR #8	@ r7  = fixed value

	AND	r12, r6, r5		@ r12 = .S......S......S......
	SUB	r12,r12,r12,LSR #8	@ r12 = ..SSSSSS.SSSSSS.SSSSSS
	ORR	r6, r6, r12		@ r6 |= ..SSSSSS.SSSSSS.SSSSSS
	BIC	r12,r5, r6, LSR #1	@ r12 = .o......o......o......
	ADD	r6, r6, r12,LSR #8	@ r6  = fixed value
	B	return004
fix005:
	@ r6 is the value, which has has overflowed
	@ r12 = r7 & mask = .s......s......s......
	SUB	r12,r12,r12,LSR #8	@ r12 = ..SSSSSS.SSSSSS.SSSSSS
	ORR	r6, r6, r12		@ r6 |= ..SSSSSS.SSSSSS.SSSSSS
	BIC	r12,r5, r6, LSR #1	@ r12 = .o......o......o......
	ADD	r6, r6, r12,LSR #8	@ r6  = fixed value
	B	return005

@------------------------------------------------------------------------
asm2:
	@  Dither: 2 1
	@          0 3
	LDR	r11,[r13,#9*4]		@ r11= width
	SUBS	r8, r8, #1
	BLT	end
	BEQ	trail_row2
yloop2:
	SUB	r8, r8, r11,LSL #16	@ r8 = height-(width<<16)
	ADDS	r8, r8, #1<<16		@ if (width == 1)
	BGE	trail_pair2		@    just do 1 column
xloop2:
	LDRB	r11,[r2], #1		@ r11 = u  = *u_ptr++
	LDRB	r12,[r3], #1		@ r12 = v  = *v_ptr++
	LDRB	r7, [r1, r10]		@ r7  = y2 = y_ptr[stride]
	LDRB	r6, [r1], #1		@ r6  = y0 = *y_ptr++
	ADD	r11,r11,#256
	ADD	r12,r12,#512
	LDR	r11,[r14,r11,LSL #2]	@ r11 = u  = u_table[u]
	LDR	r12,[r14,r12,LSL #2]	@ r12 = v  = v_table[v]
	LDR	r7, [r14,r7, LSL #2]	@ r7  = y2 = y_table[y2]
	LDR	r6, [r14,r6, LSL #2]	@ r6  = y0 = y_table[y0]
	ADD	r11,r11,r12		@ r11 = uv = u+v

	ADD	r7, r7, r11		@ r7  = y2 + uv
	ADD	r6, r6, r11		@ r6  = y0 + uv
	ADD	r6, r6, r5, LSR #DITH2	@ r6  = y0 + uv + dither2
	ANDS	r12,r7, r5
	TSTEQ	r6, r5
	BNE	fix201
return201:
	AND	r7, r4, r7, LSR #3
	ORR	r7, r7, r7, LSR #16
	STRH	r7, [r0, r9]
	AND	r6, r4, r6, LSR #3
	LDRB	r12,[r1, r10]		@ r12 = y3 = y_ptr[stride]
	LDRB	r7, [r1], #1		@ r6  = y1 = *y_ptr++
	ORR	r6, r6, r6, LSR #16
	LDR	r12,[r14, r12,LSL #2]	@ r7  = y3 = y_table[y2]
	STRH	r6, [r0], #2
	LDR	r6, [r14, r7, LSL #2]	@ r6  = y1 = y_table[y0]

	ADD	r11,r11,r5, LSR #DITH1
	ADD	r7, r12,r11		@ r7  = y3 + uv + dither1
	ADD	r7, r7, r5, LSR #DITH2	@ r7  = y3 + uv + dither3
	ADD	r6, r6, r11		@ r6  = y1 + uv + dither1
	ANDS	r12,r7, r5
	TSTEQ	r6, r5
	BNE	fix202
return202:
	AND	r7, r4, r7, LSR #3
	AND	r6, r4, r6, LSR #3
	ORR	r7, r7, r7, LSR #16
	ORR	r6, r6, r6, LSR #16
	STRH	r7, [r0, r9]
	STRH	r6, [r0], #2
	ADDS	r8, r8, #2<<16
	BLT	xloop2
	MOVS	r8, r8, LSL #16		@ Clear the top 16 bits of r8
	MOV	r8, r8, LSR #16		@ If the C bit is clear we still have
	BCC	trail_pair2		@ 1 more pixel pair to do
end_xloop2:
	LDR	r11,[r13,#9*4]		@ r11= width
	LDR	r12,[r13,#12*4]		@ r12= uv_stride
	ADD	r0, r0, r9, LSL #1
	SUB	r0, r0, r11,LSL #1
	ADD	r1, r1, r10,LSL #1
	SUB	r1, r1, r11
	SUB	r2, r2, r11,LSR #1
	SUB	r3, r3, r11,LSR #1
	ADD	r2, r2, r12
	ADD	r3, r3, r12

	SUBS	r8, r8, #2
	BGT	yloop2

	LDMLTFD	r13!,{r4-r11,pc}
trail_row2:
	@ We have a row of pixels left to do
	SUB	r8, r8, r11,LSL #16	@ r8 = height-(width<<16)
	ADDS	r8, r8, #1<<16		@ if (width == 1)
	BGE	trail_pix2		@    just do 1 pixel
xloop22:
	LDRB	r11,[r2], #1		@ r11 = u  = *u_ptr++
	LDRB	r12,[r3], #1		@ r12 = v  = *v_ptr++
	LDRB	r6, [r1], #1		@ r6  = y0 = *y_ptr++
	LDRB	r7, [r1], #1		@ r7  = y1 = *y_ptr++
	ADD	r11,r11,#256
	ADD	r12,r12,#512
	LDR	r11,[r14,r11,LSL #2]	@ r11 = u  = u_table[u]
	LDR	r12,[r14,r12,LSL #2]	@ r12 = v  = v_table[v]
	LDR	r7, [r14,r7, LSL #2]	@ r7  = y1 = y_table[y1]
	LDR	r6, [r14,r6, LSL #2]	@ r6  = y0 = y_table[y0]
	ADD	r11,r11,r12		@ r11 = uv = u+v

	ADD	r6, r6, r11		@ r6  = y0 + uv
	ADD	r6, r6, r5, LSR #DITH2	@ r6  = y0 + uv + dither2
	ADD	r7, r7, r11		@ r7  = y1 + uv
	ADD	r7, r7, r5, LSR #DITH1	@ r7  = y1 + uv + dither1
	ANDS	r12,r7, r5
	TSTEQ	r6, r5
	BNE	fix204
return204:
	AND	r6, r4, r6, LSR #3
	ORR	r6, r6, r6, LSR #16
	STRH	r6, [r0], #2
	AND	r7, r4, r7, LSR #3
	ORR	r7, r7, r7, LSR #16
	STRH	r7, [r0], #2
	ADDS	r8, r8, #2<<16
	BLT	xloop22
	MOVS	r8, r8, LSL #16		@ Clear the top 16 bits of r8
	MOV	r8, r8, LSR #16		@ If the C bit is clear we still have
	BCC	trail_pix2		@ 1 more pixel pair to do

	LDMFD	r13!,{r4-r11,pc}
trail_pix2:
	@ We have a single extra pixel to do
	LDRB	r11,[r2], #1		@ r11 = u  = *u_ptr++
	LDRB	r12,[r3], #1		@ r12 = v  = *v_ptr++
	LDRB	r6, [r1], #1		@ r6  = y0 = *y_ptr++
	ADD	r11,r11,#256
	ADD	r12,r12,#512
	LDR	r11,[r14,r11,LSL #2]	@ r11 = u  = u_table[u]
	LDR	r12,[r14,r12,LSL #2]	@ r12 = v  = v_table[v]
	LDR	r6, [r14,r6, LSL #2]	@ r6  = y0 = y_table[y0]
	ADD	r11,r11,r12		@ r11 = uv = u+v

	ADD	r11,r11,r5, LSR #DITH2
	ADD	r6, r6, r11		@ r6  = y0 + uv + dither2
	ANDS	r12,r6, r5
	BNE	fix205
return205:
	AND	r6, r4, r6, LSR #3
	ORR	r6, r6, r6, LSR #16
	STRH	r6, [r0], #2

	LDMFD	r13!,{r4-r11,pc}

trail_pair2:
	@ We have a pair of pixels left to do
	LDRB	r11,[r2]		@ r11 = u  = *u_ptr++
	LDRB	r12,[r3]		@ r12 = v  = *v_ptr++
	LDRB	r7, [r1, r10]		@ r7  = y2 = y_ptr[stride]
	LDRB	r6, [r1], #1		@ r6  = y0 = *y_ptr++
	ADD	r11,r11,#256
	ADD	r12,r12,#512
	LDR	r11,[r14,r11,LSL #2]	@ r11 = u  = u_table[u]
	LDR	r12,[r14,r12,LSL #2]	@ r12 = v  = v_table[v]
	LDR	r7, [r14,r7, LSL #2]	@ r7  = y2 = y_table[y2]
	LDR	r6, [r14,r6, LSL #2]	@ r6  = y0 = y_table[y0]
	ADD	r11,r11,r12		@ r11 = uv = u+v

	ADD	r7, r7, r11		@ r7  = y2 + uv
	ADD	r6, r6, r11		@ r6  = y0 + uv
	ADD	r6, r6, r5, LSR #DITH2	@ r6  = y0 + uv + 2
	ANDS	r12,r7, r5
	TSTEQ	r6, r5
	BNE	fix203
return203:
	AND	r7, r4, r7, LSR #3
	ORR	r7, r7, r7, LSR #16
	STRH	r7, [r0, r9]
	AND	r6, r4, r6, LSR #3
	ORR	r6, r6, r6, LSR #16
	STRH	r6, [r0], #2
	B	end_xloop2
fix201:
	@ r7 and r6 are the values, at least one of which has overflowed
	@ r12 = r7 & mask = .s......s......s......
	SUB	r12,r12,r12,LSR #8	@ r12 = ..SSSSSS.SSSSSS.SSSSSS
	ORR	r7, r7, r12		@ r7 |= ..SSSSSS.SSSSSS.SSSSSS
	BIC	r12,r5, r7, LSR #1	@ r12 = .o......o......o......
	ADD	r7, r7, r12,LSR #8	@ r7  = fixed value

	AND	r12, r6, r5		@ r12 = .S......S......S......
	SUB	r12,r12,r12,LSR #8	@ r12 = ..SSSSSS.SSSSSS.SSSSSS
	ORR	r6, r6, r12		@ r6 |= ..SSSSSS.SSSSSS.SSSSSS
	BIC	r12,r5, r6, LSR #1	@ r12 = .o......o......o......
	ADD	r6, r6, r12,LSR #8	@ r6  = fixed value
	B	return201
fix202:
	@ r7 and r6 are the values, at least one of which has overflowed
	@ r12 = r7 & mask = .s......s......s......
	SUB	r12,r12,r12,LSR #8	@ r12 = ..SSSSSS.SSSSSS.SSSSSS
	ORR	r7, r7, r12		@ r7 |= ..SSSSSS.SSSSSS.SSSSSS
	BIC	r12,r5, r7, LSR #1	@ r12 = .o......o......o......
	ADD	r7, r7, r12,LSR #8	@ r7  = fixed value

	AND	r12, r6, r5		@ r12 = .S......S......S......
	SUB	r12,r12,r12,LSR #8	@ r12 = ..SSSSSS..SSSSS.SSSSSS
	ORR	r6, r6, r12		@ r6 |= ..SSSSSS..SSSSS.SSSSSS
	BIC	r12,r5, r6, LSR #1	@ r12 = .o......o......o......
	ADD	r6, r6, r12,LSR #8	@ r6  = fixed value
	B	return202
fix203:
	@ r7 and r6 are the values, at least one of which has overflowed
	@ r12 = r7 & mask = .s......s......s......
	SUB	r12,r12,r12,LSR #8	@ r12 = ..SSSSSS.SSSSSS.SSSSSS
	ORR	r7, r7, r12		@ r7 |= ..SSSSSS.SSSSSS.SSSSSS
	BIC	r12,r5, r7, LSR #1	@ r12 = .o......o......o......
	ADD	r7, r7, r12,LSR #8	@ r7  = fixed value

	AND	r12, r6, r5		@ r12 = .S......S......S......
	SUB	r12,r12,r12,LSR #8	@ r12 = ..SSSSSS.SSSSSS.SSSSSS
	ORR	r6, r6, r12		@ r6 |= ..SSSSSS.SSSSSS.SSSSSS
	BIC	r12,r5, r6, LSR #1	@ r12 = .o......o......o......
	ADD	r6, r6, r12,LSR #8	@ r6  = fixed value
	B	return203
fix204:
	@ r7 and r6 are the values, at least one of which has overflowed
	@ r12 = r7 & mask = .s......s......s......
	SUB	r12,r12,r12,LSR #8	@ r12 = ..SSSSSS.SSSSSS.SSSSSS
	ORR	r7, r7, r12		@ r7 |= ..SSSSSS.SSSSSS.SSSSSS
	BIC	r12,r5, r7, LSR #1	@ r12 = .o......o......o......
	ADD	r7, r7, r12,LSR #8	@ r7  = fixed value

	AND	r12, r6, r5		@ r12 = .S......S......S......
	SUB	r12,r12,r12,LSR #8	@ r12 = ..SSSSSS.SSSSSS.SSSSSS
	ORR	r6, r6, r12		@ r6 |= ..SSSSSS.SSSSSS.SSSSSS
	BIC	r12,r5, r6, LSR #1	@ r12 = .o......o......o......
	ADD	r6, r6, r12,LSR #8	@ r6  = fixed value
	B	return204
fix205:
	@ r6 is the value, which has has overflowed
	@ r12 = r7 & mask = .s......s......s......
	SUB	r12,r12,r12,LSR #8	@ r12 = ..SSSSSS.SSSSSS.SSSSSS
	ORR	r6, r6, r12		@ r6 |= ..SSSSSS.SSSSSS.SSSSSS
	BIC	r12,r5, r6, LSR #1	@ r12 = .o......o......o......
	ADD	r6, r6, r12,LSR #8	@ r6  = fixed value
	B	return205

@------------------------------------------------------------------------
asm3:
	@  Dither: 3 0
	@          1 2
	LDR	r11,[r13,#9*4]		@ r11= width
	SUBS	r8, r8, #1
	BLT	end
	BEQ	trail_row3
yloop3:
	SUB	r8, r8, r11,LSL #16	@ r8 = height-(width<<16)
	ADDS	r8, r8, #1<<16		@ if (width == 1)
	BGE	trail_pair3		@    just do 1 column
xloop3:
	LDRB	r11,[r2], #1		@ r11 = u  = *u_ptr++
	LDRB	r12,[r3], #1		@ r12 = v  = *v_ptr++
	LDRB	r7, [r1, r10]		@ r7  = y2 = y_ptr[stride]
	LDRB	r6, [r1], #1		@ r6  = y0 = *y_ptr++
	ADD	r11,r11,#256
	ADD	r12,r12,#512
	LDR	r11,[r14,r11,LSL #2]	@ r11 = u  = u_table[u]
	LDR	r12,[r14,r12,LSL #2]	@ r12 = v  = v_table[v]
	LDR	r7, [r14,r7, LSL #2]	@ r7  = y2 = y_table[y2]
	LDR	r6, [r14,r6, LSL #2]	@ r6  = y0 = y_table[y0]
	ADD	r11,r11,r12		@ r11 = uv = u+v

	ADD	r12,r11,r5, LSR #DITH1
	ADD	r7, r7, r12		@ r7  = y2 + uv + dither1
	ADD	r6, r6, r12		@ r6  = y0 + uv + dither1
	ADD	r6, r6, r5, LSR #DITH2	@ r6  = y0 + uv + dither3
	ANDS	r12,r7, r5
	TSTEQ	r6, r5
	BNE	fix301
return301:
	AND	r7, r4, r7, LSR #3
	ORR	r7, r7, r7, LSR #16
	STRH	r7, [r0, r9]
	AND	r6, r4, r6, LSR #3
	LDRB	r12,[r1, r10]		@ r12 = y3 = y_ptr[stride]
	LDRB	r7, [r1], #1		@ r6  = y1 = *y_ptr++
	ORR	r6, r6, r6, LSR #16
	LDR	r12,[r14, r12,LSL #2]	@ r7  = y3 = y_table[y2]
	STRH	r6, [r0], #2
	LDR	r6, [r14, r7, LSL #2]	@ r6  = y1 = y_table[y0]

	ADD	r7, r12,r11		@ r7  = y3 + uv
	ADD	r7, r7, r5, LSR #DITH2	@ r7  = y3 + uv + dither2
	ADD	r6, r6, r11		@ r6  = y1 + uv
	ANDS	r12,r7, r5
	TSTEQ	r6, r5
	BNE	fix302
return302:
	AND	r7, r4, r7, LSR #3
	AND	r6, r4, r6, LSR #3
	ORR	r7, r7, r7, LSR #16
	ORR	r6, r6, r6, LSR #16
	STRH	r7, [r0, r9]
	STRH	r6, [r0], #2
	ADDS	r8, r8, #2<<16
	BLT	xloop3
	MOVS	r8, r8, LSL #16		@ Clear the top 16 bits of r8
	MOV	r8, r8, LSR #16		@ If the C bit is clear we still have
	BCC	trail_pair3		@ 1 more pixel pair to do
end_xloop3:
	LDR	r11,[r13,#9*4]		@ r11= width
	LDR	r12,[r13,#12*4]		@ r12= uv_stride
	ADD	r0, r0, r9, LSL #1
	SUB	r0, r0, r11,LSL #1
	ADD	r1, r1, r10,LSL #1
	SUB	r1, r1, r11
	SUB	r2, r2, r11,LSR #1
	SUB	r3, r3, r11,LSR #1
	ADD	r2, r2, r12
	ADD	r3, r3, r12

	SUBS	r8, r8, #2
	BGT	yloop3

	LDMLTFD	r13!,{r4-r11,pc}
trail_row3:
	@ We have a row of pixels left to do
	SUB	r8, r8, r11,LSL #16	@ r8 = height-(width<<16)
	ADDS	r8, r8, #1<<16		@ if (width == 1)
	BGE	trail_pix3		@    just do 1 pixel
xloop32:
	LDRB	r11,[r2], #1		@ r11 = u  = *u_ptr++
	LDRB	r12,[r3], #1		@ r12 = v  = *v_ptr++
	LDRB	r6, [r1], #1		@ r6  = y0 = *y_ptr++
	LDRB	r7, [r1], #1		@ r7  = y1 = *y_ptr++
	ADD	r11,r11,#256
	ADD	r12,r12,#512
	LDR	r11,[r14,r11,LSL #2]	@ r11 = u  = u_table[u]
	LDR	r12,[r14,r12,LSL #2]	@ r12 = v  = v_table[v]
	LDR	r7, [r14,r7, LSL #2]	@ r7  = y1 = y_table[y1]
	LDR	r6, [r14,r6, LSL #2]	@ r6  = y0 = y_table[y0]
	ADD	r11,r11,r12		@ r11 = uv = u+v

	ADD	r6, r6, r11		@ r6  = y0 + uv
	ADD	r6, r6, r5, LSR #DITH1	@ r6  = y0 + uv + dither1
	ADD	r6, r6, r5, LSR #DITH2	@ r6  = y0 + uv + dither3
	ADD	r7, r7, r11		@ r7  = y1 + uv
	ANDS	r12,r7, r5
	TSTEQ	r6, r5
	BNE	fix304
return304:
	AND	r6, r4, r6, LSR #3
	ORR	r6, r6, r6, LSR #16
	STRH	r6, [r0], #2
	AND	r7, r4, r7, LSR #3
	ORR	r7, r7, r7, LSR #16
	STRH	r7, [r0], #2
	ADDS	r8, r8, #2<<16
	BLT	xloop32
	MOVS	r8, r8, LSL #16		@ Clear the top 16 bits of r8
	MOV	r8, r8, LSR #16		@ If the C bit is clear we still have
	BCC	trail_pix3		@ 1 more pixel pair to do

	LDMFD	r13!,{r4-r11,pc}
trail_pix3:
	@ We have a single extra pixel to do
	LDRB	r11,[r2], #1		@ r11 = u  = *u_ptr++
	LDRB	r12,[r3], #1		@ r12 = v  = *v_ptr++
	LDRB	r6, [r1], #1		@ r6  = y0 = *y_ptr++
	ADD	r11,r11,#256
	ADD	r12,r12,#512
	LDR	r11,[r14,r11,LSL #2]	@ r11 = u  = u_table[u]
	LDR	r12,[r14,r12,LSL #2]	@ r12 = v  = v_table[v]
	LDR	r6, [r14,r6, LSL #2]	@ r6  = y0 = y_table[y0]
	ADD	r11,r11,r12		@ r11 = uv = u+v

	ADD	r11,r11,r5, LSR #DITH1
	ADD	r11,r11,r5, LSR #DITH2
	ADD	r6, r6, r11		@ r6  = y0 + uv + dither3
	ANDS	r12,r6, r5
	BNE	fix305
return305:
	AND	r6, r4, r6, LSR #3
	ORR	r6, r6, r6, LSR #16
	STRH	r6, [r0], #2

	LDMFD	r13!,{r4-r11,pc}

trail_pair3:
	@ We have a pair of pixels left to do
	LDRB	r11,[r2]		@ r11 = u  = *u_ptr++
	LDRB	r12,[r3]		@ r12 = v  = *v_ptr++
	LDRB	r7, [r1, r10]		@ r7  = y2 = y_ptr[stride]
	LDRB	r6, [r1], #1		@ r6  = y0 = *y_ptr++
	ADD	r11,r11,#256
	ADD	r12,r12,#512
	LDR	r11,[r14,r11,LSL #2]	@ r11 = u  = u_table[u]
	LDR	r12,[r14,r12,LSL #2]	@ r12 = v  = v_table[v]
	LDR	r7, [r14,r7, LSL #2]	@ r7  = y2 = y_table[y2]
	LDR	r6, [r14,r6, LSL #2]	@ r6  = y0 = y_table[y0]
	ADD	r11,r11,r12		@ r11 = uv = u+v

	ADD	r12,r11,r5, LSR #DITH1
	ADD	r7, r7, r12		@ r7  = y2 + uv + dither1
	ADD	r6, r6, r12		@ r6  = y0 + uv + dither1
	ADD	r6, r6, r5, LSR #DITH2	@ r6  = y0 + uv + dither3
	ANDS	r12,r7, r5
	TSTEQ	r6, r5
	BNE	fix303
return303:
	AND	r7, r4, r7, LSR #3
	ORR	r7, r7, r7, LSR #16
	STRH	r7, [r0, r9]
	AND	r6, r4, r6, LSR #3
	ORR	r6, r6, r6, LSR #16
	STRH	r6, [r0], #2
	B	end_xloop3
fix301:
	@ r7 and r6 are the values, at least one of which has overflowed
	@ r12 = r7 & mask = .s......s......s......
	SUB	r12,r12,r12,LSR #8	@ r12 = ..SSSSSS.SSSSSS.SSSSSS
	ORR	r7, r7, r12		@ r7 |= ..SSSSSS.SSSSSS.SSSSSS
	BIC	r12,r5, r7, LSR #1	@ r12 = .o......o......o......
	ADD	r7, r7, r12,LSR #8	@ r7  = fixed value

	AND	r12, r6, r5		@ r12 = .S......S......S......
	SUB	r12,r12,r12,LSR #8	@ r12 = ..SSSSSS.SSSSSS.SSSSSS
	ORR	r6, r6, r12		@ r6 |= ..SSSSSS.SSSSSS.SSSSSS
	BIC	r12,r5, r6, LSR #1	@ r12 = .o......o......o......
	ADD	r6, r6, r12,LSR #8	@ r6  = fixed value
	B	return301
fix302:
	@ r7 and r6 are the values, at least one of which has overflowed
	@ r12 = r7 & mask = .s......s......s......
	SUB	r12,r12,r12,LSR #8	@ r12 = ..SSSSSS.SSSSSS.SSSSSS
	ORR	r7, r7, r12		@ r7 |= ..SSSSSS.SSSSSS.SSSSSS
	BIC	r12,r5, r7, LSR #1	@ r12 = .o......o......o......
	ADD	r7, r7, r12,LSR #8	@ r7  = fixed value

	AND	r12, r6, r5		@ r12 = .S......S......S......
	SUB	r12,r12,r12,LSR #8	@ r12 = ..SSSSSS..SSSSS.SSSSSS
	ORR	r6, r6, r12		@ r6 |= ..SSSSSS..SSSSS.SSSSSS
	BIC	r12,r5, r6, LSR #1	@ r12 = .o......o......o......
	ADD	r6, r6, r12,LSR #8	@ r6  = fixed value
	B	return302
fix303:
	@ r7 and r6 are the values, at least one of which has overflowed
	@ r12 = r7 & mask = .s......s......s......
	SUB	r12,r12,r12,LSR #8	@ r12 = ..SSSSSS.SSSSSS.SSSSSS
	ORR	r7, r7, r12		@ r7 |= ..SSSSSS.SSSSSS.SSSSSS
	BIC	r12,r5, r7, LSR #1	@ r12 = .o......o......o......
	ADD	r7, r7, r12,LSR #8	@ r7  = fixed value

	AND	r12, r6, r5		@ r12 = .S......S......S......
	SUB	r12,r12,r12,LSR #8	@ r12 = ..SSSSSS.SSSSSS.SSSSSS
	ORR	r6, r6, r12		@ r6 |= ..SSSSSS.SSSSSS.SSSSSS
	BIC	r12,r5, r6, LSR #1	@ r12 = .o......o......o......
	ADD	r6, r6, r12,LSR #8	@ r6  = fixed value
	B	return303
fix304:
	@ r7 and r6 are the values, at least one of which has overflowed
	@ r12 = r7 & mask = .s......s......s......
	SUB	r12,r12,r12,LSR #8	@ r12 = ..SSSSSS.SSSSSS.SSSSSS
	ORR	r7, r7, r12		@ r7 |= ..SSSSSS.SSSSSS.SSSSSS
	BIC	r12,r5, r7, LSR #1	@ r12 = .o......o......o......
	ADD	r7, r7, r12,LSR #8	@ r7  = fixed value

	AND	r12, r6, r5		@ r12 = .S......S......S......
	SUB	r12,r12,r12,LSR #8	@ r12 = ..SSSSSS.SSSSSS.SSSSSS
	ORR	r6, r6, r12		@ r6 |= ..SSSSSS.SSSSSS.SSSSSS
	BIC	r12,r5, r6, LSR #1	@ r12 = .o......o......o......
	ADD	r6, r6, r12,LSR #8	@ r6  = fixed value
	B	return304
fix305:
	@ r6 is the value, which has has overflowed
	@ r12 = r7 & mask = .s......s......s......
	SUB	r12,r12,r12,LSR #8	@ r12 = ..SSSSSS.SSSSSS.SSSSSS
	ORR	r6, r6, r12		@ r6 |= ..SSSSSS.SSSSSS.SSSSSS
	BIC	r12,r5, r6, LSR #1	@ r12 = .o......o......o......
	ADD	r6, r6, r12,LSR #8	@ r6  = fixed value
	B	return305


yuv2rgb_table:
y_table:
        .word 0x7FFFFFED
        .word 0x7FFFFFEF
        .word 0x7FFFFFF0
        .word 0x7FFFFFF1
        .word 0x7FFFFFF2
        .word 0x7FFFFFF3
        .word 0x7FFFFFF4
        .word 0x7FFFFFF6
        .word 0x7FFFFFF7
        .word 0x7FFFFFF8
        .word 0x7FFFFFF9
        .word 0x7FFFFFFA
        .word 0x7FFFFFFB
        .word 0x7FFFFFFD
        .word 0x7FFFFFFE
        .word 0x7FFFFFFF
        .word 0x80000000
        .word 0x80400801
        .word 0x80A01002
        .word 0x80E01803
        .word 0x81202805
        .word 0x81803006
        .word 0x81C03807
        .word 0x82004008
        .word 0x82604809
        .word 0x82A0500A
        .word 0x82E0600C
        .word 0x8340680D
        .word 0x8380700E
        .word 0x83C0780F
        .word 0x84208010
        .word 0x84608811
        .word 0x84A09813
        .word 0x8500A014
        .word 0x8540A815
        .word 0x8580B016
        .word 0x85E0B817
        .word 0x8620C018
        .word 0x8660D01A
        .word 0x86C0D81B
        .word 0x8700E01C
        .word 0x8740E81D
        .word 0x87A0F01E
        .word 0x87E0F81F
        .word 0x88210821
        .word 0x88811022
        .word 0x88C11823
        .word 0x89012024
        .word 0x89412825
        .word 0x89A13026
        .word 0x89E14028
        .word 0x8A214829
        .word 0x8A81502A
        .word 0x8AC1582B
        .word 0x8B01602C
        .word 0x8B61682D
        .word 0x8BA1782F
        .word 0x8BE18030
        .word 0x8C418831
        .word 0x8C819032
        .word 0x8CC19833
        .word 0x8D21A034
        .word 0x8D61B036
        .word 0x8DA1B837
        .word 0x8E01C038
        .word 0x8E41C839
        .word 0x8E81D03A
        .word 0x8EE1D83B
        .word 0x8F21E83D
        .word 0x8F61F03E
        .word 0x8FC1F83F
        .word 0x90020040
        .word 0x90420841
        .word 0x90A21042
        .word 0x90E22044
        .word 0x91222845
        .word 0x91823046
        .word 0x91C23847
        .word 0x92024048
        .word 0x92624849
        .word 0x92A2504A
        .word 0x92E2604C
        .word 0x9342684D
        .word 0x9382704E
        .word 0x93C2784F
        .word 0x94228050
        .word 0x94628851
        .word 0x94A29853
        .word 0x9502A054
        .word 0x9542A855
        .word 0x9582B056
        .word 0x95E2B857
        .word 0x9622C058
        .word 0x9662D05A
        .word 0x96C2D85B
        .word 0x9702E05C
        .word 0x9742E85D
        .word 0x97A2F05E
        .word 0x97E2F85F
        .word 0x98230861
        .word 0x98831062
        .word 0x98C31863
        .word 0x99032064
        .word 0x99632865
        .word 0x99A33066
        .word 0x99E34068
        .word 0x9A434869
        .word 0x9A83506A
        .word 0x9AC3586B
        .word 0x9B23606C
        .word 0x9B63686D
        .word 0x9BA3786F
        .word 0x9BE38070
        .word 0x9C438871
        .word 0x9C839072
        .word 0x9CC39873
        .word 0x9D23A074
        .word 0x9D63B076
        .word 0x9DA3B877
        .word 0x9E03C078
        .word 0x9E43C879
        .word 0x9E83D07A
        .word 0x9EE3D87B
        .word 0x9F23E87D
        .word 0x9F63F07E
        .word 0x9FC3F87F
        .word 0xA0040080
        .word 0xA0440881
        .word 0xA0A41082
        .word 0xA0E42084
        .word 0xA1242885
        .word 0xA1843086
        .word 0xA1C43887
        .word 0xA2044088
        .word 0xA2644889
        .word 0xA2A4588B
        .word 0xA2E4608C
        .word 0xA344688D
        .word 0xA384708E
        .word 0xA3C4788F
        .word 0xA4248090
        .word 0xA4649092
        .word 0xA4A49893
        .word 0xA504A094
        .word 0xA544A895
        .word 0xA584B096
        .word 0xA5E4B897
        .word 0xA624C098
        .word 0xA664D09A
        .word 0xA6C4D89B
        .word 0xA704E09C
        .word 0xA744E89D
        .word 0xA7A4F09E
        .word 0xA7E4F89F
        .word 0xA82508A1
        .word 0xA88510A2
        .word 0xA8C518A3
        .word 0xA90520A4
        .word 0xA96528A5
        .word 0xA9A530A6
        .word 0xA9E540A8
        .word 0xAA4548A9
        .word 0xAA8550AA
        .word 0xAAC558AB
        .word 0xAB2560AC
        .word 0xAB6568AD
        .word 0xABA578AF
        .word 0xAC0580B0
        .word 0xAC4588B1
        .word 0xAC8590B2
        .word 0xACE598B3
        .word 0xAD25A0B4
        .word 0xAD65B0B6
        .word 0xADA5B8B7
        .word 0xAE05C0B8
        .word 0xAE45C8B9
        .word 0xAE85D0BA
        .word 0xAEE5D8BB
        .word 0xAF25E8BD
        .word 0xAF65F0BE
        .word 0xAFC5F8BF
        .word 0xB00600C0
        .word 0xB04608C1
        .word 0xB0A610C2
        .word 0xB0E620C4
        .word 0xB12628C5
        .word 0xB18630C6
        .word 0xB1C638C7
        .word 0xB20640C8
        .word 0xB26648C9
        .word 0xB2A658CB
        .word 0xB2E660CC
        .word 0xB34668CD
        .word 0xB38670CE
        .word 0xB3C678CF
        .word 0xB42680D0
        .word 0xB46690D2
        .word 0xB4A698D3
        .word 0xB506A0D4
        .word 0xB546A8D5
        .word 0xB586B0D6
        .word 0xB5E6B8D7
        .word 0xB626C8D9
        .word 0xB666D0DA
        .word 0xB6C6D8DB
        .word 0xB706E0DC
        .word 0xB746E8DD
        .word 0xB7A6F0DE
        .word 0xB7E6F8DF
        .word 0xB82708E1
        .word 0xB88710E2
        .word 0xB8C718E3
        .word 0xB90720E4
        .word 0xB96728E5
        .word 0xB9A730E6
        .word 0xB9E740E8
        .word 0xBA4748E9
        .word 0xBA8750EA
        .word 0xBAC758EB
        .word 0xBB2760EC
        .word 0xBB6768ED
        .word 0xBBA778EF
        .word 0xBC0780F0
        .word 0xBC4788F1
        .word 0xBC8790F2
        .word 0xBCE798F3
        .word 0xBD27A0F4
        .word 0xBD67B0F6
        .word 0xBDC7B8F7
        .word 0xBE07C0F8
        .word 0xBE47C8F9
        .word 0xBEA7D0FA
        .word 0xBEE7D8FB
        .word 0xBF27E8FD
        .word 0xBF87F0FE
        .word 0xBFC7F8FF
        .word 0xC0080100
        .word 0xC0480901
        .word 0xC0A81102
        .word 0xC0E82104
        .word 0xC0E82104
        .word 0xC0E82104
        .word 0xC0E82104
        .word 0xC0E82104
        .word 0xC0E82104
        .word 0xC0E82104
        .word 0xC0E82104
        .word 0xC0E82104
        .word 0xC0E82104
        .word 0xC0E82104
        .word 0xC0E82104
        .word 0xC0E82104
        .word 0xC0E82104
        .word 0xC0E82104
        .word 0xC0E82104
        .word 0xC0E82104
u_table:
        .word 0x0C400103
        .word 0x0C200105
        .word 0x0C200107
        .word 0x0C000109
        .word 0x0BE0010B
        .word 0x0BC0010D
        .word 0x0BA0010F
        .word 0x0BA00111
        .word 0x0B800113
        .word 0x0B600115
        .word 0x0B400117
        .word 0x0B400119
        .word 0x0B20011B
        .word 0x0B00011D
        .word 0x0AE0011F
        .word 0x0AE00121
        .word 0x0AC00123
        .word 0x0AA00125
        .word 0x0A800127
        .word 0x0A600129
        .word 0x0A60012B
        .word 0x0A40012D
        .word 0x0A20012F
        .word 0x0A000131
        .word 0x0A000132
        .word 0x09E00134
        .word 0x09C00136
        .word 0x09A00138
        .word 0x09A0013A
        .word 0x0980013C
        .word 0x0960013E
        .word 0x09400140
        .word 0x09400142
        .word 0x09200144
        .word 0x09000146
        .word 0x08E00148
        .word 0x08C0014A
        .word 0x08C0014C
        .word 0x08A0014E
        .word 0x08800150
        .word 0x08600152
        .word 0x08600154
        .word 0x08400156
        .word 0x08200158
        .word 0x0800015A
        .word 0x0800015C
        .word 0x07E0015E
        .word 0x07C00160
        .word 0x07A00162
        .word 0x07A00164
        .word 0x07800166
        .word 0x07600168
        .word 0x0740016A
        .word 0x0720016C
        .word 0x0720016E
        .word 0x07000170
        .word 0x06E00172
        .word 0x06C00174
        .word 0x06C00176
        .word 0x06A00178
        .word 0x0680017A
        .word 0x0660017C
        .word 0x0660017E
        .word 0x06400180
        .word 0x06200182
        .word 0x06000184
        .word 0x05E00185
        .word 0x05E00187
        .word 0x05C00189
        .word 0x05A0018B
        .word 0x0580018D
        .word 0x0580018F
        .word 0x05600191
        .word 0x05400193
        .word 0x05200195
        .word 0x05200197
        .word 0x05000199
        .word 0x04E0019B
        .word 0x04C0019D
        .word 0x04C0019F
        .word 0x04A001A1
        .word 0x048001A3
        .word 0x046001A5
        .word 0x044001A7
        .word 0x044001A9
        .word 0x042001AB
        .word 0x040001AD
        .word 0x03E001AF
        .word 0x03E001B1
        .word 0x03C001B3
        .word 0x03A001B5
        .word 0x038001B7
        .word 0x038001B9
        .word 0x036001BB
        .word 0x034001BD
        .word 0x032001BF
        .word 0x032001C1
        .word 0x030001C3
        .word 0x02E001C5
        .word 0x02C001C7
        .word 0x02A001C9
        .word 0x02A001CB
        .word 0x028001CD
        .word 0x026001CF
        .word 0x024001D1
        .word 0x024001D3
        .word 0x022001D5
        .word 0x020001D7
        .word 0x01E001D8
        .word 0x01E001DA
        .word 0x01C001DC
        .word 0x01A001DE
        .word 0x018001E0
        .word 0x016001E2
        .word 0x016001E4
        .word 0x014001E6
        .word 0x012001E8
        .word 0x010001EA
        .word 0x010001EC
        .word 0x00E001EE
        .word 0x00C001F0
        .word 0x00A001F2
        .word 0x00A001F4
        .word 0x008001F6
        .word 0x006001F8
        .word 0x004001FA
        .word 0x004001FC
        .word 0x002001FE
        .word 0x00000200
        .word 0xFFE00202
        .word 0xFFC00204
        .word 0xFFC00206
        .word 0xFFA00208
        .word 0xFF80020A
        .word 0xFF60020C
        .word 0xFF60020E
        .word 0xFF400210
        .word 0xFF200212
        .word 0xFF000214
        .word 0xFF000216
        .word 0xFEE00218
        .word 0xFEC0021A
        .word 0xFEA0021C
        .word 0xFEA0021E
        .word 0xFE800220
        .word 0xFE600222
        .word 0xFE400224
        .word 0xFE200226
        .word 0xFE200228
        .word 0xFE000229
        .word 0xFDE0022B
        .word 0xFDC0022D
        .word 0xFDC0022F
        .word 0xFDA00231
        .word 0xFD800233
        .word 0xFD600235
        .word 0xFD600237
        .word 0xFD400239
        .word 0xFD20023B
        .word 0xFD00023D
        .word 0xFCE0023F
        .word 0xFCE00241
        .word 0xFCC00243
        .word 0xFCA00245
        .word 0xFC800247
        .word 0xFC800249
        .word 0xFC60024B
        .word 0xFC40024D
        .word 0xFC20024F
        .word 0xFC200251
        .word 0xFC000253
        .word 0xFBE00255
        .word 0xFBC00257
        .word 0xFBC00259
        .word 0xFBA0025B
        .word 0xFB80025D
        .word 0xFB60025F
        .word 0xFB400261
        .word 0xFB400263
        .word 0xFB200265
        .word 0xFB000267
        .word 0xFAE00269
        .word 0xFAE0026B
        .word 0xFAC0026D
        .word 0xFAA0026F
        .word 0xFA800271
        .word 0xFA800273
        .word 0xFA600275
        .word 0xFA400277
        .word 0xFA200279
        .word 0xFA20027B
        .word 0xFA00027C
        .word 0xF9E0027E
        .word 0xF9C00280
        .word 0xF9A00282
        .word 0xF9A00284
        .word 0xF9800286
        .word 0xF9600288
        .word 0xF940028A
        .word 0xF940028C
        .word 0xF920028E
        .word 0xF9000290
        .word 0xF8E00292
        .word 0xF8E00294
        .word 0xF8C00296
        .word 0xF8A00298
        .word 0xF880029A
        .word 0xF860029C
        .word 0xF860029E
        .word 0xF84002A0
        .word 0xF82002A2
        .word 0xF80002A4
        .word 0xF80002A6
        .word 0xF7E002A8
        .word 0xF7C002AA
        .word 0xF7A002AC
        .word 0xF7A002AE
        .word 0xF78002B0
        .word 0xF76002B2
        .word 0xF74002B4
        .word 0xF74002B6
        .word 0xF72002B8
        .word 0xF70002BA
        .word 0xF6E002BC
        .word 0xF6C002BE
        .word 0xF6C002C0
        .word 0xF6A002C2
        .word 0xF68002C4
        .word 0xF66002C6
        .word 0xF66002C8
        .word 0xF64002CA
        .word 0xF62002CC
        .word 0xF60002CE
        .word 0xF60002CF
        .word 0xF5E002D1
        .word 0xF5C002D3
        .word 0xF5A002D5
        .word 0xF5A002D7
        .word 0xF58002D9
        .word 0xF56002DB
        .word 0xF54002DD
        .word 0xF52002DF
        .word 0xF52002E1
        .word 0xF50002E3
        .word 0xF4E002E5
        .word 0xF4C002E7
        .word 0xF4C002E9
        .word 0xF4A002EB
        .word 0xF48002ED
        .word 0xF46002EF
        .word 0xF46002F1
        .word 0xF44002F3
        .word 0xF42002F5
        .word 0xF40002F7
        .word 0xF3E002F9
        .word 0xF3E002FB
v_table:
        .word 0x1A09A000
        .word 0x19E9A800
        .word 0x19A9B800
        .word 0x1969C800
        .word 0x1949D000
        .word 0x1909E000
        .word 0x18C9E800
        .word 0x18A9F800
        .word 0x186A0000
        .word 0x182A1000
        .word 0x180A2000
        .word 0x17CA2800
        .word 0x17AA3800
        .word 0x176A4000
        .word 0x172A5000
        .word 0x170A6000
        .word 0x16CA6800
        .word 0x168A7800
        .word 0x166A8000
        .word 0x162A9000
        .word 0x160AA000
        .word 0x15CAA800
        .word 0x158AB800
        .word 0x156AC000
        .word 0x152AD000
        .word 0x14EAE000
        .word 0x14CAE800
        .word 0x148AF800
        .word 0x146B0000
        .word 0x142B1000
        .word 0x13EB2000
        .word 0x13CB2800
        .word 0x138B3800
        .word 0x134B4000
        .word 0x132B5000
        .word 0x12EB6000
        .word 0x12CB6800
        .word 0x128B7800
        .word 0x124B8000
        .word 0x122B9000
        .word 0x11EBA000
        .word 0x11ABA800
        .word 0x118BB800
        .word 0x114BC000
        .word 0x112BD000
        .word 0x10EBE000
        .word 0x10ABE800
        .word 0x108BF800
        .word 0x104C0000
        .word 0x100C1000
        .word 0x0FEC2000
        .word 0x0FAC2800
        .word 0x0F8C3800
        .word 0x0F4C4000
        .word 0x0F0C5000
        .word 0x0EEC5800
        .word 0x0EAC6800
        .word 0x0E6C7800
        .word 0x0E4C8000
        .word 0x0E0C9000
        .word 0x0DEC9800
        .word 0x0DACA800
        .word 0x0D6CB800
        .word 0x0D4CC000
        .word 0x0D0CD000
        .word 0x0CCCD800
        .word 0x0CACE800
        .word 0x0C6CF800
        .word 0x0C4D0000
        .word 0x0C0D1000
        .word 0x0BCD1800
        .word 0x0BAD2800
        .word 0x0B6D3800
        .word 0x0B2D4000
        .word 0x0B0D5000
        .word 0x0ACD5800
        .word 0x0AAD6800
        .word 0x0A6D7800
        .word 0x0A2D8000
        .word 0x0A0D9000
        .word 0x09CD9800
        .word 0x098DA800
        .word 0x096DB800
        .word 0x092DC000
        .word 0x090DD000
        .word 0x08CDD800
        .word 0x088DE800
        .word 0x086DF800
        .word 0x082E0000
        .word 0x07EE1000
        .word 0x07CE1800
        .word 0x078E2800
        .word 0x076E3800
        .word 0x072E4000
        .word 0x06EE5000
        .word 0x06CE5800
        .word 0x068E6800
        .word 0x064E7800
        .word 0x062E8000
        .word 0x05EE9000
        .word 0x05CE9800
        .word 0x058EA800
        .word 0x054EB800
        .word 0x052EC000
        .word 0x04EED000
        .word 0x04AED800
        .word 0x048EE800
        .word 0x044EF000
        .word 0x042F0000
        .word 0x03EF1000
        .word 0x03AF1800
        .word 0x038F2800
        .word 0x034F3000
        .word 0x030F4000
        .word 0x02EF5000
        .word 0x02AF5800
        .word 0x028F6800
        .word 0x024F7000
        .word 0x020F8000
        .word 0x01EF9000
        .word 0x01AF9800
        .word 0x016FA800
        .word 0x014FB000
        .word 0x010FC000
        .word 0x00EFD000
        .word 0x00AFD800
        .word 0x006FE800
        .word 0x004FF000
        .word 0x00100000
        .word 0xFFD01000
        .word 0xFFB01800
        .word 0xFF702800
        .word 0xFF303000
        .word 0xFF104000
        .word 0xFED05000
        .word 0xFEB05800
        .word 0xFE706800
        .word 0xFE307000
        .word 0xFE108000
        .word 0xFDD09000
        .word 0xFD909800
        .word 0xFD70A800
        .word 0xFD30B000
        .word 0xFD10C000
        .word 0xFCD0D000
        .word 0xFC90D800
        .word 0xFC70E800
        .word 0xFC30F000
        .word 0xFBF10000
        .word 0xFBD11000
        .word 0xFB911800
        .word 0xFB712800
        .word 0xFB313000
        .word 0xFAF14000
        .word 0xFAD14800
        .word 0xFA915800
        .word 0xFA516800
        .word 0xFA317000
        .word 0xF9F18000
        .word 0xF9D18800
        .word 0xF9919800
        .word 0xF951A800
        .word 0xF931B000
        .word 0xF8F1C000
        .word 0xF8B1C800
        .word 0xF891D800
        .word 0xF851E800
        .word 0xF831F000
        .word 0xF7F20000
        .word 0xF7B20800
        .word 0xF7921800
        .word 0xF7522800
        .word 0xF7123000
        .word 0xF6F24000
        .word 0xF6B24800
        .word 0xF6925800
        .word 0xF6526800
        .word 0xF6127000
        .word 0xF5F28000
        .word 0xF5B28800
        .word 0xF5729800
        .word 0xF552A800
        .word 0xF512B000
        .word 0xF4F2C000
        .word 0xF4B2C800
        .word 0xF472D800
        .word 0xF452E800
        .word 0xF412F000
        .word 0xF3D30000
        .word 0xF3B30800
        .word 0xF3731800
        .word 0xF3532800
        .word 0xF3133000
        .word 0xF2D34000
        .word 0xF2B34800
        .word 0xF2735800
        .word 0xF2336800
        .word 0xF2137000
        .word 0xF1D38000
        .word 0xF1B38800
        .word 0xF1739800
        .word 0xF133A800
        .word 0xF113B000
        .word 0xF0D3C000
        .word 0xF093C800
        .word 0xF073D800
        .word 0xF033E000
        .word 0xF013F000
        .word 0xEFD40000
        .word 0xEF940800
        .word 0xEF741800
        .word 0xEF342000
        .word 0xEEF43000
        .word 0xEED44000
        .word 0xEE944800
        .word 0xEE745800
        .word 0xEE346000
        .word 0xEDF47000
        .word 0xEDD48000
        .word 0xED948800
        .word 0xED549800
        .word 0xED34A000
        .word 0xECF4B000
        .word 0xECD4C000
        .word 0xEC94C800
        .word 0xEC54D800
        .word 0xEC34E000
        .word 0xEBF4F000
        .word 0xEBB50000
        .word 0xEB950800
        .word 0xEB551800
        .word 0xEB352000
        .word 0xEAF53000
        .word 0xEAB54000
        .word 0xEA954800
        .word 0xEA555800
        .word 0xEA156000
        .word 0xE9F57000
        .word 0xE9B58000
        .word 0xE9958800
        .word 0xE9559800
        .word 0xE915A000
        .word 0xE8F5B000
        .word 0xE8B5C000
        .word 0xE875C800
        .word 0xE855D800
        .word 0xE815E000
        .word 0xE7F5F000
        .word 0xE7B60000
        .word 0xE7760800
        .word 0xE7561800
        .word 0xE7162000
        .word 0xE6D63000
        .word 0xE6B64000
        .word 0xE6764800
        .word 0xE6365800

	@ END
