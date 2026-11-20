/* IK Music 共享 HRTF FIR。数据版权与署名见 data/MIT-KEMAR-LICENSE。 */
#include "ik_spatial.h"
#include <math.h>
#include <stdlib.h>
#include <string.h>
#include "ik_hrtf_data.h"

struct IkSpatial {
    float history[2][IK_SPATIAL_TAPS * 2];
    float kernel[2][2][IK_SPATIAL_TAPS];
    float previous[2][2][IK_SPATIAL_TAPS];
    int rate, cursor, ramp, ramp_length;
    uint64_t frames;
};

int ik_spatial_abi_version(void) { return 1; }

IkSpatial *ik_spatial_create(int rate) {
    if (rate != 44100 && rate != 48000) return NULL;
    IkSpatial *s = calloc(1, sizeof(*s));
    if (!s) return NULL;
    s->rate = rate;
    s->ramp_length = rate / 50;
    s->kernel[0][0][0] = s->kernel[1][1][0] = 1.0f;
    return s;
}

void ik_spatial_destroy(IkSpatial *s) { free(s); }
void ik_spatial_reset(IkSpatial *s) {
    if (!s) return;
    memset(s->history, 0, sizeof(s->history));
    s->cursor = 0;
    s->frames = 0;
    s->ramp = 0;
}

int ik_spatial_configure(IkSpatial *s, int enabled, float strength,
                         float azimuth, float elevation, int smooth) {
    if (!s || !isfinite(strength) || !isfinite(azimuth) || !isfinite(elevation) ||
        strength < 0 || strength > 1 || elevation < -30 || elevation > 30 ||
        azimuth < -180 || azimuth > 180) return -1;
    float old_mix = s->ramp ? 1.0f - (float)s->ramp/s->ramp_length : 1;
    for (int source = 0; source < 2; ++source)
        for (int ear = 0; ear < 2; ++ear)
            for (int tap = 0; tap < IK_SPATIAL_TAPS; ++tap)
                s->previous[source][ear][tap] += old_mix *
                    (s->kernel[source][ear][tap] - s->previous[source][ear][tap]);
    memset(s->kernel, 0, sizeof(s->kernel));
    float amount = enabled ? strength : 0;
    if (amount == 0) {
        s->kernel[0][0][0] = s->kernel[1][1][0] = 1;
    } else {
        float elev_index = (elevation + 30) / 30;
        int e0 = (int)elev_index, e1 = e0 < 2 ? e0+1 : e0;
        float eb = elev_index-e0;
        int rate_index = s->rate == 48000;
        for (int source = 0; source < 2; ++source) {
            float angle = azimuth + (source == 0 ? -30 : 30);
            while (angle < 0) angle += 360;
            while (angle >= 360) angle -= 360;
            float index = angle/15;
            int a0 = (int)index, a1 = (a0+1)%24;
            float ab = index-a0;
            for (int ear = 0; ear < 2; ++ear) {
                for (int tap = 0; tap < IK_SPATIAL_TAPS; ++tap) {
                    float lo = ik_hrtf[rate_index][e0][a0][ear][tap]*(1-ab) +
                               ik_hrtf[rate_index][e0][a1][ear][tap]*ab;
                    float hi = ik_hrtf[rate_index][e1][a0][ear][tap]*(1-ab) +
                               ik_hrtf[rate_index][e1][a1][ear][tap]*ab;
                    s->kernel[source][ear][tap] = 0.5f*amount*(lo*(1-eb)+hi*eb);
                }
            }
            /* 延迟对齐的干声；开启/关闭由整个核的 20ms 平滑过渡处理。 */
            s->kernel[source][source][s->rate == 48000 ? 18 : 16] += 1-amount;
        }
    }
    s->ramp = smooth ? s->ramp_length : 0;
    return 0;
}

int ik_spatial_process(IkSpatial *s, const float *in, float *out, size_t frames) {
    if (!s || !in || !out) return -1;
    for (size_t i = 0; i < frames; ++i) {
        s->cursor = (s->cursor + IK_SPATIAL_TAPS-1)%IK_SPATIAL_TAPS;
        for (int source = 0; source < 2; ++source) {
            float value = in[2*i+source];
            if (!isfinite(value)) value = 0;
            s->history[source][s->cursor] = value;
            s->history[source][s->cursor+IK_SPATIAL_TAPS] = value;
        }
        float blend = s->ramp ? 1.0f-(float)s->ramp/s->ramp_length : 1;
        for (int ear = 0; ear < 2; ++ear) {
            float total = 0, previous = 0;
            for (int source = 0; source < 2; ++source) {
                const float *history = s->history[source]+s->cursor;
                for (int tap = 0; tap < IK_SPATIAL_TAPS; ++tap) {
                    total += history[tap]*s->kernel[source][ear][tap];
                    if (s->ramp) previous += history[tap]*s->previous[source][ear][tap];
                }
            }
            total = previous*(1-blend)+total*blend;
            out[2*i+ear] = fmaxf(-1.0f, fminf(1.0f, total));
        }
        if (s->ramp) --s->ramp;
    }
    s->frames += frames;
    return 0;
}

uint64_t ik_spatial_frames(const IkSpatial *s) { return s ? s->frames : 0; }
const float *ik_spatial_kernel(const IkSpatial *s, int source, int ear) {
    return s && source >= 0 && source < 2 && ear >= 0 && ear < 2 ?
        s->kernel[source][ear] : NULL;
}
