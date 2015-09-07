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

  function:
    last mod: $Id: fragment.c 16503 2009-08-22 18:14:02Z giles $

 ********************************************************************/
#include <string.h>
#include "internal.h"

#if 0
void oc_frag_copy_slow(unsigned char *_dst,const unsigned char *_src,int _ystride){
  int i;

  Output("Wooah! Unaligned fragment copy!\n");

  for(i=8;i-->0;){
    memcpy(_dst,_src,8*sizeof(*_dst));
    _dst+=_ystride;
    _src+=_ystride;
  }
}
#endif

#if 0
void oc_frag_recon_intra(unsigned char *_dst,int _ystride,
 const ogg_int16_t _residue[64]){
  int i;
  for(i=0;i<8;i++){
    int j;
    for(j=0;j<8;j++)_dst[j]=OC_CLAMP255(_residue[i*8+j]+128);
    _dst+=_ystride;
  }
}

void oc_frag_recon_inter(unsigned char *_dst,
 const unsigned char *_src,int _ystride,const ogg_int16_t _residue[64]){
  int i;
  for(i=0;i<8;i++){
    int j;
    for(j=0;j<8;j++)_dst[j]=OC_CLAMP255(_residue[i*8+j]+_src[j]);
    _dst+=_ystride;
    _src+=_ystride;
  }
}

void oc_frag_recon_inter2(unsigned char *_dst,const unsigned char *_src1,
 const unsigned char *_src2,int _ystride,const ogg_int16_t _residue[64]){
  int i;
  for(i=0;i<8;i++){
    int j;
    for(j=0;j<8;j++)_dst[j]=OC_CLAMP255(_residue[i*8+j]+(_src1[j]+_src2[j]>>1));
    _dst+=_ystride;
    _src1+=_ystride;
    _src2+=_ystride;
  }
}
#endif
