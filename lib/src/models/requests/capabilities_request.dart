import 'dart:convert';

import 'package:whisper_ggml/src/models/whisper_dto.dart';

/// Requests backend capabilities without loading a speech model.
class CapabilitiesRequest implements WhisperRequestDto {
  const CapabilitiesRequest();

  @override
  String get specialType => 'getCapabilities';

  @override
  String toRequestString() {
    return json.encode({'@type': specialType});
  }
}
