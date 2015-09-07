CPPCMPL =  arm-linux-gnueabi-g++ -fpermissive
CCOMPL  =  arm-linux-gnueabi-gcc
ASCOMPL =  arm-linux-gnueabi-as 
CFLAGS  =  -D_LOW_ACCURACY_ -O3 


DEFINES = # -DOSX

NAME = wattsARM


VPATH =  ../theorarm/dec:../theorarm/tremolo:../theorarm/yuv2rgb:../ogg:../oggeyman:../theorarm:../theora
LIBS      =  -lm -lc  -L/usr/lib 
INCLUDE   = -I../include/theorarm/dec -I../include/theorarm/tremolo -I../include/theorarm -I../include  -I../include/ogg
ASINCLUDE = -I../theorarm/dec

SOURCES.cpp =  armtest.cpp  oggeyman.cpp
SOURCES.c =   watts.c yuv2rgb16tab.c bitwise.c framing.c\
	apiwrapper.c decapiwrapper.c	decode.c fragment.c idct.c internal.c state.c \
	bitpack.c decinfo.c dequant.c huffdec.c	info.c	quant.c # yuv420_2_rgb8888.c

SOURCES.s =  yuv420_2_rgb8888.s bitwise2ARM.s   decodeARM.s  fragARM.s \
	idctARM.s    ppARM.s  stateARM.s

AUX =  makefile  yuv2rgb.h 

SOURCES = $(SOURCES.s)  $(SOURCES.c) $(SOURCES.cpp)
OBJECTS = $(SOURCES.s:.s=.o) $(SOURCES.c:.c=.o) $(SOURCES.cpp:.cpp=.o) 


$(NAME): $(OBJECTS) 
	$(CPPCMPL) -o $@  $(OBJECTS)  $(LIBS)
	@echo run with:  qemu-arm -L /usr/arm-linux-gnueabi $(NAME)


.cpp.o:
	$(CPPCMPL) $(CFLAGS) $(DEFINES)  -c $<  $(INCLUDE)
.c.o:
	$(CCOMPL) $(CFLAGS) $(DEFINES)  -c $<  $(INCLUDE)
.s.o:
	$(ASCOMPL) -o $@ -c $<  $(ASINCLUDE) 

clean:
	rm  $(OBJECTS) 



