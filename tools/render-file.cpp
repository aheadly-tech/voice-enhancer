// render-file.cpp — Process raw float32 audio through Voice Enhancer presets.
//
// Usage:
//   render-file <input.raw> <output_prefix>
//
// Input:  mono float32 PCM at 48 kHz (no header)
// Output: <prefix>_natural.raw, <prefix>_broadcast.raw, etc.

#include "engine_c_api.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <vector>

static const int kSampleRate = 48000;
static const int kBlockSize  = 512;

struct PresetInfo {
    ve_preset_t preset;
    const char* suffix;
};

static const PresetInfo kPresets[] = {
    { VE_PRESET_NATURAL,   "natural"   },
    { VE_PRESET_BROADCAST, "broadcast" },
    { VE_PRESET_CLARITY,   "clarity"   },
    { VE_PRESET_WARM,      "warm"      },
};

static std::vector<float> read_raw(const char* path) {
    FILE* f = fopen(path, "rb");
    if (!f) { fprintf(stderr, "Cannot open %s\n", path); exit(1); }
    fseek(f, 0, SEEK_END);
    long bytes = ftell(f);
    fseek(f, 0, SEEK_SET);
    std::vector<float> buf(bytes / sizeof(float));
    fread(buf.data(), sizeof(float), buf.size(), f);
    fclose(f);
    return buf;
}

static void write_raw(const char* path, const float* data, size_t n) {
    FILE* f = fopen(path, "wb");
    if (!f) { fprintf(stderr, "Cannot write %s\n", path); exit(1); }
    fwrite(data, sizeof(float), n, f);
    fclose(f);
}

int main(int argc, char** argv) {
    if (argc < 3) {
        fprintf(stderr, "Usage: render-file <input.raw> <output_prefix>\n");
        return 1;
    }

    const char* input_path = argv[1];
    const char* prefix     = argv[2];

    auto input = read_raw(input_path);
    printf("Read %zu samples (%.2fs at %d Hz)\n",
           input.size(), (double)input.size() / kSampleRate, kSampleRate);

    for (auto& pi : kPresets) {
        ve_engine_t* engine = ve_engine_create();
        if (!engine) { fprintf(stderr, "Failed to create engine\n"); return 1; }

        ve_engine_prepare(engine, kSampleRate, kBlockSize);
        ve_engine_set_preset(engine, pi.preset);

        // Copy input so we can process in-place
        std::vector<float> buf = input;

        // Process in blocks
        size_t pos = 0;
        while (pos < buf.size()) {
            int32_t frames = (int32_t)std::min((size_t)kBlockSize, buf.size() - pos);
            ve_engine_process(engine, buf.data() + pos, frames);
            pos += frames;
        }

        char out_path[512];
        snprintf(out_path, sizeof(out_path), "%s_%s.raw", prefix, pi.suffix);
        write_raw(out_path, buf.data(), buf.size());
        printf("Wrote %s (%s preset)\n", out_path, ve_preset_name(pi.preset));

        ve_engine_destroy(engine);
    }

    return 0;
}
