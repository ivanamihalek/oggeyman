# include <stdio.h>
# include <stdlib.h>
# include <math.h>
# include <string.h>
# include "oggeyman.hpp"

int main ( int argc, char * argv[]) {

    Oggeyman oggey;
    
    if (!oggey.init(VF_BGRA, "test.ogv")) return 1;
	
    int num_bytes = oggey.width() * oggey.height() * 4;
    unsigned char *BGRAbuffer = NULL;
    BGRAbuffer = calloc(num_bytes,sizeof(unsigned char));
    if (!BGRAbuffer) {
	fprintf (stderr, "allocation problem\n");
	exit(0);
    }
    oggey.timer_restart();
    while (!oggey.done() ) {
	bool next_frame_ready = false;
	while (!next_frame_ready && !oggey.done()) {
	    next_frame_ready = oggey.get_next_frame(BGRAbuffer);
	}
	printf ("time  %8.3f, done ? %d\n", oggey.get_packet_time(), oggey.done() );
    };
    return 0;
}
 
