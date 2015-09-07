/* YUV-> RGB conversion code.
 *
 * Copyright (C) 2011 Robin Watts (robin@wss.co.uk) for Pinknoise
 * Productions Ltd.
 *
 * Licensed under the BSD license. See 'COPYING' for details of
 * (non-)warranty.
 */

#include "yuv2rgb/yuv2rgb.h"


// it has to be 420 8888
// Spes has only 420 versions in libtheoraplayer, and I have (in MovieScreen)
//		pretext = new Texture(Gdx.graphics.getWidth(),
// Gdx.graphics.getHeight(), Pixmap.Format.RGBA8888);
// YUV is color coding scheme, and 420 is sampling/storage scheme


void watts (unsigned char* dst_ptr, unsigned char*y_ptr, unsigned char*u_ptr, unsigned char*v_ptr,
		int width, int height, int y_span, int uv_span, int dst_span) {

	yuv420_2_rgb8888 (dst_ptr, (const uint8_t  *)y_ptr,
			  (const uint8_t  *)u_ptr,  (const uint8_t  *)v_ptr,
			width, height, y_span,  uv_span, dst_span,  yuv2rgb565_table, 0);
}


