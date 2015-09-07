#include "oggeyman.hpp"
#include "wrapper.h"


extern "C" {
	JNIEXPORT jint JNICALL JNI_OnLoad_oggeyman (JavaVM *vm, void *pvt) {
		fprintf( stdout, "* JNI_OnLoad_oggeyman called\n" );
		return JNI_VERSION_1_8;
	}
}

/*
JNIEXPORT void JNICALL JNI_OnUnload_oggeyman (JavaVM *vm, void *pvt){
	//fprintf( stdout, "* JNI_OnUnload called\n" );
}

JNIEXPORT jint JNICALL JNI_OnLoad (JavaVM *vm, void *pvt) {
	fprintf( stdout, "* JNI_OnLoad called\n" );
	return JNI_VERSION_1_8;
}


JNIEXPORT void JNICALL JNI_OnUnload (JavaVM *vm, void *pvt){
	//fprintf( stdout, "* JNI_OnUnload called\n" );
}
*/


JNIEXPORT jlong JNICALL Java_oggeyman_Oggeyman_create
	(JNIEnv * env, jobject oggeyObject) {
	return reinterpret_cast <jlong> (new Oggeyman());
}


JNIEXPORT jboolean JNICALL Java_oggeyman_Oggeyman_init
  (JNIEnv * env, jobject oggeyObject, jlong handle, jstring filePath) {
	Oggeyman * oggeyPtr = reinterpret_cast <Oggeyman *> (handle);
	// jstring to char *
	const char * cStyleString = NULL;
	cStyleString = env->GetStringUTFChars (filePath, NULL);
    if (cStyleString==NULL) return 0;
    // pass to the init() function
    jboolean retval = oggeyPtr->init(cStyleString);
    env->ReleaseStringUTFChars (filePath, cStyleString);
	// pass to the init() function

    return retval;
}

JNIEXPORT void JNICALL Java_oggeyman_Oggeyman_timer_1restart
	(JNIEnv * env, jobject oggeyObject, jlong handle) {
	Oggeyman * oggeyPtr = reinterpret_cast <Oggeyman *> (handle);
	oggeyPtr->timer_restart();
	return;
}

JNIEXPORT jboolean JNICALL Java_oggeyman_Oggeyman_fast_1forward_1to_1frame
  (JNIEnv * env, jobject oggeyObject, jlong handle, jint frameno){
	Oggeyman * oggeyPtr = reinterpret_cast <Oggeyman *> (handle);
	jboolean retval = oggeyPtr->fast_forward_to_frame(frameno);
	return retval;
}

JNIEXPORT jint JNICALL Java_oggeyman_Oggeyman_width
  (JNIEnv * env, jobject oggeyObject, jlong handle) {
	Oggeyman * oggeyPtr = reinterpret_cast <Oggeyman *> (handle);
	return  oggeyPtr->width();
}

JNIEXPORT jint JNICALL Java_oggeyman_Oggeyman_height
(JNIEnv * env, jobject oggeyObject, jlong handle) {
	Oggeyman * oggeyPtr = reinterpret_cast <Oggeyman *> (handle);
	return oggeyPtr->height();
}

JNIEXPORT jboolean JNICALL Java_oggeyman_Oggeyman_get_1next_1frame
  ( JNIEnv * env, jobject oggeyObject, jlong handle, jbyteArray retBuffer) {
	Oggeyman * oggeyPtr = reinterpret_cast <Oggeyman *> (handle);
	//Java 2 SDK release 1.2 introduces Get/ReleasePrimitiveArrayCritical functions.
	//These functions allow virtual machines to disable garbage collection
	// while the native code accesses the contents of primitive arrays
	jbyte * carr = env->GetByteArrayElements(retBuffer, NULL);
	if (carr == NULL) return 0; /* exception occurred */
	bool retval = oggeyPtr->get_next_frame((unsigned char*)carr);
	env->ReleaseByteArrayElements(retBuffer, carr, 0);
	return retval;
}

JNIEXPORT jboolean JNICALL Java_oggeyman_Oggeyman_done
	(JNIEnv * env, jobject oggeyObject, jlong handle) {
	Oggeyman * oggeyPtr = reinterpret_cast <Oggeyman *> (handle);
	return oggeyPtr->done();
}

JNIEXPORT jboolean JNICALL Java_oggeyman_Oggeyman_shutdown
	(JNIEnv * env, jobject oggeyObject, jlong handle) {
	Oggeyman * oggeyPtr = reinterpret_cast <Oggeyman *> (handle);
	return oggeyPtr->shutdown();
}


