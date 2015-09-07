/********************************************************************
 *                                                                  *
 * THIS FILE IS PART OF THE Oggeyman  DECODER SOURCE CODE.          *
 * USE, DISTRIBUTION AND REPRODUCTION OF THIS LIBRARY SOURCE IS     *
 * GOVERNED BY A SOURCE LICENSE INCLUDED WITH THIS SOURCE.          *
 * PLEASE READ THESE TERMS BEFORE DISTRIBUTING.                     *
 * (C) 2015 Ivana Mihalek                                           *
 *                                                                  *
 * THE Theora SOURCE CODE IS COPYRIGHT (C) 2002-2009                *
 * by the Xiph.Org Foundation and contributors http://www.xiph.org/ *
 * THE Theorarm Copyright (C) 2009 Robin Watts for                  *
 * Pinknoise Productions Ltd.                                       *
 *                                                                  *
 ********************************************************************/

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


