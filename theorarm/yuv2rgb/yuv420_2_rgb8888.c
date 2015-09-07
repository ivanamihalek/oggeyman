// I need this header of type definitions
#include "yuv2rgb.h"

enum {
	FLAGS = 0x40080100
};

#define READUV(U,V) (tables[256 + (U)] + tables[512 + (V)])
#define READY(Y)    tables[Y]
#define FIXUP(Y)                 \
{                                \
    int tmp = (Y) & FLAGS;       \
    if (tmp != 0)                \
    {                            \
        tmp  -= tmp>>8;          \
        (Y)  |= tmp;             \
        tmp   = FLAGS & ~(Y>>1); \
        (Y)  += tmp>>8;          \
    }                            \
}

// careful here when reordering bytes; watts arranges colors as g, b, r in his 32 bit rep (osGGGGGgggggosBBBBBbbbosRRRRRrrr),
// and then stores into rbg:
//#define STORE(Y,DSTPTR)   (DSTPTR) = ( 0xFF & Y) | (0xFF00 & (Y>>14)) | (0xFF0000 & (Y<<5)) | (0xFF000000 );
// 0xFF     is red
// 0xFF00   is green
// 0xFF0000 is blue
//so insted of watts original, we want b g r a in the increasing byte weight
#define STORE(Y,DSTPTR)   (DSTPTR) =  (0xFF & (Y>>11)) | (0xFF00 & (Y>>14)) | (0xFF0000 & (Y<<16)) | (0xFF000000)


void yuv420_2_rgb8888(uint8_t *dst_ptr_, const uint8_t *y_ptr,
		const uint8_t *u_ptr, const uint8_t *v_ptr, int32_t width,
		int32_t height, int32_t y_span, int32_t uv_span, int32_t dst_span,
		const uint32_t *tables, int32_t dither) {

	uint32_t *dst_ptr = (uint32_t *) (void *) dst_ptr_;
	dst_span >>= 2;

	height -= 1;
	while (height > 0) {
		// these are hacks to re-use these variables as counters
		// this is how we'll do it it assembly later
		height -= width << 16;
		height += 1 << 16; // we could have just said height += (width-1)<<16 - again this way might be easier in assembly
		// Do 2 column pairs
		while (height < 0) {
			uint32_t uv, y0, y1;
			uv = READUV(*u_ptr++, *v_ptr++);
			y1 = uv + READY(y_ptr[y_span]);
			y0 = uv + READY(*y_ptr++);
			FIXUP(y1);
			FIXUP(y0);
			STORE(y1, dst_ptr[dst_span]);
			STORE(y0, *dst_ptr++);
			y1 = uv + READY(y_ptr[y_span]);
			y0 = uv + READY(*y_ptr++);
			FIXUP(y1);
			FIXUP(y0);
			STORE(y1, dst_ptr[dst_span]);
			STORE(y0, *dst_ptr++);
			height += (2 << 16); // we are moving in steps of two
		}
		// if the width is an odd number there is one more pixel we need to take care of
		if ((height >> 16) == 0) {
			// Trailing column pair
			uint32_t uv, y0, y1;

			uv = READUV(*u_ptr, *v_ptr);
			y1 = uv + READY(y_ptr[y_span]);
			y0 = uv + READY(*y_ptr++);
			FIXUP(y1);
			FIXUP(y0);
			STORE(y0, dst_ptr[dst_span]);
			STORE(y1, *dst_ptr++);
		}
		dst_ptr += dst_span * 2 - width;
		y_ptr += y_span * 2 - width;
		u_ptr += uv_span - (width >> 1);
		v_ptr += uv_span - (width >> 1);
		height = (height << 16) >> 16;
		height -= 2; // <========  this is here we move to the next row
	}

	if (height == 0) {
		//Trail row
		height -= width << 16;
		height += 1 << 16;
		while (height < 0) {
			// Do a row pair
			uint32_t uv, y0, y1;

			uv = READUV(*u_ptr++, *v_ptr++);
			y1 = uv + READY(*y_ptr++);
			y0 = uv + READY(*y_ptr++);
			FIXUP(y1);
			FIXUP(y0);
			STORE(y1, *dst_ptr++);
			STORE(y0, *dst_ptr++);
			height += (2 << 16);
		}
		if ((height >> 16) == 0) {
			// Trailing pix
			uint32_t uv, y0;

			uv = READUV(*u_ptr++, *v_ptr++);
			y0 = uv + READY(*y_ptr++);
			FIXUP(y0);
			STORE(y0, *dst_ptr++);
		}
	}
}

