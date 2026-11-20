/* 正式 U07 信号门：使用发行核心与真实 MIT KEMAR 系数，不依赖播放器 UI。 */
#include "ik_spatial.h"
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void require(int condition, const char *message) {
    if (!condition) { fprintf(stderr, "FAIL: %s\n", message); exit(1); }
}

int main(void) {
    const int rates[] = {44100, 48000};
    int cases = 0;
    for (int r = 0; r < 2; ++r) {
        for (int elevation = -30; elevation <= 30; elevation += 30) {
            for (int azimuth = -180; azimuth < 180; azimuth += 15) {
                for (int channel = 0; channel < 2; ++channel) {
                    IkSpatial *dsp = ik_spatial_create(rates[r]);
                    require(dsp != NULL, "supported rate");
                    require(ik_spatial_configure(dsp, 1, 1.0f, azimuth,
                                                elevation, 0) == 0,
                            "valid direction");
                    float input[1024] = {0}, output[1024] = {0};
                    input[channel] = 0.25f;
                    require(ik_spatial_process(dsp, input, output, 512) == 0,
                            "PCM processed");
                    const float *left = ik_spatial_kernel(dsp, channel, 0);
                    const float *right = ik_spatial_kernel(dsp, channel, 1);
                    double cross_energy = 0;
                    for (int i = 0; i < 512; ++i) {
                        float want_l = i < IK_SPATIAL_TAPS ? left[i] * 0.25f : 0;
                        float want_r = i < IK_SPATIAL_TAPS ? right[i] * 0.25f : 0;
                        require(fabsf(output[2*i] - want_l) < 0.000002f &&
                                fabsf(output[2*i+1] - want_r) < 0.000002f,
                                "impulse matches measured HRTF convolution");
                        cross_energy += output[2*i + 1-channel] *
                                        output[2*i + 1-channel];
                    }
                    require(cross_energy > 0.000001, "both ears contain HRTF");
                    require(ik_spatial_frames(dsp) == 512, "real frame count");
                    ik_spatial_reset(dsp);
                    memset(input, 0, sizeof(input));
                    ik_spatial_process(dsp, input, output, 512);
                    for (int i = 0; i < 1024; ++i)
                        require(output[i] == 0, "seek clears previous tail");
                    ik_spatial_destroy(dsp);
                    ++cases;
                }
            }
        }
        IkSpatial *dsp = ik_spatial_create(rates[r]);
        float input[4096], output[4096];
        for (int i = 0; i < 4096; ++i)
            input[i] = 0.93f * sinf(i * 0.173f);
        ik_spatial_configure(dsp, 0, 1, 0, 0, 0);
        ik_spatial_process(dsp, input, output, 2048);
        require(memcmp(input, output, sizeof(input)) == 0, "off is exact bypass");
        ik_spatial_configure(dsp, 1, 0, 0, 0, 0);
        ik_spatial_process(dsp, input, output, 2048);
        require(memcmp(input, output, sizeof(input)) == 0, "zero is exact bypass");
        for (int strength = 1; strength <= 4; ++strength) {
            ik_spatial_reset(dsp);
            ik_spatial_configure(dsp, 1, strength * 0.25f, 90, 30, 1);
            ik_spatial_process(dsp, input, output, 2048);
            for (int i = 0; i < 4096; ++i)
                require(isfinite(output[i]) && fabsf(output[i]) <= 1.0f,
                        "strength transition finite and bounded");
            ++cases;
        }
        require(ik_spatial_configure(dsp, 1, NAN, 0, 0, 0) != 0,
                "bad controls rejected");
        ik_spatial_destroy(dsp);
    }
    require(ik_spatial_create(8000) == NULL, "unsupported rate rejected");
    printf("U07 native signal gate: %d full-direction cases PASS\n", cases);
    return 0;
}
