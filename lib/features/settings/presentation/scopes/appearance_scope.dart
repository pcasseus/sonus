import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/design/sonus_theme_factory.dart';
import '../../application/controllers/appearance_controller.dart';
import '../../data/appearance_preferences_store.dart';

/// Provides the [AppearanceController] to the whole app.
///
/// Placed above the restart scope, so the theme survives a reload after a
/// restore. It re-evaluates the schedule when the app resumes and follows
/// the device's high-contrast and reduced-motion settings.
class AppearanceScope extends StatefulWidget {
  const AppearanceScope({super.key, this.controller, required this.child});

  /// An existing controller (tests). When null the scope creates, loads and
  /// disposes its own.
  final AppearanceController? controller;
  final Widget child;

  @override
  State<AppearanceScope> createState() => _AppearanceScopeState();
}

class _AppearanceScopeState extends State<AppearanceScope>
    with WidgetsBindingObserver {
  late final AppearanceController _controller;
  late final bool _ownsController;

  @override
  void initState() {
    super.initState();

    _ownsController = widget.controller == null;
    _controller =
        widget.controller ??
        AppearanceController(store: AppearancePreferencesStore());

    WidgetsBinding.instance.addObserver(this);
    _readAccessibilityFeatures();

    if (_ownsController) {
      unawaited(_controller.load());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _controller.refresh();
    }
  }

  @override
  void didChangeAccessibilityFeatures() {
    _readAccessibilityFeatures();
  }

  void _readAccessibilityFeatures() {
    final features =
        WidgetsBinding.instance.platformDispatcher.accessibilityFeatures;

    _controller.updateSystemAccessibility(
      highContrast: features.highContrast,
      reduceMotion: features.disableAnimations || features.reduceMotion,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);

    if (_ownsController) {
      _controller.dispose();
    }

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<AppearanceController>.value(
      value: _controller,
      child: widget.child,
    );
  }
}

typedef SonusThemedAppWidgetBuilder =
    Widget Function(
      BuildContext context,
      ThemeData theme,
      Duration themeAnimationDuration,
    );

/// Builds the app with the active Sonus theme.
///
/// Without an [AppearanceScope] above it, the default Concrete & Spray
/// theme is used. The first theme applied after loading, and every change
/// under reduced motion, switch without animation.
class SonusThemedAppBuilder extends StatefulWidget {
  const SonusThemedAppBuilder({super.key, required this.builder});

  final SonusThemedAppWidgetBuilder builder;

  @override
  State<SonusThemedAppBuilder> createState() => _SonusThemedAppBuilderState();
}

class _SonusThemedAppBuilderState extends State<SonusThemedAppBuilder> {
  bool _wasLoaded = false;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppearanceController?>();

    if (controller == null) {
      return widget.builder(
        context,
        SonusThemeFactory.build(const SonusAppearanceSpec()),
        kThemeAnimationDuration,
      );
    }

    final firstLoadedFrame = controller.isLoaded && !_wasLoaded;
    _wasLoaded = controller.isLoaded;

    final animate =
        controller.isLoaded &&
        !firstLoadedFrame &&
        !controller.spec.reduceMotion;

    return widget.builder(
      context,
      controller.theme,
      animate ? kThemeAnimationDuration : Duration.zero,
    );
  }
}
