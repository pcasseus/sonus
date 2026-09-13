import 'package:flutter/widgets.dart';

import 'app/sonus_app.dart';
import 'features/account/application/config/account_bootstrapper.dart';
import 'features/account/application/config/account_environment_config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final config = AccountEnvironmentConfig.fromEnvironment();

  final accountBootstrap = await AccountBootstrapper.initialize(config);

  runApp(SonusApp(accountRepository: accountBootstrap.repository));
}
