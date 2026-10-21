import 'package:flutter_test/flutter_test.dart';

import 'package:sonus_next/features/sync/data/mappers/supabase_cloud_record_mapper.dart';
import 'package:sonus_next/features/sync/domain/models/sync_data_contract.dart';

void main() {
  Map<String, dynamic> artistRow() => {
    'id': 'artist-1',
    'user_id': 'user-1',
    'name': 'Artist Name',
    'canonical_name': 'artist name',
    'is_blacklisted': false,
    'header_artwork_id': null,
    'top_artists_artwork_id': null,
    'created_at': '2026-10-16T10:00:00.000Z',
    'updated_at': '2026-10-16T11:00:00.000Z',
    'server_updated_at': '2026-10-16T12:00:00.000Z',
    'deleted_at': null,
  };

  test('preserves the exact cloud server revision', () {
    final row = artistRow()..['server_revision'] = 17;

    final item = SupabaseCloudRecordMapper.fromRow(
      entityType: CloudDataEntity.artist,
      row: row,
    );

    expect(item.serverRevision, 17);
    expect(item.record.id, 'artist-1');
  });

  test('accepts initial server revision 1', () {
    final row = artistRow()..['server_revision'] = 1;

    final item = SupabaseCloudRecordMapper.fromRow(
      entityType: CloudDataEntity.artist,
      row: row,
    );

    expect(item.serverRevision, 1);
  });

  test('rejects missing server revision', () {
    expect(
      () => SupabaseCloudRecordMapper.fromRow(
        entityType: CloudDataEntity.artist,
        row: artistRow(),
      ),
      throwsStateError,
    );
  });

  test('rejects invalid revision values', () {
    for (final invalid in <Object?>[null, 0, -1, '1', 1.5, true]) {
      final row = artistRow()..['server_revision'] = invalid;

      expect(
        () => SupabaseCloudRecordMapper.fromRow(
          entityType: CloudDataEntity.artist,
          row: row,
        ),
        throwsStateError,
        reason: 'Revision $invalid should be rejected.',
      );
    }
  });
}
