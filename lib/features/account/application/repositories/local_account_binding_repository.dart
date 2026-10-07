import '../../domain/entities/local_account_binding.dart';

class LocalAccountBindingConflict implements Exception {
  const LocalAccountBindingConflict({
    required this.boundUserId,
    required this.requestedUserId,
  });

  final String boundUserId;
  final String requestedUserId;

  @override
  String toString() {
    return 'This local Sonus library is already bound to another account.';
  }
}

abstract interface class LocalAccountBindingRepository {
  Future<LocalAccountBinding?> getBinding();

  Future<void> bindToUser(String userId);

  Future<void> clearBinding();
}
