import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:sonus_next/features/account/data/mappers/supabase_account_user_mapper.dart';

void main() {
  group('SupabaseAccountUserMapper', () {
    test('maps Supabase user fields and Google metadata', () {
      final user = _user(
        email: ' listener@example.com ',
        metadata: <String, dynamic>{
          'full_name': ' Pat Listener ',
          'avatar_url': ' https://example.com/avatar.jpg ',
        },
      );

      final accountUser = SupabaseAccountUserMapper.fromUser(user);

      expect(accountUser.id, 'user-1');
      expect(accountUser.email, 'listener@example.com');
      expect(accountUser.displayName, 'Pat Listener');
      expect(accountUser.avatarUrl, 'https://example.com/avatar.jpg');
    });

    test('falls back to name and picture metadata', () {
      final user = _user(
        metadata: <String, dynamic>{
          'name': 'Fallback Name',
          'picture': 'https://example.com/picture.jpg',
        },
      );

      final accountUser = SupabaseAccountUserMapper.fromUser(user);

      expect(accountUser.displayName, 'Fallback Name');
      expect(accountUser.avatarUrl, 'https://example.com/picture.jpg');
    });

    test('falls back when primary metadata values are blank', () {
      final user = _user(
        metadata: <String, dynamic>{
          'full_name': '   ',
          'name': 'Fallback Name',
          'avatar_url': '',
          'picture': 'https://example.com/fallback.jpg',
        },
      );

      final accountUser = SupabaseAccountUserMapper.fromUser(user);

      expect(accountUser.displayName, 'Fallback Name');
      expect(accountUser.avatarUrl, 'https://example.com/fallback.jpg');
    });

    test('ignores non-string metadata values', () {
      final user = _user(
        metadata: <String, dynamic>{
          'full_name': 123,
          'name': 'Safe Name',
          'avatar_url': <String>['invalid'],
          'picture': 'https://example.com/safe.jpg',
        },
      );

      final accountUser = SupabaseAccountUserMapper.fromUser(user);

      expect(accountUser.displayName, 'Safe Name');
      expect(accountUser.avatarUrl, 'https://example.com/safe.jpg');
    });

    test('normalizes blank optional values to null', () {
      final user = _user(
        email: '   ',
        metadata: <String, dynamic>{'full_name': ' ', 'avatar_url': ''},
      );

      final accountUser = SupabaseAccountUserMapper.fromUser(user);

      expect(accountUser.email, isNull);
      expect(accountUser.displayName, isNull);
      expect(accountUser.avatarUrl, isNull);
    });
  });
}

User _user({
  String? email = 'listener@example.com',
  Map<String, dynamic>? metadata,
}) {
  return User(
    id: 'user-1',
    appMetadata: const <String, dynamic>{},
    userMetadata: metadata,
    aud: 'authenticated',
    email: email,
    createdAt: '2026-09-12T00:00:00.000Z',
  );
}
