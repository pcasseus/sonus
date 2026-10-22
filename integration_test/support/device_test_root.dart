import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

/// A disposable folder inside the app's private storage, used only by
/// SN-42 integration tests. Never touches the app's real database
/// (`sonus_next.db`) or managed artwork.
Future<Directory> createDeviceTestRoot(String name) async {
  final support = await getApplicationSupportDirectory();
  final root = Directory(
    path.join(
      support.path,
      'sn42_integration',
      '${name}_${DateTime.now().microsecondsSinceEpoch}',
    ),
  );
  await root.create(recursive: true);
  return root;
}

Future<Directory> fixedDeviceTestRoot(String name) async {
  final support = await getApplicationSupportDirectory();
  return Directory(path.join(support.path, 'sn42_integration', name));
}

Future<void> deleteDeviceTestRoot(Directory root) async {
  // Only ever delete inside the dedicated integration folder.
  if (!root.path.contains('${Platform.pathSeparator}sn42_integration')) {
    throw StateError('Refusing to delete outside the integration folder.');
  }

  if (await root.exists()) {
    await root.delete(recursive: true);
  }
}
