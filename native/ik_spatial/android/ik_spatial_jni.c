#include <jni.h>
#include <stdint.h>
#include "ik_spatial.h"

#define JNI_METHOD(name) Java_com_ryanheise_just_1audio_IkSpatialProcessor_##name

JNIEXPORT jlong JNICALL JNI_METHOD(create)(JNIEnv *env, jclass cls, jint rate) {
    (void)env; (void)cls;
    return (jlong)(intptr_t)ik_spatial_create(rate);
}
JNIEXPORT void JNICALL JNI_METHOD(destroy)(JNIEnv *env, jclass cls, jlong ptr) {
    (void)env; (void)cls;
    ik_spatial_destroy((IkSpatial *)(intptr_t)ptr);
}
JNIEXPORT void JNICALL JNI_METHOD(resetNative)(JNIEnv *env, jclass cls, jlong ptr) {
    (void)env; (void)cls;
    ik_spatial_reset((IkSpatial *)(intptr_t)ptr);
}
JNIEXPORT jint JNICALL JNI_METHOD(configure)(JNIEnv *env, jclass cls, jlong ptr,
    jboolean enabled, jfloat strength, jfloat azimuth, jfloat elevation) {
    (void)env; (void)cls;
    return ik_spatial_configure((IkSpatial *)(intptr_t)ptr, enabled,
        strength, azimuth, elevation, 1);
}
JNIEXPORT jint JNICALL JNI_METHOD(process)(JNIEnv *env, jclass cls, jlong ptr,
    jobject input, jint offset, jobject output, jint frames, jint channels) {
    (void)cls;
    if (!ptr || frames < 0 || (channels != 1 && channels != 2)) return -1;
    const uint8_t *bytes = (*env)->GetDirectBufferAddress(env, input);
    int16_t *destination = (*env)->GetDirectBufferAddress(env, output);
    if (!bytes || !destination || offset < 0 ||
        (*env)->GetDirectBufferCapacity(env, input) < (jlong)offset+frames*channels*2LL ||
        (*env)->GetDirectBufferCapacity(env, output) < frames*4LL) return -1;
    const int16_t *source = (const int16_t *)(bytes+offset);
    float block[1024*2], processed[1024*2];
    for (int start=0; start<frames; start+=1024) {
        int count=frames-start < 1024 ? frames-start : 1024;
        for (int i=0; i<count; ++i) {
            block[2*i]=source[(start+i)*channels]/32768.0f;
            block[2*i+1]=source[(start+i)*channels+channels-1]/32768.0f;
        }
        int result=ik_spatial_process((IkSpatial *)(intptr_t)ptr, block, processed, count);
        if (result) return result;
        for (int i=0; i<count*2; ++i) {
            float value=processed[i]*32768.0f;
            destination[start*2+i]=(int16_t)(value>32767 ? 32767 : value < -32768 ? -32768 : value);
        }
    }
    return 0;
}
