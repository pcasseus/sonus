import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/import/application/folders/device_music_folder_tree.dart';
import 'package:sonus_next/features/import/application/services/device_music_access.dart';

DeviceAudioFolder _folder(String path, int count) =>
    DeviceAudioFolder(path: path, audioCount: count);

void main() {
  test('builds the folders above every music folder, with counts', () {
    final volumes = DeviceMusicFolderTree.build([
      _folder('/storage/emulated/0/Download/Music/FLO/Access All Areas', 6),
      _folder('/storage/emulated/0/Download/Music/FLO/The Lead', 5),
      _folder('/storage/emulated/0/Download/Music/Victorious', 18),
      _folder('/storage/emulated/0/Ringtones', 3),
    ]);

    final phone = volumes.single;
    expect(phone.name, 'This phone');
    expect(phone.totalAudioCount, 32);
    expect([for (final c in phone.children) c.name], ['Download', 'Ringtones']);

    final music = phone.children.first.children.single;
    expect(music.path, '/storage/emulated/0/Download/Music');
    expect(music.totalAudioCount, 29);
    expect(music.directAudioCount, 0);
    expect([for (final c in music.children) c.name], ['FLO', 'Victorious']);

    final flo = music.children.first;
    expect(flo.totalAudioCount, 11);
    expect(
      [for (final c in flo.children) c.name],
      ['Access All Areas', 'The Lead'],
    );
    expect(music.children.last.directAudioCount, 18);
    expect(music.children.last.hasSubfolders, isFalse);
  });

  test('names are kept exactly, accents included, and sorted calmly', () {
    final volumes = DeviceMusicFolderTree.build([
      _folder('/storage/emulated/0/Download/Music/Reneé Rapp/Snow Angel', 2),
      _folder('/storage/emulated/0/Download/Music/ADÉLA/PRIMA', 2),
      _folder('/storage/emulated/0/Download/Music/beyoncé/Lemonade', 2),
    ]);

    final music = volumes.single.children.single.children.single;
    expect(
      [for (final c in music.children) c.name],
      ['ADÉLA', 'beyoncé', 'Reneé Rapp'],
    );
  });

  test('a memory card is its own volume, after the phone', () {
    final volumes = DeviceMusicFolderTree.build([
      _folder('/storage/1A2B-3C4D/Music/Artist/Album', 4),
      _folder('/storage/emulated/0/Music/Samsung', 1),
    ]);

    expect(
      [for (final v in volumes) v.name],
      ['This phone', 'Storage 1A2B-3C4D'],
    );
    expect(volumes.last.children.single.name, 'Music');
  });

  test('anything outside device storage, or with no audio, is left out', () {
    final volumes = DeviceMusicFolderTree.build([
      _folder('/data/user/0/other.app/files', 9),
      _folder('/storage/emulated/0/Empty', 0),
      _folder('/storage/emulated/0//Music/Samsung/', 1),
    ]);

    final phone = volumes.single;
    expect(phone.totalAudioCount, 1);
    expect(
      phone.children.single.children.single.path,
      '/storage/emulated/0/Music/Samsung',
    );
  });

  test('no music means no volumes', () {
    expect(DeviceMusicFolderTree.build(const []), isEmpty);
  });
}
