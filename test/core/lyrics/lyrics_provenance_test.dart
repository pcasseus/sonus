// App Update 1.3 (database version 48): the one precedence rule every
// lyrics writer uses, text by text.
import 'package:flutter_test/flutter_test.dart';

import 'package:sonus_next/core/lyrics/lyrics_provenance.dart';

const _t1 = '2026-11-01T00:00:00.000Z';
const _t2 = '2026-11-02T00:00:00.000Z';

LyricsText _text(String? text, LyricsSource? source, {String? editedAt}) =>
    LyricsText(
      text: text,
      source: source,
      userEditedAt: editedAt == null ? null : DateTime.parse(editedAt),
    );

Map<String, Object?> _row({
  String? plain,
  String? plainSource,
  String? plainEdited,
  String? synced,
  String? syncedSource,
  String? syncedEdited,
  String? licence,
}) => {
  'song_id': 'song-1',
  'plain_text': plain,
  'plain_source': plainSource,
  'plain_user_edited_at': plainEdited,
  'synced_text': synced,
  'synced_source': syncedSource,
  'synced_user_edited_at': syncedEdited,
  'provider_licence': licence,
  'created_at': _t1,
  'updated_at': _t1,
};

void main() {
  group('precedence', () {
    test('ranks user > provider > embedded > .lrc > other sidecar > legacy '
        '> generated', () {
      final order = [
        LyricsSource.user,
        LyricsSource.provider,
        LyricsSource.embedded,
        LyricsSource.sidecarLrc,
        LyricsSource.sidecarTxt,
        null,
        LyricsSource.generated,
      ];
      for (var i = 0; i + 1 < order.length; i++) {
        expect(
          LyricsPrecedence.rank(order[i]),
          greaterThan(LyricsPrecedence.rank(order[i + 1])),
        );
      }
    });

    test('no automatic source replaces a listener edit', () {
      final edit = _text('Mine', LyricsSource.user, editedAt: _t1);
      for (final source in [...LyricsSource.values, null]) {
        if (source == LyricsSource.user) continue;
        for (final mode in LyricsMergeMode.values) {
          expect(
            LyricsPrecedence.replaces(_text('Auto', source), edit, mode: mode),
            isFalse,
            reason: '$source ($mode)',
          );
        }
      }
    });

    test('an edit is replaced only by an edit at least as recent', () {
      final edit = _text('Mine', LyricsSource.user, editedAt: _t2);
      expect(
        LyricsPrecedence.replaces(
          _text('Older', LyricsSource.user, editedAt: _t1),
          edit,
        ),
        isFalse,
      );
      expect(
        LyricsPrecedence.replaces(
          _text('Same time', LyricsSource.user, editedAt: _t2),
          edit,
        ),
        isTrue,
      );
    });

    test(
      'a listener edit replaces any automatic text, even by clearing it',
      () {
        expect(
          LyricsPrecedence.replaces(
            _text(null, LyricsSource.user, editedAt: _t1),
            _text('Embedded', LyricsSource.embedded),
          ),
          isTrue,
        );
      },
    );

    test('a worse source never replaces a better one; equal or better '
        'does', () {
      bool replaces(LyricsSource? incoming, LyricsSource? existing) =>
          LyricsPrecedence.replaces(
            _text('New', incoming),
            _text('Old', existing),
          );
      expect(replaces(LyricsSource.sidecarTxt, LyricsSource.embedded), isFalse);
      expect(replaces(LyricsSource.generated, null), isFalse);
      expect(
        replaces(LyricsSource.sidecarLrc, LyricsSource.sidecarLrc),
        isTrue,
      );
      expect(replaces(LyricsSource.embedded, LyricsSource.sidecarLrc), isTrue);
      expect(replaces(LyricsSource.sidecarTxt, null), isTrue);
      expect(replaces(LyricsSource.provider, LyricsSource.embedded), isTrue);
    });

    test('missing text never erases text', () {
      expect(
        LyricsPrecedence.replaces(
          _text(null, LyricsSource.provider),
          _text('Kept', LyricsSource.generated),
        ),
        isFalse,
      );
      expect(
        LyricsPrecedence.replaces(
          _text('  ', LyricsSource.provider),
          _text('Kept', null),
        ),
        isFalse,
      );
    });

    test('duplicate merge keeps the kept text unless it is empty', () {
      expect(
        LyricsPrecedence.replaces(
          _text('Dup', LyricsSource.embedded),
          _text('Kept', null),
          mode: LyricsMergeMode.keepExisting,
        ),
        isFalse,
      );
      expect(
        LyricsPrecedence.replaces(
          _text('Dup', LyricsSource.embedded),
          _text(null, null),
          mode: LyricsMergeMode.keepExisting,
        ),
        isTrue,
      );
    });
  });

  group('reading', () {
    test('unknown or inconsistent provenance reads as legacy', () {
      final unknown = LyricsText.fromRow({
        'plain_text': 'x',
        'plain_source': 'scraped',
      }, LyricsTextKind.plain);
      expect(unknown.source, isNull);
      final unstamped = LyricsText.fromRow({
        'plain_text': 'x',
        'plain_source': 'user',
      }, LyricsTextKind.plain);
      expect(unstamped.source, isNull);
      expect(unstamped.isUserEdit, isFalse);
      final stampOnly = LyricsText.fromRow({
        'synced_text': 'x',
        'synced_source': 'embedded',
        'synced_user_edited_at': _t1,
      }, LyricsTextKind.synced);
      expect(stampOnly.isUserEdit, isFalse);
      final confidence = LyricsText.fromRow({
        'plain_text': 'x',
        'plain_source': 'embedded',
        'plain_confidence': 1,
      }, LyricsTextKind.plain);
      expect(confidence.confidence, isNull);
    });
  });

  group('merge', () {
    test('plain and synchronised are decided independently', () {
      final merged = LyricsRows.merge(
        songId: 'song-1',
        existing: _row(
          plain: 'My words',
          plainSource: 'user',
          plainEdited: _t1,
          synced: '[00:01.00]Old',
          syncedSource: 'sidecarLrc',
        ),
        incoming: _row(
          plain: 'Tag words',
          plainSource: 'embedded',
          synced: '[00:01.00]Tag',
          syncedSource: 'embedded',
        ),
        stamp: _t2,
      )!;
      expect(merged['plain_text'], 'My words');
      expect(merged['plain_source'], 'user');
      expect(merged['plain_user_edited_at'], _t1);
      expect(merged['synced_text'], '[00:01.00]Tag');
      expect(merged['synced_source'], 'embedded');
      expect(merged['updated_at'], _t2);
    });

    test('nothing changes: null', () {
      final row = _row(plain: 'Same', plainSource: 'embedded');
      expect(
        LyricsRows.merge(
          songId: 'song-1',
          existing: row,
          incoming: _row(plain: 'Worse', plainSource: 'sidecarTxt'),
          stamp: _t2,
        ),
        isNull,
      );
    });

    test('an offset follows only a listener correction at least as recent', () {
      final existing = {
        ..._row(plain: 'x'),
        'offset_ms': 250,
        'offset_user_edited_at': _t2,
      };
      expect(
        LyricsRows.merge(
          songId: 'song-1',
          existing: existing,
          incoming: {'offset_ms': -100, 'offset_user_edited_at': _t1},
          stamp: _t2,
        ),
        isNull,
      );
      final newer = LyricsRows.merge(
        songId: 'song-1',
        existing: existing,
        incoming: {
          'offset_ms': -100,
          'offset_user_edited_at': '2026-11-03T00:00:00.000Z',
        },
        stamp: _t2,
      )!;
      expect(newer['offset_ms'], -100);
    });
  });

  group('portable form', () {
    test('display-only provider text is blanked; other text stays', () {
      final row = {
        ..._row(
          plain: 'Licensed',
          plainSource: 'provider',
          synced: '[00:01.00]Mine',
          syncedSource: 'sidecarLrc',
          licence: 'displayOnly',
        ),
        'provider': 'p',
        'provider_ref': 'ref',
      };
      final portable = LyricsRows.portable(row)!;
      expect(portable['plain_text'], isNull);
      expect(portable['plain_source'], isNull);
      expect(portable['synced_text'], '[00:01.00]Mine');
      expect(portable['provider'], isNull);
      expect(portable['provider_licence'], isNull);
    });

    test('a row with only display-only text has no portable form', () {
      expect(
        LyricsRows.portable(
          _row(
            plain: 'Licensed',
            plainSource: 'provider',
            licence: 'displayOnly',
          ),
        ),
        isNull,
      );
    });

    test('cacheable provider text stays', () {
      final row = _row(
        plain: 'Licensed',
        plainSource: 'provider',
        licence: 'cacheable',
      );
      expect(LyricsRows.hasDisplayOnly(row), isFalse);
      expect(LyricsRows.portable(row), row);
    });
  });
}
