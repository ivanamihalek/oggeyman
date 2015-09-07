/********************************************************************
 *                                                                  *
 * THIS FILE IS PART OF THE Oggeyman  DECODER SOURCE CODE.          *
 * USE, DISTRIBUTION AND REPRODUCTION OF THIS LIBRARY SOURCE IS     *
 * GOVERNED BY A SOURCE LICENSE INCLUDED WITH THIS SOURCE           *
 * IN 'COPYING'. PLEASE READ THESE TERMS BEFORE DISTRIBUTING.       *
 * (C) 2015 Ivana Mihalek                                           *
 *                                                                  *
 * THE Theora SOURCE CODE IS COPYRIGHT (C) 2002-2009                *
 * by the Xiph.Org Foundation and contributors http://www.xiph.org/ *
 * THE Theorarm Copyright (C) 2009 Robin Watts for                  *
 * Pinknoise Productions Ltd.                                       *
 *                                                                  *
 ********************************************************************/

# ifndef OGGSTREAM_H_
# define OGGSTREAM_H_
// get rid of the standard library bcs android does not seem to like it
#   include <sys/time.h>
#   include <stdlib.h>
#   include <stdio.h>
#   include <string.h>


# if ! (defined OSX || defined IOS)
# 	include <malloc.h>
# endif

# include "ogg/ogg.h"
# include "theora/theora.h"
# include "theora/theoradec.h"
#ifdef ANDR
#   include <time.h>
#   include <android/log.h>
#endif

extern "C" void watts  (unsigned char* dst_ptr, unsigned char*y_ptr, unsigned char*u_ptr,
			unsigned char*v_ptr,int width, int height, int y_span, int uv_span,
			int dst_span);


typedef enum  { // for now we'll be using only VF_BGRA
	VF_RGB, VF_BGR, VF_RGBA, VF_BGRA
} VideoFormat;

typedef struct  {
	int y_width;
	int y_height;
	int y_stride;
	int uv_width;
	int uv_height;
	int uv_stride;
	unsigned char *y;
	unsigned char *u;
	unsigned char *v;
} YUVbuffer;

typedef struct {
	void set(int r,int g,int b,int bpp){
		r_offset = r;
		g_offset = g;
		b_offset = b;
		this->bpp =bpp;
	}
	int r_offset;
	int g_offset;
	int b_offset;
	// if bpp=4 we have an alpha channel at offset 4
	int bpp;

} PixelFormat;


class Oggeyman {

public:
     ~Oggeyman();
     Oggeyman();
     //****************************************************************/
     bool init(const char * path);
     bool init(VideoFormat video_format, char * path);
     void timer_restart ();
     void timer_update  ();
     bool shutdown();
     bool seek    ();       // time? frame?
     bool get_next_frame(unsigned char *BGRAbuffer); // this will provide BGRA pixel data for OpenGL texture
     bool fast_forward_to_frame(int frameno);
     double get_packet_time ();

     bool done();
     int width();
     int height();
     void  varcheck();
private:
     static const size_t  IN_CHUNK_SIZE = 4096; //what is the optimum? really reading the whole thing as Jinman does?
     VideoFormat video_format;
     // ogg stuff
     ogg_sync_state    overall_sync_state;
     ogg_stream_state  ogg_theora_stream_state; // ogg stream containing theora
     ogg_page          current_ogg_page;
     ogg_packet        ogg_theora_packet;       //ogg packet containing theora data

     theora_info theo_info;
     theora_comment theo_comment;
     theora_state theo_state;
 
     double last_packet_time; // theora packet, we are not considering any other packets here
     double total_play_time;
     double last_registered_time;

     bool stream_done;
     //Theora decoder supports a post-processing filter that can improve the appearance of the decoded images.
     //TH_DECCTL_GET_PPLEVEL_MAX returns the highest level setting for this post-processor,
     //corresponding to maximum improvement and computational expense.
     //We will use it if we figure out we have enough time.
     int pp_level_max;
     int pp_level;
     int pp_inc;

     // the input file, full path:
     // name
     const char * path;
     // handle do I really need the handle here?
     // apprently FILE* is not a primitve variable (?) bcs it is not initialized
     FILE * infptr;
     // processing the input:
     PixelFormat pixel_format;
     yuv_buffer YUVbuffer;

    //****************************************************************/
     void springtime_cleaning();
     bool parse_headers();
     bool next_packet        (ogg_stream_state *state_ptr, ogg_packet *packet_ptr);
     bool next_theora_packet (ogg_stream_state *state_ptr, ogg_packet *packet_ptr,
    		                  theora_state  * theo_state_ptr);
     bool next_page         ();
     bool next_theora_page  ();
     bool is_header_page    (ogg_page * ogg_page_ptr);
     bool is_theora_stream  (ogg_stream_state *probe_state_ptr,  ogg_packet * probe_packet_ptr);
     bool initialize_theora ();
     bool process_packet (unsigned char * BGRAbuffer); // the outcome, when successful: BGRAbuffer filled
     void yuv2bgra(unsigned char *BGRAbuffer);
};


# endif
