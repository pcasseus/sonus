import 'package:flutter/widgets.dart';

import 'app/sonus_app.dart';
import 'features/account/application/config/account_bootstrapper.dart';
import 'features/account/application/config/account_environment_config.dart';
import 'features/player/application/services/media_session/media_session_bootstrap.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final config = AccountEnvironmentConfig.fromEnvironment();

  final accountBootstrap = await AccountBootstrapper.initialize(config);

  // Once per process: the media session outlives app reloads.
  final mediaSession = await MediaSessionBootstrap.start();

  runApp(
    SonusApp(
      accountRepository: accountBootstrap.repository,
      mediaSession: mediaSession,
    ),
  );
}
