// ignore_for_file: prefer_initializing_formals

import 'dart:developer' as developer;

import '../../domain/moments/chart_moment_rules.dart';

typedef MomentRulesActivationNow = DateTime Function();

/// Where the SN-50 Moments rules activation instant is kept.
abstract interface class MomentRulesActivationStore {
  /// Null until an approved build has recorded one.
  Future<String?> read();

  Future<void> write(String activatedAtUtc);

  /// Where refined catalog [version] (2 or later) started on this install;
  /// null until a build carrying it has recorded one (SN-50 R-V).
  Future<String?> readCatalogStart(int version);

  Future<void> writeCatalogStart(int version, String fromUtc);
}

/// Where the climb wording revision's start is kept (SN-50 device polish).
abstract interface class MomentDevicePolishStore {
  /// Null until a build carrying the wording has recorded one.
  Future<String?> readDevicePolishStart();

  Future<void> writeDevicePolishStart(String fromUtc);
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
    int catalogVersion = ChartMomentRules.currentCatalogVersion,
    MomentDevicePolishStore? devicePolish,
    MomentRulesActivationNow? now,
  }) : _store = store,
       _approved = approved,
       _catalogVersion = catalogVersion,
       _devicePolish = devicePolish,
       _now = now ?? DateTime.now;

  static const bool buildApproved = bool.fromEnvironment(
    'SONUS_MOMENTS_REFINED_APPROVED',
  );

  final MomentRulesActivationStore _store;
  final bool _approved;

  /// The newest refined catalog version this build carries.
  final int _catalogVersion;

  /// Where the climb wording starts; without it, no story changes words.
  final MomentDevicePolishStore? _devicePolish;
  final MomentRulesActivationNow _now;

  Future<ChartMomentRules>? _resolved;

  /// The start once read; only a resolved instant is kept, so a read that
  /// never finishes cannot hold up later loads.
  DateTime? _devicePolishStart;

  /// The rules for this run. Shared by every caller; retried after a
  /// storage failure, which falls back to the earlier rules meanwhile.
  Future<ChartMomentRules> rules() async {
    final climbFrom = await _devicePolishFrom();
    if (!_approved) {
      return climbFrom == null
          ? ChartMomentRules.legacy
          : ChartMomentRules(devicePolishFromUtc: climbFrom);
    }

    final rules = await (_resolved ??= _resolve().then((rules) {
      if (rules.activatedAtUtc == null) _resolved = null;
      return rules;
    }));
    return climbFrom == null
        ? rules
        : ChartMomentRules(
            activatedAtUtc: rules.activatedAtUtc,
            catalogStarts: rules.catalogStarts,
            devicePolishFromUtc: climbFrom,
          );
  }

  /// The climb wording's start on this install, recorded once on the first
  /// run that carries it. Stories already told happened before it, so they
  /// keep their words. Unreadable or unsaved: no story changes words this
  /// run, and a later run tries again.
  Future<DateTime?> _devicePolishFrom() async {
    final known = _devicePolishStart;
    if (known != null) return known;
    final store = _devicePolish;
    if (store == null) return null;
    try {
      var stored = await store.readDevicePolishStart();
      if (stored == null) {
        await store.writeDevicePolishStart(_now().toUtc().toIso8601String());
        stored = await store.readDevicePolishStart();
        if (stored == null) {
          throw StateError('The climb wording start was not saved.');
        }
      }
      return _devicePolishStart = _instant(stored);
    } catch (error, stackTrace) {
      developer.log(
        'The Moments climb wording start could not be read or saved '
        '(${error.runtimeType}); stories keep their first wording',
        name: 'sonus.charts',
        level: 900,
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  Future<ChartMomentRules> _resolve() async {
    try {
      var stored = await _store.read();
      if (stored == null) {
        await _store.write(_now().toUtc().toIso8601String());
        stored = await _store.read();
        if (stored == null) {
          throw StateError('The activation instant was not saved.');
        }
      }
      final activated = _instant(stored);
      return ChartMomentRules(
        activatedAtUtc: activated,
        catalogStarts: await _catalogStarts(),
      );
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

  /// Where each refined catalog version after the first starts (SN-50
  /// R-V). A version this build carries but has not recorded starts now:
  /// later than every story already told, so those keep their catalog. An
  /// absent instant is never read as an earlier one.
  ///
  /// A start recorded by a newer build means stories here were told with a
  /// catalog this build lacks; rather than re-tell them, the run keeps the
  /// earlier rules.
  Future<List<RefinedCatalogStart>> _catalogStarts() async {
    if (await _store.readCatalogStart(_catalogVersion + 1) != null) {
      throw StateError(
        'A newer refined catalog was used on this install than this build '
        'carries.',
      );
    }
    final starts = <RefinedCatalogStart>[];
    for (var version = 2; version <= _catalogVersion; version++) {
      var stored = await _store.readCatalogStart(version);
      if (stored == null) {
        await _store.writeCatalogStart(
          version,
          _now().toUtc().toIso8601String(),
        );
        stored = await _store.readCatalogStart(version);
        if (stored == null) {
          throw StateError('Catalog version $version start was not saved.');
        }
      }
      starts.add(RefinedCatalogStart(version, _instant(stored)));
    }
    return starts;
  }

  /// An unreadable instant is kept, never replaced: Moments keep the
  /// earlier rules until it is repaired.
  static DateTime _instant(String stored) {
    final instant = DateTime.tryParse(stored);
    if (instant == null || !instant.isUtc) {
      throw FormatException('Unreadable activation instant', stored);
    }
    return instant;
  }
}
