import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/account/application/repositories/local_account_binding_repository.dart';
import 'package:sonus_next/features/account/domain/entities/local_account_binding.dart';
import 'package:sonus_next/features/recovery/application/models/account_recovery_eligibility.dart';
import 'package:sonus_next/features/recovery/application/services/account_recovery_eligibility_service.dart';

class FakeBindingRepository implements LocalAccountBindingRepository {
  FakeBindingRepository(this.binding);

  LocalAccountBinding? binding;
  int readCount = 0;
  int writeCount = 0;

  @override
  Future<LocalAccountBinding?> getBinding() async {
    readCount++;
    return binding;
  }

  @override
  Future<void> bindToUser(String userId) async {
    writeCount++;
    throw StateError('Recovery assessment must not bind an account.');
  }

  @override
  Future<void> clearBinding() async {
    writeCount++;
    throw StateError('Recovery assessment must not clear an account binding.');
  }
}

LocalAccountBinding bindingFor(String userId) {
  final timestamp = DateTime.utc(2026, 10, 21);

  return LocalAccountBinding(
    userId: userId,
    boundAt: timestamp,
    updatedAt: timestamp,
  );
}

void main() {
  test('requires authentication without accessing the local binding', () async {
    final repository = FakeBindingRepository(null);
    final service = AccountRecoveryEligibilityService(
      bindingRepository: repository,
    );

    final result = await service.assess(authenticatedUserId: null);

    expect(
      result.status,
      AccountRecoveryEligibilityStatus.authenticationRequired,
    );
    expect(result.canAssess, isFalse);
    expect(repository.readCount, 0);
    expect(repository.writeCount, 0);
  });

  test('rejects whitespace-only authentication identifiers', () async {
    final repository = FakeBindingRepository(null);
    final service = AccountRecoveryEligibilityService(
      bindingRepository: repository,
    );

    final result = await service.assess(authenticatedUserId: '   ');

    expect(
      result.status,
      AccountRecoveryEligibilityStatus.authenticationRequired,
    );
    expect(repository.readCount, 0);
  });

  test('allows assessment for a matching account binding', () async {
    final repository = FakeBindingRepository(bindingFor('user-a'));
    final service = AccountRecoveryEligibilityService(
      bindingRepository: repository,
    );

    final result = await service.assess(authenticatedUserId: 'user-a');

    expect(result.status, AccountRecoveryEligibilityStatus.eligible);
    expect(result.canAssess, isTrue);
    expect(result.canRestore, isTrue);
    expect(result.requiresLocalBinding, isFalse);
    expect(repository.writeCount, 0);
  });

  test('rejects recovery for a different bound account', () async {
    final repository = FakeBindingRepository(bindingFor('user-a'));
    final service = AccountRecoveryEligibilityService(
      bindingRepository: repository,
    );

    final result = await service.assess(authenticatedUserId: 'user-b');

    expect(
      result.status,
      AccountRecoveryEligibilityStatus.accountBindingConflict,
    );
    expect(result.canAssess, isFalse);
    expect(result.canRestore, isFalse);
    expect(repository.writeCount, 0);
  });

  test(
    'allows assessment without silently binding an unowned library',
    () async {
      final repository = FakeBindingRepository(null);
      final service = AccountRecoveryEligibilityService(
        bindingRepository: repository,
      );

      final result = await service.assess(authenticatedUserId: 'user-a');

      expect(result.status, AccountRecoveryEligibilityStatus.eligible);
      expect(result.canAssess, isTrue);
      expect(result.canRestore, isFalse);
      expect(result.requiresLocalBinding, isTrue);
      expect(repository.writeCount, 0);
      expect(repository.binding, isNull);
    },
  );

  test('normalizes surrounding whitespace in authenticated user ID', () async {
    final repository = FakeBindingRepository(bindingFor('user-a'));
    final service = AccountRecoveryEligibilityService(
      bindingRepository: repository,
    );

    final result = await service.assess(authenticatedUserId: ' user-a ');

    expect(result.canAssess, isTrue);
    expect(result.requiresLocalBinding, isFalse);
    expect(repository.writeCount, 0);
  });
}
