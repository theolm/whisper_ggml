/// Backend capabilities reported by the native library.
///
/// Probing never loads a model. It only enumerates the Vulkan devices the
/// runtime can see and confirms which library answered the request.
class WhisperCapabilities {
  const WhisperCapabilities({
    required this.backend,
    required this.vulkanCompiled,
    required this.vulkanAvailable,
    this.deviceCount = 0,
    this.deviceName,
    this.freeMemoryBytes,
    this.totalMemoryBytes,
    this.runtime,
  });

  final String backend;
  final bool vulkanCompiled;
  final bool vulkanAvailable;
  final int deviceCount;
  final String? deviceName;
  final int? freeMemoryBytes;
  final int? totalMemoryBytes;
  final String? runtime;

  bool get isVulkan => backend == 'vulkan';

  factory WhisperCapabilities.fromJson(Map<String, dynamic> json) {
    int? integer(Object? value) => value is num ? value.toInt() : null;
    return WhisperCapabilities(
      backend: json['backend'] as String? ?? 'cpu',
      vulkanCompiled: json['vulkan_compiled'] == true,
      vulkanAvailable: json['vulkan_available'] == true,
      deviceCount: integer(json['device_count']) ?? 0,
      deviceName: json['device_name'] as String?,
      freeMemoryBytes: integer(json['free_memory_bytes']),
      totalMemoryBytes: integer(json['total_memory_bytes']),
      runtime: json['runtime'] as String?,
    );
  }

  @override
  String toString() =>
      'WhisperCapabilities(backend: $backend, vulkanCompiled: $vulkanCompiled, '
      'vulkanAvailable: $vulkanAvailable, deviceCount: $deviceCount, '
      'deviceName: $deviceName)';
}
