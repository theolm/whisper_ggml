/// Stable native error surfaced across the FFI boundary.
///
/// [code] is intentionally machine-readable so callers can decide whether a
/// failure is recoverable on another backend. [message] never contains audio
/// or transcript content.
class WhisperException implements Exception {
  const WhisperException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => 'WhisperException($code): $message';
}
