import 'package:flutter_test/flutter_test.dart';

import 'package:sonus_next/features/library/domain/metadata/metadata_field_state.dart';
import 'package:sonus_next/features/library/domain/repositories/metadata_field_state_repository.dart';
import 'package:sonus_next/features/library/domain/services/metadata_field_state_service.dart';

void main() {
  late _MemoryMetadataFieldStateRepository repository;
  late MetadataFieldStateService service;

  setUp(() {
    repository = _MemoryMetadataFieldStateRepository();
    service = MetadataFieldStateService(repository: repository);
  });

  test('records provenance when field has no existing state', () async {
    final now = DateTime.utc(2026, 10, 7, 12);

    final accepted = await service.record(
      entityType: MetadataEntityType.song,
      entityId: 'song_1',
      fieldName: 'title',
      authority: MetadataAuthority.imported,
      source: MetadataProvenanceSource.embeddedTag,
      updatedAt: now,
    );

    expect(accepted, isTrue);

    final state = await repository.get(
      entityType: MetadataEntityType.song,
      entityId: 'song_1',
      fieldName: 'title',
    );

    expect(state?.authority, MetadataAuthority.imported);
    expect(state?.source, MetadataProvenanceSource.embeddedTag);
    expect(state?.updatedAt, now);
  });

  test('stronger authority replaces weaker authority', () async {
    final first = DateTime.utc(2026, 10, 7, 12);
    final second = DateTime.utc(2026, 10, 7, 13);

    await service.record(
      entityType: MetadataEntityType.song,
      entityId: 'song_1',
      fieldName: 'title',
      authority: MetadataAuthority.imported,
      source: MetadataProvenanceSource.embeddedTag,
      updatedAt: first,
    );

    final accepted = await service.record(
      entityType: MetadataEntityType.song,
      entityId: 'song_1',
      fieldName: 'title',
      authority: MetadataAuthority.manual,
      source: MetadataProvenanceSource.user,
      updatedAt: second,
    );

    expect(accepted, isTrue);

    final state = await repository.get(
      entityType: MetadataEntityType.song,
      entityId: 'song_1',
      fieldName: 'title',
    );

    expect(state?.authority, MetadataAuthority.manual);
    expect(state?.source, MetadataProvenanceSource.user);
    expect(state?.updatedAt, second);
  });

  test('weaker authority cannot replace stronger authority', () async {
    final manualTime = DateTime.utc(2026, 10, 7, 12);
    final externalTime = DateTime.utc(2026, 10, 7, 13);

    await service.record(
      entityType: MetadataEntityType.song,
      entityId: 'song_1',
      fieldName: 'title',
      authority: MetadataAuthority.manual,
      source: MetadataProvenanceSource.user,
      updatedAt: manualTime,
    );

    final accepted = await service.record(
      entityType: MetadataEntityType.song,
      entityId: 'song_1',
      fieldName: 'title',
      authority: MetadataAuthority.external,
      source: MetadataProvenanceSource.musicBrainz,
      updatedAt: externalTime,
    );

    expect(accepted, isFalse);

    final state = await repository.get(
      entityType: MetadataEntityType.song,
      entityId: 'song_1',
      fieldName: 'title',
    );

    expect(state?.authority, MetadataAuthority.manual);
    expect(state?.source, MetadataProvenanceSource.user);
    expect(state?.updatedAt, manualTime);
  });

  test('recordAll records each distinct field once', () async {
    final now = DateTime.utc(2026, 10, 7, 12);

    await service.recordAll(
      entityType: MetadataEntityType.song,
      entityId: 'song_1',
      fieldNames: const ['title', 'artistCredits', 'title'],
      authority: MetadataAuthority.manual,
      source: MetadataProvenanceSource.user,
      updatedAt: now,
    );

    final states = await repository.getByEntity(
      entityType: MetadataEntityType.song,
      entityId: 'song_1',
    );

    expect(states, hasLength(2));
    expect(states.map((state) => state.fieldName).toSet(), {
      'title',
      'artistCredits',
    });
  });
}

class _MemoryMetadataFieldStateRepository
    implements MetadataFieldStateRepository {
  final Map<String, MetadataFieldState> _states = {};

  String _key(
    MetadataEntityType entityType,
    String entityId,
    String fieldName,
  ) {
    return '${entityType.name}|$entityId|$fieldName';
  }

  @override
  Future<MetadataFieldState?> get({
    required MetadataEntityType entityType,
    required String entityId,
    required String fieldName,
  }) async {
    return _states[_key(entityType, entityId, fieldName)];
  }

  @override
  Future<List<MetadataFieldState>> getByEntity({
    required MetadataEntityType entityType,
    required String entityId,
  }) async {
    return _states.values
        .where(
          (state) =>
              state.entityType == entityType && state.entityId == entityId,
        )
        .toList(growable: false);
  }

  @override
  Future<void> save(MetadataFieldState state) async {
    _states[_key(state.entityType, state.entityId, state.fieldName)] = state;
  }

  @override
  Future<void> delete({
    required MetadataEntityType entityType,
    required String entityId,
    required String fieldName,
  }) async {
    _states.remove(_key(entityType, entityId, fieldName));
  }

  @override
  Future<void> deleteByEntity({
    required MetadataEntityType entityType,
    required String entityId,
  }) async {
    _states.removeWhere(
      (_, state) =>
          state.entityType == entityType && state.entityId == entityId,
    );
  }
}
