import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/import/application/metadata/track_title_version_interpreter.dart';
import 'package:sonus_next/features/library/domain/entities/song.dart';

void main() {
  const interpreter = TrackTitleVersionInterpreter();

  test('parses parenthesized live suffix', () {
    final result = interpreter.interpret('Song Title (Live)');

    expect(result.title, 'Song Title');
    expect(result.versionLabel, 'Live');
    expect(result.versionCharacteristics, const [
      SongVersionCharacteristic.live,
    ]);
  });

  test('parses bracketed remix suffix', () {
    final result = interpreter.interpret('Song Title [Remix]');

    expect(result.title, 'Song Title');
    expect(result.versionLabel, 'Remix');
    expect(result.versionCharacteristics, const [
      SongVersionCharacteristic.remix,
    ]);
  });

  test('parses hyphenated radio edit suffix', () {
    final result = interpreter.interpret('Song Title - Radio Edit');

    expect(result.title, 'Song Title');
    expect(result.versionLabel, 'Radio Edit');
    expect(result.versionCharacteristics, const [
      SongVersionCharacteristic.radioEdit,
    ]);
  });

  test('parses acoustic suffix', () {
    final result = interpreter.interpret('Song Title (Acoustic)');

    expect(result.title, 'Song Title');
    expect(result.versionLabel, 'Acoustic');
    expect(result.versionCharacteristics, const [
      SongVersionCharacteristic.acoustic,
    ]);
  });

  test('parses demo suffix', () {
    final result = interpreter.interpret('Song Title [Demo]');

    expect(result.title, 'Song Title');
    expect(result.versionLabel, 'Demo');
    expect(result.versionCharacteristics, const [
      SongVersionCharacteristic.demo,
    ]);
  });

  test('parses extended mix suffix', () {
    final result = interpreter.interpret('Song Title - Extended Mix');

    expect(result.title, 'Song Title');
    expect(result.versionLabel, 'Extended Mix');
    expect(result.versionCharacteristics, const [
      SongVersionCharacteristic.extended,
    ]);
  });

  test('parses instrumental suffix', () {
    final result = interpreter.interpret('Song Title (Instrumental)');

    expect(result.title, 'Song Title');
    expect(result.versionLabel, 'Instrumental');
    expect(result.versionCharacteristics, const [
      SongVersionCharacteristic.instrumental,
    ]);
  });

  test('parses remaster suffix with year', () {
    final result = interpreter.interpret('Song Title (2024 Remaster)');

    expect(result.title, 'Song Title');
    expect(result.versionLabel, '2024 Remaster');
    expect(result.versionCharacteristics, const [
      SongVersionCharacteristic.remaster,
    ]);
  });

  test('parses multiple recognized characteristics', () {
    final result = interpreter.interpret('Song Title (Live Remix)');

    expect(result.title, 'Song Title');
    expect(result.versionLabel, 'Live Remix');
    expect(result.versionCharacteristics, const [
      SongVersionCharacteristic.live,
      SongVersionCharacteristic.remix,
    ]);
  });

  test('does not reinterpret live phrase as live version', () {
    final result = interpreter.interpret('Song Title (Live Forever)');

    expect(result.title, 'Song Title (Live Forever)');
    expect(result.versionLabel, isNull);
    expect(result.versionCharacteristics, isEmpty);
  });

  test('does not reinterpret remix phrase as remix version', () {
    final result = interpreter.interpret('Song Title (Remix Contest Winner)');

    expect(result.title, 'Song Title (Remix Contest Winner)');
    expect(result.versionLabel, isNull);
    expect(result.versionCharacteristics, isEmpty);
  });

  test('does not reinterpret descriptive demo phrase as demo version', () {
    final result = interpreter.interpret('Song Title (Demo Version by X)');

    expect(result.title, 'Song Title (Demo Version by X)');
    expect(result.versionLabel, isNull);
    expect(result.versionCharacteristics, isEmpty);
  });

  test('accepts controlled version qualifier vocabulary', () {
    final acoustic = interpreter.interpret('Song Title (Acoustic Version)');
    final demo = interpreter.interpret('Song Title (Demo Version)');
    final remastered = interpreter.interpret('Song Title (2024 Remastered)');

    expect(acoustic.title, 'Song Title');
    expect(acoustic.versionLabel, 'Acoustic Version');
    expect(acoustic.versionCharacteristics, const [
      SongVersionCharacteristic.acoustic,
    ]);

    expect(demo.title, 'Song Title');
    expect(demo.versionLabel, 'Demo Version');
    expect(demo.versionCharacteristics, const [SongVersionCharacteristic.demo]);

    expect(remastered.title, 'Song Title');
    expect(remastered.versionLabel, '2024 Remastered');
    expect(remastered.versionCharacteristics, const [
      SongVersionCharacteristic.remaster,
    ]);
  });
  test('preserves unrecognized terminal qualifier', () {
    final result = interpreter.interpret(
      'Song Title (From The Motion Picture)',
    );

    expect(result.title, 'Song Title (From The Motion Picture)');
    expect(result.versionLabel, isNull);
    expect(result.versionCharacteristics, isEmpty);
  });

  test('does not reinterpret legitimate title containing live', () {
    final result = interpreter.interpret('Live and Let Die');

    expect(result.title, 'Live and Let Die');
    expect(result.versionLabel, isNull);
    expect(result.versionCharacteristics, isEmpty);
  });

  test('does not reinterpret title that itself is remix', () {
    final result = interpreter.interpret('The Remix');

    expect(result.title, 'The Remix');
    expect(result.versionLabel, isNull);
    expect(result.versionCharacteristics, isEmpty);
  });

  test('trims surrounding title whitespace', () {
    final result = interpreter.interpret('  Song Title (Live)  ');

    expect(result.title, 'Song Title');
    expect(result.versionLabel, 'Live');
  });

  test('blank title stays blank safely', () {
    final result = interpreter.interpret('   ');

    expect(result.title, '');
    expect(result.versionLabel, isNull);
    expect(result.versionCharacteristics, isEmpty);
  });

  test('interpretation is idempotent after version suffix is removed', () {
    final first = interpreter.interpret('Song Title (Live)');
    final second = interpreter.interpret(first.title);

    expect(first.title, 'Song Title');
    expect(first.versionLabel, 'Live');
    expect(second.title, 'Song Title');
    expect(second.versionLabel, isNull);
    expect(second.versionCharacteristics, isEmpty);
  });
}
