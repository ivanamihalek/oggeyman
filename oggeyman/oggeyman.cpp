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


#include "oggeyman.hpp"

Oggeyman::Oggeyman() {
	springtime_cleaning();
}

Oggeyman::~Oggeyman() {
	shutdown();
}

bool Oggeyman::done() {
	return stream_done;
}

void Oggeyman::springtime_cleaning() {

	memset(&overall_sync_state, 0, sizeof(overall_sync_state));
	memset(&ogg_theora_stream_state, 0, sizeof(ogg_theora_stream_state));
	memset(&current_ogg_page, 0, sizeof(current_ogg_page));
	memset(&ogg_theora_packet, 0, sizeof(ogg_theora_packet));

	memset(&theo_info, 0, sizeof(theo_info));
	memset(&theo_comment, 0, sizeof(theo_comment));
	memset(&theo_state, 0, sizeof(theo_state));

	last_packet_time = 0; // theora packet, we are not considering any other packets here
	total_play_time = 0;
	last_registered_time = 0;
	pp_level_max = 0;
	pp_level = 0;
	pp_inc = 0;
	stream_done = false;
	infptr = NULL;
	video_format = VF_RGBA;

}

bool Oggeyman::init(VideoFormat video_format, char * path) {
	// I won't be exporting this to interface, bcs libgdx does not have BGRA option
	this->video_format = video_format;
	return init(path);
}

# define PREC 15

bool Oggeyman::init(const char * path) {

	switch (video_format) {
	//pixel_format.set(r_offset,g_offset,b_offset,bpp not a_offset);
	case VF_RGB:
		pixel_format.set(0, 1, 2, 3);
		break;
	case VF_BGR:
		pixel_format.set(2, 1, 0, 3);
		break;
	case VF_RGBA:
		pixel_format.set(0, 1, 2, 4);
		break;
	case VF_BGRA:
		pixel_format.set(2, 1, 0, 4);
		break;
	}
	this->path = path;
	// open the input file
	infptr = fopen(path, "rb");
	if (!infptr) {
		printf("\t failure opening %s\n", path);
		return false;
	}
	// initialize  ogg and theora -- none of these have a useful diagnostics implemented
	ogg_sync_init(&overall_sync_state);
	theora_info_init(&theo_info);
	theora_comment_init(&theo_comment);
	// find theora stream
	if (!parse_headers())	return false;
	// bcs we are only interested in theora,
	// flip through pages until we are sure we are on theora page
	bool have_page = false;
	bool is_theora_page = false;
	do { // we start by checking the page that was read in during header perusal
		int retval = ogg_stream_pagein(&ogg_theora_stream_state, &current_ogg_page);
		is_theora_page = (retval >= 0);
		if (!is_theora_page) have_page = next_page();
	} while (have_page && !is_theora_page);
	// initialize theora decoder
	if (!initialize_theora())
		return false;
	// the user should allocate space for the output buffer, BGRAbuffer
	return true;
}
/*******************************************************************************************/
bool Oggeyman::parse_headers() {

	bool found_theora = false;
	// The whole page belongs to one particular stream, but to find out what is the type of
	// the payload, we have to go all the way down to the packet level and try to decode it.
	// In this first loop we will only go through the header pages, and find which
	// stream belongs to theora - we will save that info in theora_stream_state structure
	// later, we will use that info to look only at the pages belonging to our stream of interest
	// (here I am counting on having (or following) only one stream- theora)s
	ogg_stream_state probe;
	int pagect = 0;
	while (next_page()) {
		pagect++;
		// is this a header page at all?
		if (!is_header_page(&current_ogg_page)) break;
		bool wrote_stream_state = false;
		if (ogg_stream_init(&probe, ogg_page_serialno(&current_ogg_page)))
			return false;
		// submit the completed page to the streaming layer with ogg_stream_pagein
		ogg_stream_pagein(&probe, &current_ogg_page);
		// if I understand this correctly, theora wants theora_decode_header to be called
		// "until it returns 0": theora_decode_header is wrapper for th_decode_headerin
		// [th_decode_headerin] Decodes one header packet.
		// This should be called repeatedly with the packets at the beginning of the
		//  stream until it returns 0.
		// That is why we call is_theora_stream, even though we have initialized the theora stream_state.
		// (I.e. one would think that we need to find only one theora header, but no.)
		if (is_theora_stream(&probe, &ogg_theora_packet)) {
			found_theora = true;
			if (! ogg_theora_stream_state.serialno) {
				memcpy(&ogg_theora_stream_state, &probe, sizeof(probe));
				wrote_stream_state = true;
			}
		}
		if (!wrote_stream_state) ogg_stream_clear(&probe);

	}
	return found_theora;
}

/******************************************************************/
bool Oggeyman::is_header_page(ogg_page * ogg_page_ptr) {
	// From Ogg spec: "Granule Position must always increase forward or remain equal
	// from page to page, be unset, or be zero for a header page. "
	bool is_header = false;
	if (ogg_page_granulepos(ogg_page_ptr) == 0)
		is_header = true;
	return is_header;
}
/******************************************************************/
bool Oggeyman::is_theora_stream(ogg_stream_state *probe_state_ptr, ogg_packet * probe_packet_ptr) {

	bool found_theora_packet = false;
	while (next_packet(probe_state_ptr, probe_packet_ptr)) {
		// theo info and theo comment are private variables of the Oggeyman object
		if (theora_decode_header(&theo_info, &theo_comment, probe_packet_ptr)>= 0) {
			found_theora_packet = true;
			// I need to go through all of them (or so the src code makes me believe)
			// therefore, no break here
		}
	}
	return found_theora_packet;
}
/******************************************************************/
bool Oggeyman::next_packet(ogg_stream_state *state_ptr,
		ogg_packet *packet_ptr) {
	int retval = -1;
	int panic_ctr = 0;
	while (retval < 0 && panic_ctr < 100) { // I am not sure what this is
		// in framing.c:976:_packetout() it says, quote:
		/*  "we need to tell the codec there's a gap; it might need to
		 handle previous packet dependencies" */
		retval = ogg_stream_packetout(state_ptr, packet_ptr);
		panic_ctr++;
	}
	if (retval <= 0)
		return false;
	if (packet_ptr->bytes == 0)
		return false;	// happens in theorarm version
	return true;
}
/******************************************************************/
bool Oggeyman::next_theora_packet(ogg_stream_state *state_ptr,
		ogg_packet *packet_ptr, theora_state * theo_state_ptr) {
	bool have_packet = false;
	bool packet_ok = false;
	do {
		have_packet = next_packet(state_ptr, packet_ptr);
		if (have_packet)
			packet_ok =(theora_decode_packetin(theo_state_ptr, packet_ptr) >= 0);
	} while (have_packet && !packet_ok);

	return have_packet && packet_ok; // superfluous, but readable
}
/******************************************************************/
bool Oggeyman::next_page() {
	bool have_next_page = false;
	// ogg_sync_pageout takes the data stored in the buffer of the ogg_sync_state struct
	// and inserts them into an ogg_page.
	// The ogg_sync_state struct tracks the synchronization of the current page
	// return values for ogg_sync_pageout:
	//case -1: //stream has not yet captured sync (bytes were skipped)
	//case  0: // more data needed or an internal error occurred
	//case 1: //indicates a page was synced and returned

	if (ogg_sync_pageout(&overall_sync_state, &current_ogg_page) > 0) {
		// we have some leftovers from the last time
		have_next_page = true;

	} else while (ogg_sync_pageout(&overall_sync_state, &current_ogg_page) <= 0) {
		// allocate buffer of the appropriate size
		char* ogg_buffer = (char *) ogg_sync_buffer(&overall_sync_state, IN_CHUNK_SIZE);
		size_t bytes_written = fread(ogg_buffer, 1, IN_CHUNK_SIZE, infptr);
		// shouldn't we be checking whether we are done here?
		if (bytes_written) {
			ogg_sync_wrote(&overall_sync_state, bytes_written);
			have_next_page = true;
		} else {
			break;
		}
	}
	if (!current_ogg_page.header) // we didn't write anything, probably not ogg at all
		have_next_page = false;

	return have_next_page;
}
/******************************************************************/
bool Oggeyman::initialize_theora() {

	theora_decode_init(&theo_state, &theo_info);
	theora_control(&theo_state, TH_DECCTL_GET_PPLEVEL_MAX, &pp_level_max,
			sizeof(pp_level_max));
	pp_level = pp_level_max;
	theora_control(&theo_state, TH_DECCTL_SET_PPLEVEL, &pp_level,
			sizeof(pp_level));
	pp_inc = 0;
	return true;
}
/******************************************************************/
bool Oggeyman::fast_forward_to_frame(int frameno) {

	if (stream_done)
		return false;
	int framect = 0;
	while (framect < frameno && !stream_done) {
		bool packet_found = false;
		do {
			// list through packets to get rid of bad packets
			// (the function below checks whether the packet is ok)
			packet_found = next_theora_packet(&ogg_theora_stream_state,
					&ogg_theora_packet, &theo_state);
			if (!packet_found) { //try new page
				bool is_theora_page = false;
				while (!stream_done && !is_theora_page) {
					stream_done = !next_page();
					if (stream_done)
						continue;
					// submit the completed page to the streaming layer with ogg_stream_pagein.
					// check out the return value - it will be < 0 it the page does not correspond
					// to the stream whose state we are providing as the first argument
					is_theora_page = (ogg_stream_pagein(
							&ogg_theora_stream_state, &current_ogg_page) >= 0);
				}
			} else {
				framect++;
			}
		} while (!packet_found && !stream_done);
	}
	if (framect == frameno && !stream_done) {
		total_play_time = last_packet_time = get_packet_time();
		return true;
	}
	return false;
}

/******************************************************************/
bool Oggeyman::get_next_frame(unsigned char *BGRAbuffer) {

	if (stream_done)
		return false;
	timer_update();
#ifdef ANDR
	//printf ("in get_next_frame:  last_packet_time %12.2lf   total_play_time %12.2lf \n", last_packet_time, total_play_time);
	// "foo"  will be used as a tag in LogCat
	__android_log_print(ANDROID_LOG_INFO, "foo",
			"in get_next_frame:  last_packet_time %12.2lf   total_play_time %12.2lf \n", last_packet_time, total_play_time );
# endif
	if (last_packet_time > total_play_time)
		return false;
	// TODO: what's with this pp_level reduction business?
	// do we have a leftover packet from the last page? (and is it really theora?)

#ifdef ANDR
	struct timespec time1,time2;
	clock_gettime(CLOCK_MONOTONIC, &time1);
# endif
	bool packet_found = (next_packet(&ogg_theora_stream_state,
			&ogg_theora_packet)
			&& theora_decode_header(&theo_info, &theo_comment,
					&ogg_theora_packet) >= 0);
#ifdef ANDR
	clock_gettime(CLOCK_MONOTONIC, &time2);
	__android_log_print(ANDROID_LOG_INFO, "foo",
			"in get_next_frame:  time to get next packet and decode header %6.2lf ms\n", (time2.tv_sec - time1.tv_sec)*1.e3 + (time2.tv_nsec - time1.tv_nsec)/1000.0f );
	clock_gettime(CLOCK_MONOTONIC, &time1);
# endif
	while (!packet_found && !stream_done) {
		bool is_theora_page = false;
		while (!stream_done && !is_theora_page) {
			stream_done = !next_page();
			if (stream_done) continue;
			// submit the completed page to the streaming layer with ogg_stream_pagein.
			// check out the return value - it will be < 0 it the page does not correspond
			// to the stream whose state we are providing as the first argument
			is_theora_page = (ogg_stream_pagein(&ogg_theora_stream_state,
					&current_ogg_page) >= 0);
		}
		if (stream_done) continue;
		// Packets can span multiple pages, but next_packet, or rather ogg_stream_packetout,
		// should take care of that - not return packets until they are complete.
		packet_found = next_packet(&ogg_theora_stream_state, &ogg_theora_packet);
	}
#ifdef ANDR
	clock_gettime(CLOCK_MONOTONIC, &time2);
	__android_log_print(ANDROID_LOG_INFO, "foo",
			"in get_next_frame:  looping for next packet %6.2lf ms\n", (time2.tv_sec - time1.tv_sec)*1.e3 + (time2.tv_nsec - time1.tv_nsec)/1000.0f );
# endif

	if (packet_found) {
#ifdef ANDR
		clock_gettime(CLOCK_MONOTONIC, &time1);
# endif
		bool processing_ok = process_packet(BGRAbuffer);
#ifdef ANDR
		clock_gettime(CLOCK_MONOTONIC, &time2);
		__android_log_print(ANDROID_LOG_INFO, "foo",
				"[Aug 2015] in get_next_frame:  time to process the packet %6.2lf ms\n", (time2.tv_sec - time1.tv_sec)*1.e3 + (time2.tv_nsec - time1.tv_nsec)/1.e6 );
# endif
		return processing_ok;
	}
	return false;
}

/******************************************************************/
double Oggeyman::get_packet_time() {
	if (ogg_theora_packet.granulepos >= 0) {
		theora_control(&theo_state, TH_DECCTL_SET_GRANPOS,
				&(ogg_theora_packet.granulepos),
				sizeof(ogg_theora_packet.granulepos));
	}
	ogg_int64_t videobuf_granulepos = theo_state.granulepos;
	return theora_granule_time(&theo_state, videobuf_granulepos);
}
/******************************************************************/
bool Oggeyman::process_packet(unsigned char *BGRAbuffer) {
	// if we got to here, it should be that
	// a) we have theora stream
	// b) this particular packet belongs to theora
	double this_packet_time = get_packet_time();
#ifdef ANDR
	struct timespec time1,time2;
	clock_gettime(CLOCK_MONOTONIC, &time1);
#endif
	int retvalue = theora_decode_packetin(&theo_state, &ogg_theora_packet);
#ifdef ANDR
	clock_gettime(CLOCK_MONOTONIC, &time2);
	__android_log_print(ANDROID_LOG_INFO, "foo",
			"\tin process_packet:  theora_decode_packetin  %6.2lf ms\n", (time2.tv_nsec - time1.tv_nsec)/1.e6 );
#endif
	if (retvalue != 0)
		return false;
	// decoding ok, give us the YUV buffer pls
#ifdef ANDR
	clock_gettime(CLOCK_MONOTONIC, &time1);
#endif

	theora_decode_YUVout(&theo_state, &YUVbuffer);
#ifdef ANDR
	clock_gettime(CLOCK_MONOTONIC, &time2);
	__android_log_print(ANDROID_LOG_INFO, "foo",
			"\tin process_packet:  theora_decode_YUVout  %6.2lf ms\n", (time2.tv_nsec - time1.tv_nsec)/1.e6 );
#endif
	// translate the buffer to BGRA, the Opengl's favorite format
#ifdef ANDR
	clock_gettime(CLOCK_MONOTONIC, &time1);
#endif
	yuv2bgra(BGRAbuffer);
#ifdef ANDR
	clock_gettime(CLOCK_MONOTONIC, &time2);
	__android_log_print(ANDROID_LOG_INFO, "foo",
			"\tin process_packet:  yuv2bgra  %6.2lf ms\n",
			(time2.tv_sec - time1.tv_sec)*1.e3 + (time2.tv_nsec - time1.tv_nsec)/1.e6 );
#endif
	last_packet_time = this_packet_time;
	return true;

}
/********************************************************/
inline double get_wall_time() {
	// this was an attempt to see if the timer is the problem on android
	// but apparently yhis is not the case, and it is just giving me further problems
	// because clock_gettime is apparently not supported on OSX should use mach_time or some such
	// (like, gettimeofday should never be used because is has a hiccup each time NTP kicks in)
	// TODO maybe fix this later, after I have figured what actually kills android
# ifdef ANDR
	struct timespec time;
	clock_gettime(CLOCK_MONOTONIC, &time);
	return (double)time.tv_sec + (double)time.tv_nsec * 1.e-9;
# else
	struct timeval time;
	gettimeofday(&time, NULL);
	return (double) time.tv_sec + (double) time.tv_usec * .000001;
# endif
}

/******************************************************************/
void Oggeyman::timer_update() {
	double now = get_wall_time();
	double uninterrupted_chunk = now - last_registered_time;
	total_play_time += uninterrupted_chunk;
	last_registered_time = now;
}
/******************************************************************/
// we do nothing in particular on pause, but on restart we register
// the new time - note that on linux, clock() measures system time
// on windows it measures wall time
void Oggeyman::timer_restart() {
	last_registered_time = get_wall_time();
}

/******************************************************************/
int Oggeyman::width() {
	return theo_info.width;
}
/******************************************************************/
int Oggeyman::height() {
	return theo_info.height;
}

bool Oggeyman::shutdown() {
	// shutdown in the reverse order of intialization
	theora_clear(&theo_state);
	ogg_stream_clear(&ogg_theora_stream_state);
	theora_comment_clear(&theo_comment);
	theora_info_clear(&theo_info);
	ogg_sync_clear(&overall_sync_state);

	if (infptr)
		fclose(infptr);

	return true;
}

/*****************************************************************/
inline int clamp(int val) {
	if (val < 0)
		return 0;
	if (val > 255)
		return 255;
	return val;
}

void Oggeyman::yuv2bgra(unsigned char * BGRAbuffer) {

	int stride = width() * pixel_format.bpp;
	int uv_ki = YUVbuffer.y_width / YUVbuffer.uv_width;
	int uv_kj = YUVbuffer.y_height / YUVbuffer.uv_height;

	int y_offset = theo_info.offset_x + YUVbuffer.y_stride * theo_info.offset_y;
	int uv_offset = theo_info.offset_x / uv_ki
			+ YUVbuffer.uv_stride * theo_info.offset_y / uv_kj;

	int y_p, uv_p, b_p;
	int w = width();
	int h = height();

	unsigned char * y_start = YUVbuffer.y + y_offset;
	unsigned char * u_start = YUVbuffer.u + uv_offset;
	unsigned char * v_start = YUVbuffer.v + uv_offset;

	if (1) {
#ifdef ANDR
	    __android_log_print(ANDROID_LOG_INFO, "foo",
				"going to watts" );
# endif
	    watts(BGRAbuffer, y_start, u_start, v_start, width(), height(),
		  YUVbuffer.y_stride,  //y_span
		  YUVbuffer.uv_stride, //uv_span
		  stride); //dst_span
			     
	} else { /* the straightforward implementation using multiplication*/
		for (int j = 0; j < h; j++) {
			y_p = y_offset + j * YUVbuffer.y_stride;
			b_p = j * stride;
			uv_p = uv_offset + j / uv_kj * YUVbuffer.uv_stride;

			for (int i = 0; i < w; i++) {
				//http://en.wikipedia.org/wiki/YUVbuffer
				//theora's yuv_buffer is actually YCbCr (duh)
				int y = YUVbuffer.y[y_p];
				int u = YUVbuffer.u[uv_p] - 128;
				int v = YUVbuffer.v[uv_p] - 128;

				int r = clamp(y + 1.402 * v);
				int g = clamp(y - 0.344 * u - 0.714 * v);
				int b = clamp(y + 1.772 * u);

				BGRAbuffer[b_p + pixel_format.r_offset] = r;
				BGRAbuffer[b_p + pixel_format.g_offset] = g;
				BGRAbuffer[b_p + pixel_format.b_offset] = b;
				if (pixel_format.bpp == 4)
					BGRAbuffer[b_p + 3] = 255;
				b_p += pixel_format.bpp;
				y_p += 1;
				if (i % uv_ki == uv_ki - 1)
					uv_p++;
			}
		}

	}
}

/*****************************************************************/
