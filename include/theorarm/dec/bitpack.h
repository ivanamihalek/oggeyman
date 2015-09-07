/********************************************************************
 *                                                                  *
 * THIS FILE IS PART OF THE Theorarm SOFTWARE CODEC SOURCE CODE.    *
 * USE, DISTRIBUTION AND REPRODUCTION OF THIS LIBRARY SOURCE IS     *
 * GOVERNED BY A SOURCE LICENSE INCLUDED WITH THIS SOURCE           *
 * IN 'COPYING'. PLEASE READ THESE TERMS BEFORE DISTRIBUTING.       *
 *                                                                  *
 * THE Theora SOURCE CODE IS COPYRIGHT (C) 2002-2009                *
 * by the Xiph.Org Foundation and contributors http://www.xiph.org/ *
 * Modifications/Additions Copyright (C) 2009 Robin Watts for       *
 * Pinknoise Productions Ltd.                                       *
 *                                                                  *
 ********************************************************************

  function: packing variable sized words into an octet stream

 ********************************************************************/
#if !defined(_bitpack_H)
# define _bitpack_H (1)
# include <ogg/ogg.h>

#define oc_pack_buf oggpack_buffer
#define oc_pack_adv(B,A) theorapackB_adv(B,A)
#define oc_pack_look(B,A) theorapackB_look(B,A)
#define oc_pack_readinit(B,R) theorapackB_readinit(B,R)
#define oc_pack_read(B,L) theorapackB_read((B),(L))
#define oc_pack_read1(B) theorapackB_read1((B))
#define oc_pack_bytes_left(B) theorapackB_bytesleft(B)

long theorapackB_lookARM(oggpack_buffer *_b, int bits);
long theorapackB_readARM(oggpack_buffer *_b,int _bits);
long theorapackB_read1ARM(oggpack_buffer *_b);

#if 1

#define theorapackB_look theorapackB_lookARM
#define theorapackB_read theorapackB_readARM
#define theorapackB_read1 theorapackB_read1ARM
#define theorapackB_adv  oggpack_adv
#define theorapackB_readinit oggpack_readinit
#define theorapackB_bytes oggpack_bytes
#define theorapackB_bits oggpack_bits
#define theorapackB_bytesleft oggpack_bytesleft

#else

long theorapackB_look(oggpack_buffer *_b, int bits);
void theorapackB_adv(oggpack_buffer *_b, int bits);
long theorapackB_read(oggpack_buffer *_b,int _bits);
void theorapackB_readinit(oggpack_buffer *b, ogg_reference *r);
long theorapackB_bytes(oggpack_buffer *_b);
long theorapackB_bits(oggpack_buffer *_b);
long theorapackB_bytesleft(oggpack_buffer *_b);

#endif




//unsigned char *theorapackB_get_buffer(oggpack_buffer *_b);


#endif
