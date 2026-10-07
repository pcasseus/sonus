import 'package:flutter_test/flutter_test.dart';

import 'package:sonus_next/features/library/domain/metadata/metadata_field_state.dart';
import 'package:sonus_next/features/library/domain/services/metadata_authority_policy.dart';

void main() {
  MetadataFieldState state(MetadataAuthority authority) {
    return MetadataFieldState(
      entityType: MetadataEntityType.song,
      entityId: 'song_1',
      fieldName: 'title',
      authority: authority,
      source: MetadataProvenanceSource.legacy,
      updatedAt: DateTime.utc(2026, 10, 7, 12),
    );
  }

  group('MetadataAuthorityPolicy', () {
    test('accepts metadata when no previous field state exists', () {
      expect(
        MetadataAuthorityPolicy.evaluate(
          existing: null,
          incomingAuthority: MetadataAuthority.inferred,
        ),
        MetadataReplacementDecision.accept,
      );
    });

    test('accepts equal authority', () {
      for (final authority in MetadataAuthority.values) {
        expect(
          MetadataAuthorityPolicy.evaluate(
            existing: state(authority),
            incomingAuthority: authority,
          ),
          MetadataReplacementDecision.accept,
          reason: 'Expected equal $authority authority to replace itself.',
        );
      }
    });

    test('accepts every stronger authority', () {
      final authorities = MetadataAuthority.values;

      for (
        var existingIndex = 0;
        existingIndex < authorities.length;
        existingIndex++
      ) {
        for (
          var incomingIndex = existingIndex + 1;
          incomingIndex < authorities.length;
          incomingIndex++
        ) {
          final existingAuthority = authorities[existingIndex];
          final incomingAuthority = authorities[incomingIndex];

          expect(
            MetadataAuthorityPolicy.evaluate(
              existing: state(existingAuthority),
              incomingAuthority: incomingAuthority,
            ),
            MetadataReplacementDecision.accept,
            reason: '$incomingAuthority should replace $existingAuthority.',
          );
        }
      }
    });

    test('rejects every weaker authority', () {
      final authorities = MetadataAuthority.values;

      for (
        var existingIndex = 1;
        existingIndex < authorities.length;
        existingIndex++
      ) {
        for (
          var incomingIndex = 0;
          incomingIndex < existingIndex;
          incomingIndex++
        ) {
          final existingAuthority = authorities[existingIndex];
          final incomingAuthority = authorities[incomingIndex];

          expect(
            MetadataAuthorityPolicy.evaluate(
              existing: state(existingAuthority),
              incomingAuthority: incomingAuthority,
            ),
            MetadataReplacementDecision.rejectLowerAuthority,
            reason: '$incomingAuthority must not replace $existingAuthority.',
          );
        }
      }
    });

    test('manual metadata cannot be replaced automatically', () {
      final existing = state(MetadataAuthority.manual);

      for (final incomingAuthority in const [
        MetadataAuthority.inferred,
        MetadataAuthority.imported,
        MetadataAuthority.external,
        MetadataAuthority.confirmed,
      ]) {
        expect(
          MetadataAuthorityPolicy.canReplace(
            existing: existing,
            incomingAuthority: incomingAuthority,
          ),
          isFalse,
        );
      }
    });

    test('confirmed review can replace external metadata', () {
      expect(
        MetadataAuthorityPolicy.canReplace(
          existing: state(MetadataAuthority.external),
          incomingAuthority: MetadataAuthority.confirmed,
        ),
        isTrue,
      );
    });

    test('external metadata can replace imported metadata', () {
      expect(
        MetadataAuthorityPolicy.canReplace(
          existing: state(MetadataAuthority.imported),
          incomingAuthority: MetadataAuthority.external,
        ),
        isTrue,
      );
    });

    group('automatic replacement', () {
      test('empty field accepts external metadata without prior state', () {
        expect(
          MetadataAuthorityPolicy.evaluateAutomaticReplacement(
            existingValuePresent: false,
            existing: null,
            incomingAuthority: MetadataAuthority.external,
          ),
          MetadataReplacementDecision.accept,
        );

        expect(
          MetadataAuthorityPolicy.canAutomaticallyReplace(
            existingValuePresent: false,
            existing: null,
            incomingAuthority: MetadataAuthority.external,
          ),
          isTrue,
        );
      });

      test('legacy existing value without field state requires review', () {
        expect(
          MetadataAuthorityPolicy.evaluateAutomaticReplacement(
            existingValuePresent: true,
            existing: null,
            incomingAuthority: MetadataAuthority.external,
          ),
          MetadataReplacementDecision.requireReviewUnknownAuthority,
        );

        expect(
          MetadataAuthorityPolicy.canAutomaticallyReplace(
            existingValuePresent: true,
            existing: null,
            incomingAuthority: MetadataAuthority.external,
          ),
          isFalse,
        );
      });

      test('known imported value accepts stronger external metadata', () {
        expect(
          MetadataAuthorityPolicy.evaluateAutomaticReplacement(
            existingValuePresent: true,
            existing: state(MetadataAuthority.imported),
            incomingAuthority: MetadataAuthority.external,
          ),
          MetadataReplacementDecision.accept,
        );
      });

      test('known manual value rejects external metadata', () {
        expect(
          MetadataAuthorityPolicy.evaluateAutomaticReplacement(
            existingValuePresent: true,
            existing: state(MetadataAuthority.manual),
            incomingAuthority: MetadataAuthority.external,
          ),
          MetadataReplacementDecision.rejectLowerAuthority,
        );
      });

      test('known confirmed value rejects external metadata', () {
        expect(
          MetadataAuthorityPolicy.evaluateAutomaticReplacement(
            existingValuePresent: true,
            existing: state(MetadataAuthority.confirmed),
            incomingAuthority: MetadataAuthority.external,
          ),
          MetadataReplacementDecision.rejectLowerAuthority,
        );
      });

      test('known inferred value accepts external metadata', () {
        expect(
          MetadataAuthorityPolicy.evaluateAutomaticReplacement(
            existingValuePresent: true,
            existing: state(MetadataAuthority.inferred),
            incomingAuthority: MetadataAuthority.external,
          ),
          MetadataReplacementDecision.accept,
        );
      });
    });
    test('embedded import cannot replace confirmed review', () {
      expect(
        MetadataAuthorityPolicy.canReplace(
          existing: state(MetadataAuthority.confirmed),
          incomingAuthority: MetadataAuthority.imported,
        ),
        isFalse,
      );
    });
  });
}
