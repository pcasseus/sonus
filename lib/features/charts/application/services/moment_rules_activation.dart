// ignore_for_file: prefer_initializing_formals

import 'dart:developer' as developer;

import '../../domain/moments/chart_moment_rules.dart';

typedef MomentRulesActivationNow = DateTime Function();

/// Where the SN-50 Moments rules activation instant is kept.
abstract interface class MomentRulesActivationStore {
  /// Null until an approved build has recorded one.
  Future<String?> read();

  Future<void> write(String activatedAtUtc);
}

/// Decides which Moments rules this run uses (SN-50 R2).
///
/// Only a build compiled with
/// `--dart-define=SONUS_MOMENTS_REFINED_APPROVED=true` can activate the new
/// rules; installing or launching any other build never does. On its first
/// run an approved build records the activation instant once: later runs
/// read it back and never move it. The instant is durable before any rules
/// that depend on it are returned, so a run that ends before it is saved
/// publishes nothing under the new rules.
///
/// Storage that has lost the instant (reinstall, cleared or restored
/// preferences without it) gets a new one at that run's time: only later
/// Moments follow the new rules, never earlier ones. The instant is never
/// derived from listening or Moments data.
class MomentRulesActivation {
  MomentRulesActivation({
    required MomentRulesActivationStore store,
    bool approved = buildApproved,
    MomentRulesActivationNow? now,
  }) : _store = store,
       _approved = approved,
       _now = now ?? DateTime.now;

  static const bool buildApproved = bool.fromEnvironment(
    'SONUS_MOMENTS_REFINED_APPROVED',
  );

  final MomentRulesActivationStore _store;
  final bool _approved;
  final MomentRulesActivationNow _now;

  Future<ChartMomentRules>? _resolved;

  /// The rules for this run. Shared by every caller; retried after a
  /// storage failure, which falls back to the earlier rules meanwhile.
  Future<ChartMomentRules> rules() {
    if (!_approved) return Future.value(ChartMomentRules.legacy);

    return _resolved ??= _resolve().then((rules) {
      if (rules.activatedAtUtc == null) _resolved = null;
      return rules;
    });
  }

  Future<ChartMomentRules> _resolve() async {
    try {
      final stored = await _store.read();
      if (stored != null) return _rulesFrom(stored);

      await _store.write(_now().toUtc().toIso8601String());
      final saved = await _store.read();
      if (saved == null) {
        throw StateError('The activation instant was not saved.');
      }
      return _rulesFrom(saved);
    } catch (error, stackTrace) {
      developer.log(
        'The Moments rules activation could not be read or saved '
        '(${error.runtimeType}); Moments keep the earlier rules',
        name: 'sonus.charts',
        level: 900,
        error: error,
        stackTrace: stackTrace,
      );
      return ChartMomentRules.legacy;
    }
  }

  /// An unreadable instant is kept, never replaced: Moments keep the
  /// earlier rules until it is repaired.
  static ChartMomentRules _rulesFrom(String stored) {
    final activated = DateTime.tryParse(stored);
    if (activated == null || !activated.isUtc) {
      throw FormatException('Unreadable activation instant', stored);
    }
    return ChartMomentRules(activatedAtUtc: activated);
  }
}
