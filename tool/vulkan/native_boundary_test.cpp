// Host test of the real request/JSON/RAII boundary. Only the Whisper runtime is
// substituted so driver exceptions and silent CPU fallback are deterministic.
#define WHISPER_GGML_VULKAN 1
#include "../../android/src/whisper/main.cpp"
#include <cassert>
#include <stdexcept>

struct whisper_context {};
static int alive = 0;
static bool gpu = true;
static bool fail_inference = false;
static bool fail_init = false;
static int inference_calls = 0;

extern "C" {
whisper_context_params whisper_context_default_params() { return {}; }
whisper_full_params whisper_full_default_params(whisper_sampling_strategy) { return {}; }
whisper_vad_params whisper_vad_default_params() { return {}; }
int whisper_lang_id(const char *) { return 0; }
whisper_context * whisper_init_from_file_with_params(const char *, whisper_context_params) {
    if (fail_init) throw std::runtime_error("driver initialization failed");
    ++alive;
    return new whisper_context;
}
void whisper_free(whisper_context * ctx) { if (ctx) { --alive; delete ctx; } }
int whisper_full(whisper_context *, whisper_full_params, const float *, int) {
    ++inference_calls;
    if (fail_inference) throw std::runtime_error("device lost");
    return 0;
}
int whisper_full_n_segments(whisper_context *) { return 1; }
const char * whisper_full_get_segment_text(whisper_context *, int) { return "public fixture"; }
int64_t whisper_full_get_segment_t0(whisper_context *, int) { return 0; }
int64_t whisper_full_get_segment_t1(whisper_context *, int) { return 100; }
bool whisper_full_get_segment_speaker_turn_next(whisper_context *, int) { return false; }
bool whisper_ggml_uses_vulkan(const whisper_context *) { return gpu; }
int ggml_backend_vk_get_device_count() { return gpu ? 1 : 0; }
void ggml_backend_vk_get_device_description(int, char *, size_t) {}
void ggml_backend_vk_get_device_memory(int, size_t * free, size_t * total) { *free = *total = 0; }
}

int main(int argc, char ** argv) {
    assert(argc == 2);
    drwav_data_format format = {};
    format.container = drwav_container_riff;
    format.format = DR_WAVE_FORMAT_PCM;
    format.channels = 1;
    format.sampleRate = 16000;
    format.bitsPerSample = 16;
    drwav wav;
    assert(drwav_init_file_write(&wav, argv[1], &format, nullptr));
    int16_t samples[160] = {};
    drwav_write_pcm_frames(&wav, 160, samples);
    drwav_uninit(&wav);

    json body = {{"@type", "getTextFromWavFile"}, {"threads", 1},
        {"is_verbose", false}, {"is_translate", false}, {"language", "en"},
        {"is_special_tokens", false}, {"is_no_timestamps", true},
        {"model", "fixture.bin"}, {"audio", argv[1]}, {"split_on_word", false},
        {"diarize", false}};
    auto call = [&]() {
        std::string input = body.dump();
        char * raw = request(input.data());
        json response = json::parse(raw);
        free(raw);
        return response;
    };

    fail_init = true;
    assert(call()["code"] == "vulkan_inference_failed");
    assert(alive == 0);
    fail_init = false;
    fail_inference = true;
    body["keep_model_loaded"] = true;
    assert(call()["code"] == "vulkan_inference_failed");
    assert(alive == 0); // failed contexts are freed, never cached
    fail_inference = false;
    body["keep_model_loaded"] = false;
    gpu = false;
    int before = inference_calls;
    assert(call()["code"] == "vulkan_unavailable");
    assert(inference_calls == before && alive == 0);
    gpu = true;
    auto response = call();
    assert(response["backend"] == "vulkan" && response["text"] == "public fixture");
    assert(alive == 0);
    body["threads"] = "bad input";
    assert(call()["code"] == "invalid_request");
    std::remove(argv[1]);
    puts("Native boundary tests passed");
}
