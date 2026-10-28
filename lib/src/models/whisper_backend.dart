/// Native backend used for a transcription request.
///
/// Android builds ship `libwhisper.so` (CPU) and, on arm64, an optional
/// `libwhisper_vulkan.so`. Every other platform only supports [cpu].
enum WhisperBackend { cpu, vulkan }
