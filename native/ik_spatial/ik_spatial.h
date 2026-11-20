#ifndef IK_SPATIAL_H
#define IK_SPATIAL_H
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
#define IK_SPATIAL_TAPS 256
#ifdef _WIN32
__declspec(dllexport)
#endif
int ik_spatial_abi_version(void);
typedef struct IkSpatial IkSpatial;
IkSpatial *ik_spatial_create(int sample_rate);
void ik_spatial_destroy(IkSpatial *state);
void ik_spatial_reset(IkSpatial *state);
int ik_spatial_configure(IkSpatial *state, int enabled, float strength,
                         float azimuth, float elevation, int smooth);
int ik_spatial_process(IkSpatial *state, const float *input, float *output,
                       size_t frames);
uint64_t ik_spatial_frames(const IkSpatial *state);
const float *ik_spatial_kernel(const IkSpatial *state, int source, int ear);
#ifdef __cplusplus
}
#endif
#endif
