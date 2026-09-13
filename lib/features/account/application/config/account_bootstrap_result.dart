import '../../domain/repositories/account_repository.dart';

class AccountBootstrapResult {
  const AccountBootstrapResult({required this.repository});

  final AccountRepository? repository;

  bool get isAvailable => repository != null;
}
