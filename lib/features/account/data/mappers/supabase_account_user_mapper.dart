import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/entities/account_user.dart';

abstract final class SupabaseAccountUserMapper {
  static AccountUser fromUser(User user) {
    final metadata = user.userMetadata;

    return AccountUser(
      id: user.id,
      email: _clean(user.email),
      displayName: _firstNonBlank(metadata?['full_name'], metadata?['name']),
      avatarUrl: _firstNonBlank(metadata?['avatar_url'], metadata?['picture']),
    );
  }

  static String? _firstNonBlank(Object? primary, Object? fallback) {
    return _cleanObject(primary) ?? _cleanObject(fallback);
  }

  static String? _cleanObject(Object? value) {
    if (value is! String) {
      return null;
    }

    return _clean(value);
  }

  static String? _clean(String? value) {
    final trimmed = value?.trim();

    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }

    return trimmed;
  }
}
