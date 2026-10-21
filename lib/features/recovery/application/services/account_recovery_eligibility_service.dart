import '../../../account/application/repositories/local_account_binding_repository.dart';
import '../models/account_recovery_eligibility.dart';

class AccountRecoveryEligibilityService {
  const AccountRecoveryEligibilityService({
    required LocalAccountBindingRepository bindingRepository,
  }) : this._(bindingRepository);

  const AccountRecoveryEligibilityService._(this._bindingRepository);

  final LocalAccountBindingRepository _bindingRepository;

  Future<AccountRecoveryEligibility> assess({
    required String? authenticatedUserId,
  }) async {
    final userId = authenticatedUserId?.trim();

    if (userId == null || userId.isEmpty) {
      return const AccountRecoveryEligibility(
        status: AccountRecoveryEligibilityStatus.authenticationRequired,
        requiresLocalBinding: false,
      );
    }

    final binding = await _bindingRepository.getBinding();

    if (binding != null && binding.userId != userId) {
      return const AccountRecoveryEligibility(
        status: AccountRecoveryEligibilityStatus.accountBindingConflict,
        requiresLocalBinding: false,
      );
    }

    return AccountRecoveryEligibility(
      status: AccountRecoveryEligibilityStatus.eligible,
      requiresLocalBinding: binding == null,
    );
  }
}
