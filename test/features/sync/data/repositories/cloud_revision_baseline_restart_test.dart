import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/features/sync/data/daos/cloud_revision_baseline_dao.dart';
import 'package:sonus_next/features/sync/data/repositories/sqlite_cloud_revision_baseline_repository.dart';
import 'package:sonus_next/features/sync/domain/models/sync_data_contract.dart';

void main() {
  sqfliteFfiInit();

  test('cloud revision survives database close and reopen', () async {
    final directory = await Directory.systemTemp.createTemp(
      'sonus_revision_restart_',
    );

    final databasePath = path.join(directory.path, 'sonus_test.db');

    AppDatabase? first;
    AppDatabase? second;

    try {
      first = AppDatabase(
        databaseFactory: databaseFactoryFfi,
        databasePath: databasePath,
      );

      final firstDb = await first.database;

      final firstRepository = SqliteCloudRevisionBaselineRepository(
        dao: CloudRevisionBaselineDao(firstDb),
      );

      await firstRepository.saveObservedRevision(
        userId: 'account-1',
        entityType: CloudDataEntity.artist,
        entityId: 'artist-1',
        serverRevision: 12,
      );

      await first.close();
      first = null;

      second = AppDatabase(
        databaseFactory: databaseFactoryFfi,
        databasePath: databasePath,
      );

      final secondDb = await second.database;

      final secondRepository = SqliteCloudRevisionBaselineRepository(
        dao: CloudRevisionBaselineDao(secondDb),
      );

      expect(
        await secondRepository.getRevision(
          userId: 'account-1',
          entityType: CloudDataEntity.artist,
          entityId: 'artist-1',
        ),
        12,
      );

      expect(
        await secondRepository.getRevision(
          userId: 'account-2',
          entityType: CloudDataEntity.artist,
          entityId: 'artist-1',
        ),
        isNull,
      );

      expect(
        (await secondDb.rawQuery('PRAGMA user_version')).single['user_version'],
        AppDatabase.databaseVersion,
      );
    } finally {
      await first?.close();
      await second?.close();

      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    }
  });
}
