/* IK Music libavfilter 薄适配；FIR 算法与 Android 共用 ik_spatial.c。 */
#include "libavutil/channel_layout.h"
#include "libavutil/dict.h"
#include "libavutil/opt.h"
#include "avfilter.h"
#include "audio.h"
#include "formats.h"
#include "ik_spatial.h"
#include <stdatomic.h>

/* 原子观测口避免 mpv 0.36 在 metadata 查询时递归持有核心锁。 */
static atomic_uint_fast64_t observed_request;
static atomic_uint_fast64_t observed_frames;
__declspec(dllexport) int64_t ik_spatial_processed_frames(int64_t request);
__declspec(dllexport) int64_t ik_spatial_processed_frames(int64_t request) {
    uint64_t before = atomic_load(&observed_request);
    uint64_t frames = atomic_load(&observed_frames);
    return before == (uint64_t)request &&
        atomic_load(&observed_request) == before ? (int64_t)frames : 0;
}

typedef struct IkHrtfContext {
    const AVClass *class;
    int enabled;
    double strength, azimuth, elevation;
    int64_t request;
    IkSpatial *dsp;
} IkHrtfContext;

#define OFFSET(x) offsetof(IkHrtfContext, x)
#define FLAGS AV_OPT_FLAG_AUDIO_PARAM|AV_OPT_FLAG_FILTERING_PARAM|AV_OPT_FLAG_RUNTIME_PARAM
static const AVOption ikhrtf_options[] = {
    {"enabled", "Enable headphone HRTF", OFFSET(enabled), AV_OPT_TYPE_BOOL, {.i64=1}, 0, 1, FLAGS},
    {"strength", "Spatial mix", OFFSET(strength), AV_OPT_TYPE_DOUBLE, {.dbl=0.65}, 0, 1, FLAGS},
    {"azimuth", "Stage azimuth", OFFSET(azimuth), AV_OPT_TYPE_DOUBLE, {.dbl=0}, -180, 180, FLAGS},
    {"elevation", "Stage elevation", OFFSET(elevation), AV_OPT_TYPE_DOUBLE, {.dbl=0}, -30, 30, FLAGS},
    {"request", "Application request generation", OFFSET(request), AV_OPT_TYPE_INT64, {.i64=0}, 0, INT64_MAX, FLAGS},
    {NULL}
};
AVFILTER_DEFINE_CLASS(ikhrtf);

static int query_formats(AVFilterContext *ctx) {
    AVFilterFormats *formats = NULL, *rates = NULL;
    AVFilterChannelLayouts *layouts = NULL;
    int result;
    if ((result=ff_add_format(&formats, AV_SAMPLE_FMT_FLT)) < 0 ||
        (result=ff_set_common_formats(ctx, formats)) < 0 ||
        (result=ff_add_channel_layout(&layouts, &(AVChannelLayout)AV_CHANNEL_LAYOUT_STEREO)) < 0 ||
        (result=ff_set_common_channel_layouts(ctx, layouts)) < 0 ||
        (result=ff_add_format(&rates, 44100)) < 0 ||
        (result=ff_add_format(&rates, 48000)) < 0) return result;
    return ff_set_common_samplerates(ctx, rates);
}

static int config_input(AVFilterLink *inlink) {
    IkHrtfContext *s = inlink->dst->priv;
    ik_spatial_destroy(s->dsp);
    s->dsp = ik_spatial_create(inlink->sample_rate);
    atomic_store(&observed_frames, 0);
    atomic_store(&observed_request, s->request);
    if (!s->dsp) return AVERROR(EINVAL);
    return ik_spatial_configure(s->dsp, s->enabled, s->strength,
                                 s->azimuth, s->elevation, 1);
}

static int filter_frame(AVFilterLink *inlink, AVFrame *in) {
    AVFilterContext *ctx = inlink->dst;
    IkHrtfContext *s = ctx->priv;
    AVFrame *out = in;
    if (!av_frame_is_writable(in)) {
        out = ff_get_audio_buffer(ctx->outputs[0], in->nb_samples);
        if (!out) { av_frame_free(&in); return AVERROR(ENOMEM); }
        av_frame_copy_props(out, in);
    }
    int result = ik_spatial_process(s->dsp, (const float *)in->data[0],
                                     (float *)out->data[0], in->nb_samples);
    if (result < 0) {
        if (out != in) av_frame_free(&out);
        av_frame_free(&in);
        return AVERROR(EINVAL);
    }
    av_dict_set_int(&out->metadata, "ik_frames", ik_spatial_frames(s->dsp), 0);
    av_dict_set_int(&out->metadata, "ik_request", s->request, 0);
    av_dict_set_int(&out->metadata, "ik_rate", inlink->sample_rate, 0);
    av_dict_set(&out->metadata, "ik_profile", "MIT-KEMAR-diffuse-1994", 0);
    atomic_store(&observed_frames, ik_spatial_frames(s->dsp));
    atomic_store(&observed_request, s->request);
    if (out != in) av_frame_free(&in);
    return ff_filter_frame(ctx->outputs[0], out);
}

static int process_command(AVFilterContext *ctx, const char *command,
                           const char *args, char *response, int length, int flags) {
    IkHrtfContext *s = ctx->priv;
    int result = ff_filter_process_command(ctx, command, args, response, length, flags);
    if (result < 0 || !s->dsp) return result;
    return ik_spatial_configure(s->dsp, s->enabled, s->strength,
                                 s->azimuth, s->elevation, 1);
}

static void uninit(AVFilterContext *ctx) {
    IkHrtfContext *s = ctx->priv;
    if (atomic_load(&observed_request) == (uint64_t)s->request)
        atomic_store(&observed_frames, 0);
    ik_spatial_destroy(s->dsp);
    s->dsp = NULL;
}

static const AVFilterPad inputs[] = {{
    .name="default", .type=AVMEDIA_TYPE_AUDIO,
    .filter_frame=filter_frame, .config_props=config_input,
}};
static const AVFilterPad outputs[] = {{.name="default", .type=AVMEDIA_TYPE_AUDIO}};
const AVFilter ff_af_ikhrtf = {
    .name="ikhrtf", .description=NULL_IF_CONFIG_SMALL("IK measured HRTF binaural rendering"),
    .priv_size=sizeof(IkHrtfContext), .priv_class=&ikhrtf_class,
    .uninit=uninit, FILTER_INPUTS(inputs), FILTER_OUTPUTS(outputs),
    FILTER_QUERY_FUNC(query_formats), .process_command=process_command,
};
