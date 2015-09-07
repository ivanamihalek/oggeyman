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
    last mod: $Id: dequant.c 16503 2009-08-22 18:14:02Z giles $

 ********************************************************************/

#include <stdlib.h>
#include <string.h>
#include <ogg/ogg.h>
#include "dequant.h"
#include "decint.h"

int oc_quant_params_unpack(oc_pack_buf *_opb,th_quant_info *_qinfo){
  th_quant_base *base_mats;
  int            nbase_mats;
  int            sizes[64];
  int            indices[64];
  int            nbits;
  int            bmi;
  int            ci;
  int            qti;
  int            pli;
  int            qri;
  int            qi;
  int            i;
  nbits=(int)oc_pack_read(_opb,3);
  for(qi=0;qi<64;qi++){
    _qinfo->loop_filter_limits[qi]=(unsigned char)oc_pack_read(_opb,nbits);
  }
  nbits=(int)oc_pack_read(_opb,4)+1;
  for(qi=0;qi<64;qi++){
    _qinfo->ac_scale[qi]=(ogg_uint16_t)oc_pack_read(_opb,nbits);
  }
  nbits=(int)oc_pack_read(_opb,4)+1;
  for(qi=0;qi<64;qi++){
    _qinfo->dc_scale[qi]=(ogg_uint16_t)oc_pack_read(_opb,nbits);
  }
  nbase_mats=(int)oc_pack_read(_opb,9)+1;
  base_mats=_ogg_malloc(nbase_mats*sizeof(base_mats[0]));
  if(base_mats==NULL)return TH_EFAULT;
  for(bmi=0;bmi<nbase_mats;bmi++){
    for(ci=0;ci<64;ci++){
      base_mats[bmi][ci]=(unsigned char)oc_pack_read(_opb,8);
    }
  }
  nbits=oc_ilog(nbase_mats-1);
  for(i=0;i<6;i++){
    th_quant_ranges *qranges;
    th_quant_base   *qrbms;
    int             *qrsizes;
    qti=i/3;
    pli=i%3;
    qranges=_qinfo->qi_ranges[qti]+pli;
    if(i>0){
      if(!oc_pack_read1(_opb)){
        int qtj;
        int plj;
        if(qti>0){
          if(oc_pack_read1(_opb)){
            qtj=qti-1;
            plj=pli;
          }
          else{
            qtj=(i-1)/3;
            plj=(i-1)%3;
          }
        }
        else{
          qtj=(i-1)/3;
          plj=(i-1)%3;
        }
        *qranges=*(_qinfo->qi_ranges[qtj]+plj);
        continue;
      }
    }
    indices[0]=(int)oc_pack_read(_opb,nbits);
    for(qi=qri=0;qi<63;){
      sizes[qri]=(int)oc_pack_read(_opb,oc_ilog(62-qi))+1;
      qi+=sizes[qri];
      indices[++qri]=(int)oc_pack_read(_opb,nbits);
    }
    /*Note: The caller is responsible for cleaning up any partially
       constructed qinfo.*/
    if(qi>63){
      _ogg_free(base_mats);
      return TH_EBADHEADER;
    }
    qranges->nranges=qri;
    qranges->sizes=qrsizes=(int *)_ogg_malloc(qri*sizeof(qrsizes[0]));
    if(qranges->sizes==NULL){
      /*Note: The caller is responsible for cleaning up any partially
         constructed qinfo.*/
      _ogg_free(base_mats);
      return TH_EFAULT;
    }
    memcpy(qrsizes,sizes,qri*sizeof(qrsizes[0]));
    qrbms=(th_quant_base *)_ogg_malloc((qri+1)*sizeof(qrbms[0]));
    if(qrbms==NULL){
      /*Note: The caller is responsible for cleaning up any partially
         constructed qinfo.*/
      _ogg_free(base_mats);
      return TH_EFAULT;
    }
    qranges->base_matrices=(const th_quant_base *)qrbms;
    do{
      bmi=indices[qri];
      /*Note: The caller is responsible for cleaning up any partially
         constructed qinfo.*/
      if(bmi>=nbase_mats){
        _ogg_free(base_mats);
        return TH_EBADHEADER;
      }
      memcpy(qrbms[qri],base_mats[bmi],sizeof(qrbms[qri]));
    }
    while(qri-->0);
  }
  _ogg_free(base_mats);
  return 0;
}

void oc_quant_params_clear(th_quant_info *_qinfo){
  int i;
  for(i=6;i-->0;){
    int qti;
    int pli;
    qti=i/3;
    pli=i%3;
    /*Clear any duplicate pointer references.*/
    if(i>0){
      int qtj;
      int plj;
      qtj=(i-1)/3;
      plj=(i-1)%3;
      if(_qinfo->qi_ranges[qti][pli].sizes==
       _qinfo->qi_ranges[qtj][plj].sizes){
        _qinfo->qi_ranges[qti][pli].sizes=NULL;
      }
      if(_qinfo->qi_ranges[qti][pli].base_matrices==
       _qinfo->qi_ranges[qtj][plj].base_matrices){
        _qinfo->qi_ranges[qti][pli].base_matrices=NULL;
      }
    }
    if(qti>0){
      if(_qinfo->qi_ranges[1][pli].sizes==
       _qinfo->qi_ranges[0][pli].sizes){
        _qinfo->qi_ranges[1][pli].sizes=NULL;
      }
      if(_qinfo->qi_ranges[1][pli].base_matrices==
       _qinfo->qi_ranges[0][pli].base_matrices){
        _qinfo->qi_ranges[1][pli].base_matrices=NULL;
      }
    }
    /*Now free all the non-duplicate storage.*/
    _ogg_free((void *)_qinfo->qi_ranges[qti][pli].sizes);
    _ogg_free((void *)_qinfo->qi_ranges[qti][pli].base_matrices);
  }
}
