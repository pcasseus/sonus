class AnalyticsRankedEntity {
  const AnalyticsRankedEntity({
    required this.entityId,
    required this.qualifiedStreamCount,
    required this.firstQualifiedAt,
    required this.lastQualifiedAt,
  });

  final String entityId;
  final int qualifiedStreamCount;
  final DateTime firstQualifiedAt;
  final DateTime lastQualifiedAt;
}
