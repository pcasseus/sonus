import 'audio_metadata.dart';

enum MetadataSource { embedded, mixed, fallback }

class ResolvedMetadata {
  const ResolvedMetadata({required this.metadata, required this.source});

  final AudioMetadata metadata;
  final MetadataSource source;

  bool get usedFallback => source != MetadataSource.embedded;
}
