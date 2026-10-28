import 'dart:convert';
import 'dart:ffi';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:universal_io/io.dart';
import 'package:whisper_ggml/src/models/whisper_model.dart';
import 'package:whisper_ggml/src/whisper_audio_convert.dart';

import 'models/requests/capabilities_request.dart';
import 'models/requests/release_model_request.dart';
import 'models/requests/transcribe_request.dart';
import 'models/requests/transcribe_request_dto.dart';
import 'models/requests/version_request.dart';
import 'models/responses/whisper_capabilities.dart';
import 'models/responses/whisper_transcribe_response.dart';
import 'models/responses/whisper_version_response.dart';
import 'models/whisper_backend.dart';
import 'models/whisper_dto.dart';
import 'whisper_exception.dart';

export 'models/_models.dart';
export 'whisper_audio_convert.dart';
export 'whisper_exception.dart';

/// Native request type
typedef WReqNative = Pointer<Utf8> Function(Pointer<Utf8> body);

/// Entry point
class Whisper {
  /// [model] is required
  /// [modelDir] is path where downloaded model will be stored.
  /// Default to library directory
  ///
  /// [backend] selects the native library on Android. [WhisperBackend.vulkan]
  /// requires an arm64 build with `libwhisper_vulkan.so`; every other platform
  /// only supports [WhisperBackend.cpu].
  const Whisper({
    required this.model,
    this.modelDir,
    this.backend = WhisperBackend.cpu,
  });

  /// model used for transcription
  final WhisperModel model;

  /// override of model storage path
  final String? modelDir;

  /// native backend requested for this instance
  final WhisperBackend backend;

  static DynamicLibrary _openLibrary(WhisperBackend backend) {
    try {
      if (Platform.isAndroid) {
        return DynamicLibrary.open(
          backend == WhisperBackend.vulkan
              ? 'libwhisper_vulkan.so'
              : 'libwhisper.so',
        );
      }
      if (backend == WhisperBackend.vulkan) {
        throw const WhisperException(
          'vulkan_unavailable',
          'Vulkan is only available on Android arm64 builds.',
        );
      }
      if (Platform.isWindows) {
        return DynamicLibrary.open('whisper_ggml.dll');
      }
      if (Platform.isLinux) {
        return DynamicLibrary.open('libwhisper_ggml.so');
      }
      return DynamicLibrary.process();
    } on WhisperException {
      rethrow;
    } catch (error) {
      throw WhisperException('native_library_unavailable', error.toString());
    }
  }

  Future<Map<String, dynamic>> _request({
    required WhisperRequestDto whisperRequest,
  }) => _requestWithBackend(backend, whisperRequest);

  static Future<Map<String, dynamic>> _requestWithBackend(
    WhisperBackend backend,
    WhisperRequestDto whisperRequest,
  ) {
    return Isolate.run(() async {
      final DynamicLibrary library = _openLibrary(backend);
      final Pointer<Utf8> data = whisperRequest.toRequestString().toNativeUtf8();
      Pointer<Utf8>? res;
      try {
        res = library.lookupFunction<WReqNative, WReqNative>('request').call(data);
        final Map<String, dynamic> result =
            json.decode(res.toDartString()) as Map<String, dynamic>;
        return result;
      } finally {
        malloc.free(data);
        if (res != null) {
          // Native responses are malloc'd specifically so this free is valid.
          malloc.free(res);
        }
      }
    });
  }

  /// Transcribe audio file to text
  ///
  /// [onProgress] is invoked with whisper.cpp's transcription progress
  /// (0–100, coarse steps) while inference runs.
  Future<WhisperTranscribeResponse> transcribe({
    required TranscribeRequest transcribeRequest,
    required String modelPath,
    void Function(int percent)? onProgress,
  }) async {
    // A listener callable may be invoked from whisper's worker thread;
    // it delivers to this isolate. Kept open until the request finishes.
    final NativeCallable<Void Function(Int32)>? progressCallable =
        onProgress == null
            ? null
            : NativeCallable<Void Function(Int32)>.listener(onProgress);
    try {
      final WhisperAudioConvert converter = WhisperAudioConvert(
        audioInput: File(transcribeRequest.audio),
        audioOutput: File('${transcribeRequest.audio}.wav'),
      );

      final File? convertedFile = await converter.convert();

      final TranscribeRequest req = transcribeRequest.copyWith(
        audio: convertedFile?.path ?? transcribeRequest.audio,
      );

      final Map<String, dynamic> result = await _request(
        whisperRequest: TranscribeRequestDto.fromTranscribeRequest(
          req,
          modelPath,
          progressCallbackAddress: progressCallable?.nativeFunction.address,
        ),
      );

      if (result['text'] == null) {
        throw WhisperException(
          result['code'] as String? ?? 'native_error',
          result['message'] as String? ?? 'Unknown native error',
        );
      }
      return WhisperTranscribeResponse.fromJson(result);
    } catch (e) {
      debugPrint(e.toString());
      rethrow;
    } finally {
      progressCallable?.close();
    }
  }

  /// Reports the capabilities of the selected backend without loading a model.
  Future<WhisperCapabilities> capabilities() async {
    final Map<String, dynamic> result = await _request(
      whisperRequest: const CapabilitiesRequest(),
    );
    return WhisperCapabilities.fromJson(result);
  }

  /// Probes a backend without an instance or a speech model.
  ///
  /// The Vulkan library is only present on Android arm64. Callers should treat
  /// any [WhisperException] as "unavailable" and keep using the CPU backend.
  static Future<WhisperCapabilities> probeCapabilities({
    WhisperBackend backend = WhisperBackend.vulkan,
  }) async {
    final Map<String, dynamic> result = await _requestWithBackend(
      backend,
      const CapabilitiesRequest(),
    );
    return WhisperCapabilities.fromJson(result);
  }

  /// Free the model parked in native memory by a transcription with
  /// `keepModelLoaded: true`. Safe to call when nothing is parked.
  ///
  /// A transcription still in flight keeps its model until it completes;
  /// one that was started with `keepModelLoaded: true` parks the model
  /// again when it finishes.
  Future<void> releaseModel() async {
    final Map<String, dynamic> result = await _request(
      whisperRequest: const ReleaseModelRequest(),
    );
    if (result['@type'] == 'error') {
      throw WhisperException(
        result['code'] as String? ?? 'native_error',
        result['message'] as String? ?? 'Unknown native error',
      );
    }
  }

  /// Get whisper version
  Future<String?> getVersion() async {
    final Map<String, dynamic> result = await _request(
      whisperRequest: const VersionRequest(),
    );

    final WhisperVersionResponse response = WhisperVersionResponse.fromJson(
      result,
    );
    return response.message;
  }
}
