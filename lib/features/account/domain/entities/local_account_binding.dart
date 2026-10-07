class LocalAccountBinding {
  const LocalAccountBinding({
    required this.userId,
    required this.boundAt,
    required this.updatedAt,
  });

  final String userId;
  final DateTime boundAt;
  final DateTime updatedAt;

  LocalAccountBinding copyWith({
    String? userId,
    DateTime? boundAt,
    DateTime? updatedAt,
  }) {
    return LocalAccountBinding(
      userId: userId ?? this.userId,
      boundAt: boundAt ?? this.boundAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
