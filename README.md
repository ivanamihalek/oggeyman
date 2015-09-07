#Oggeyman
From ogg/theora to OpenGL texture, with ARM speedup.

## Intro ##
 [Theora](http://www.theora.org/) video encoding has a reputation of being unfriendly to [ARM](https://en.wikipedia.org/wiki/ARM_architecture) architectures, used in all major mobile platforms. Several years ago Robin Watts provided a well needed speedup using pieces of native assembly code
 ([Theorarm](http://wss.co.uk/pinknoise/theorarm/)). Oggeyman takes that implementation and ties it together with mapping onto [OpenGL](https://en.wikipedia.org/wiki/OpenGL) [Texture](https://www.opengl.org/wiki/Texture), in a piece of C++ code. Technically, Oggey provides only a BGRA formatted data buffer that can be used directly as an input for the [OpenGL's glTexImage2D function](https://www.opengl.org/sdk/docs/man3/xhtml/glTexImage2D.xml) or its first cousin [glTexSubImage2D] (https://www.opengl.org/sdk/docs/man3/xhtml/glTexSubImage2D.xml).
 
 Java interface is also provided here, but without test code (see [To Do below](#todo)).
 
Test file credit: Polar_orbit.ogg from [Wikimedia Commons](https://commons.wikimedia.org/wiki/File:Polar_orbit.ogg).
 
## Prerequisites ##
[GNU toolchain](https://en.wikipedia.org/wiki/GNU_toolchain) (gcc, g++, and make in particular; though I suspect it should not be too hard to move to other toolchains) for compilation of a generic executable. 

For a cross-compiled version, you will need a cross-compiler, and an emulator. I.e. in a Ubuntu linux setting you would install the cross-compilation toolchain as
```
sudo apt-get install gcc-4.7-arm-linux-gnueabi libc6-dev-armel-cross
```
 and for the ([QEMU](http://wiki.qemu.org/Main_Page)) emulator
```
sudo apt-get install qemu-user-static
```
Note this last step provides  just the  user-level emulation (execution of cross-compiled code) rather than the full emulated enviroment that QEMU can in principle provide.

## Compilation of the provided test ##
In the armtest directory two makefiles are provided: plain_makefile, for compiling a regular C version of the code. arm_makefile provides and example of cross-compilation (on linux for arm platform). Run as
```
make -f plain makefile
```
or 
```
make -f arm_makefile
```
### Running the test ###
For the generic case just type 
```
./oggey
```
and for the cross-compiled one:
```
qemu-arm -L /usr/arm-linux-gnueabi oggeyARM
```
Make sure that the link path corresponds to the one where arm-linux-gnueabi resides in your setup. (Failing to do so results in `/lib/ld-linux.so.3: No such file or directory` error.)

In both cases, the output should be the time of each frame, printed on stdout, in the proper time sequence.

Note that Oggeyman.cpp can be used for threeway comparison/timing of the straightforward yuv2rgb implementation, the implementation using table lookup, and the ARM optimized implementation. See Oggeyman::yuv2bgra() in [Oggeyman.cpp](https://github.com/ivanamihalek/oggeyman/blob/master/oggeyman/oggeyman.cpp).


## What Oggeyman is not ###

Oggeyman is not a full decoder - in particular it pulls out Theora (video) stream from the provided [ogg](https://en.wikipedia.org/wiki/Ogg) file, and ignores the [Vorbis](https://en.wikipedia.org/wiki/Vorbis) (audio) or any other stream that might be present.

Oggeyman is not a player, either.  It  takes ogg file as an iput an returns a data buffer in BGRA format. The rest of the implementation is up to user. 


## <a name="todo">To do</a> ##

Oggeyman was originally written to be used as a part of a larger platform, ([LibGDX](https://libgdx.badlogicgames.com/) in particular), therefore comming up with some self-standing cross-compiled Java example is yet to bbe done. In the meantime, let it just be noted that a typical usage case would be to compile all C/C++ pieces into a library, to be called from Oggeyman.java. Oggeyman can then be used as a class in a bigger Java program. 

