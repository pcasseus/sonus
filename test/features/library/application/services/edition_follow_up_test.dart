import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/library/application/services/edition_follow_up.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';

EditionListing listing(
  String id,
  List<String> songs, {
  AlbumEditionType type = AlbumEditionType.standard,
  int createdDay = 1,
}) => EditionListing(
  editionId: id,
  title: id,
  type: type,
  createdAt: DateTime.utc(2026, 10, createdDay),
  songIds: songs.toSet(),
);

void main() {
  group('after adding songs in Album Studio', () {
    test('Deluxe built on Standard is offered the new song', () {
      final followUps = EditionFollowUps.afterAdding(
        source: listing('standard', ['a', 'b']),
        others: [
          listing('deluxe', ['a', 'b', 'x'], type: AlbumEditionType.deluxe),
        ],
        added: ['new'],
      );

      expect(followUps.single.targetEditionId, 'deluxe');
      expect(followUps.single.songIds, ['new']);
    });

    test('an edition missing Standard songs was curated: not offered', () {
      final followUps = EditionFollowUps.afterAdding(
        source: listing('standard', ['a', 'b']),
        others: [
          listing('deluxe', ['a'], type: AlbumEditionType.deluxe),
        ],
        added: ['new'],
      );

      expect(followUps, isEmpty);
    });

    test('songs already on Deluxe are not offered again', () {
      final followUps = EditionFollowUps.afterAdding(
        source: listing('standard', ['a']),
        others: [
          listing('deluxe', ['a', 'b'], type: AlbumEditionType.deluxe),
        ],
        added: ['b', 'c', 'c'],
      );

      expect(followUps.single.songIds, ['c']);
    });

    test('nothing is offered for an empty source or no additions', () {
      final deluxe = listing('deluxe', ['a'], type: AlbumEditionType.deluxe);

      expect(
        EditionFollowUps.afterAdding(
          source: listing('standard', []),
          others: [deluxe],
          added: ['x'],
        ),
        isEmpty,
      );
      expect(
        EditionFollowUps.afterAdding(
          source: listing('standard', ['a']),
          others: [deluxe],
          added: [],
        ),
        isEmpty,
      );
    });
  });

  group('songs imported to Standard after Deluxe existed', () {
    final added = <String, DateTime>{
      'a': DateTime.utc(2026, 10, 1),
      'b': DateTime.utc(2026, 10, 1),
      'bonus': DateTime.utc(2026, 10, 2),
      'new': DateTime.utc(2026, 10, 9),
    };
    final orders = {
      'standard': ['a', 'b', 'new'],
      'deluxe': ['a', 'b', 'bonus'],
    };

    List<EditionFollowUp> run(
      List<EditionListing> editions, {
      Set<String> Function(String)? dismissed,
    }) => EditionFollowUps.laterAdditions(
      editions: editions,
      orderOf: (id) => orders[id] ?? const [],
      addedAt: (song) => added[song],
      dismissed: dismissed,
    );

    final standard = listing('standard', ['a', 'b', 'new']);
    final deluxe = listing(
      'deluxe',
      ['a', 'b', 'bonus'],
      type: AlbumEditionType.deluxe,
      createdDay: 2,
    );

    test('the newer Standard song is offered to Deluxe', () {
      final followUps = run([standard, deluxe]);

      expect(followUps.single.sourceEditionId, 'standard');
      expect(followUps.single.targetEditionId, 'deluxe');
      expect(followUps.single.songIds, ['new']);
    });

    test('Deluxe-only songs are never offered to Standard', () {
      final followUps = run([standard, deluxe]);

      expect(followUps.where((f) => f.targetEditionId == 'standard'), isEmpty);
    });

    test('a song left off when Deluxe was made is not offered', () {
      final curated = listing(
        'deluxe',
        ['a', 'bonus'],
        type: AlbumEditionType.deluxe,
        createdDay: 2,
      );

      expect(run([standard, curated]), isEmpty);
    });

    test('a dismissed song is not offered again', () {
      expect(run([standard, deluxe], dismissed: (target) => {'new'}), isEmpty);
    });

    test('an edition older than Standard is not treated as built on it', () {
      final older = listing(
        'deluxe',
        ['a', 'b'],
        type: AlbumEditionType.deluxe,
        createdDay: 1,
      );

      expect(
        run([
          listing('standard', ['a', 'b', 'new'], createdDay: 2),
          older,
        ]),
        isEmpty,
      );
    });
  });
}
