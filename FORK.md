# SmartNotes fork notes

This fork adds an optional Android Vulkan transcription backend without changing
the default CPU behavior or Apple targets.

## Versioning

- Upstream base: `sk3llo/whisper_ggml` `master` at `9bd9e7f` (package 2.8.1).
- Fork version: `2.8.1+smartnotes.1`.
- The app pins an immutable commit on `smartnotes/vulkan`; never reference the
  branch name. Tag a release separately when a new version is published.

## Android libraries

| File | Backend | ABI | API |
| --- | --- | --- | --- |
| `libwhisper.so` | CPU | all existing ABIs | 24 |
| `libwhisper_vulkan.so` | Vulkan | `arm64-v8a` | 28 |

`libwhisper_vulkan.so` is checked in under `android/src/main/jniLibs/arm64-v8a/`
because the current Gradle build targets a single API level for the plugin. The
CPU library remains unchanged and is the only library loaded on non-Android
platforms or when the caller does not select Vulkan.

Rebuild the optional library with:

```sh
tool/build_android_vulkan.sh /path/to/scratch
```

The script downloads the pinned whisper.cpp v1.9.1, SPIRV-Headers, and
Vulkan-Headers archives, verifies SHA-256, builds with NDK 29 and API 28, strips
the result, and copies it into `jniLibs`. The checked-in
Vulkan sources are not vendored a second time: the script builds a fresh
checksum-pinned tree, so the CPU CMake target and its vendored whisper.cpp stay
untouched.

## Native behavior

- `Whisper(backend: WhisperBackend.vulkan)` loads `libwhisper_vulkan.so`.
- `Whisper.probeCapabilities()` enumerates Vulkan devices without loading a model.
- Responses include the backend actually used; failures carry stable
  `WhisperException` codes.
- The Vulkan library reads `GGML_VK_DISABLE_F16` and
  `GGML_VK_PREFER_HOST_MEMORY` in a load-time initializer, before any capability
  probe can create the device. It disables Flash Attention only for the Vulkan
  context.
- `--exclude-libs,ALL` keeps ggml/whisper symbols local to each shared library.

## Error boundary and reproducibility

`tool/vulkan/prepare_source.py` applies a checked, Vulkan-only adapter to the
downloaded source: state/context ownership survives C++ exceptions and
`whisper_ggml_uses_vulkan` inspects the actual context's backends. A Vulkan
request that upstream silently initializes on CPU is rejected with
`vulkan_unavailable`; it is never reported as GPU success. The request boundary
frees failed contexts and translates native exceptions into a recoverable code.
Fatal signals and driver aborts still require the caller's persisted crash guard.

Host regression test (requires a C++17 compiler):

```sh
clang++ -std=c++17 -Iandroid/src/whisper/whisper.cpp/ggml/include \
  tool/vulkan/native_boundary_test.cpp -o /path/to/scratch/native-boundary-test
/path/to/scratch/native-boundary-test /path/to/scratch/fixture.wav
```

When rebasing, retain the adapter and rerun both the host test and the full
Android rebuild from a clean scratch directory. Changed source anchors fail the
build rather than skipping the exception-ownership patch.
