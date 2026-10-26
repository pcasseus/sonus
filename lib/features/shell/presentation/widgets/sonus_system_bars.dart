import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Theme-aware Android status and navigation bars (SN-45).
///
/// Sonus draws edge to edge. Both bars are transparent, with icons that
/// contrast with the theme, and without Android's own contrast scrim. The
/// playback host paints the navigation area with the page background
/// (PlaybackHost), so on gesture or three-button navigation there is no
/// solid black panel and no content shows under the bar. App bars keep
/// setting the status bar over their own area.
///
/// Edge to edge is requested whenever an activity shows Sonus, and never
/// awaited: when Android Auto starts Sonus without a screen there is no
/// window to configure, and startup must not wait for one.
class SonusSystemBars extends StatefulWidget {
  const SonusSystemBars({super.key, required this.child});

  final Widget child;

  /// Asks Android to let Sonus draw behind the system bars. Android 15
  /// and later require it; earlier versions follow the same layout.
  static void enableEdgeToEdge() {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return;
    }

    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.edgeToEdge,
    ).catchError((Object _) {});
  }

  /// The style for a theme of [brightness].
  static SystemUiOverlayStyle styleFor(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final icons = dark ? Brightness.light : Brightness.dark;

    return SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: icons,
      // iOS names the bar's own brightness, not its icons'.
      statusBarBrightness: brightness,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarIconBrightness: icons,
      systemNavigationBarContrastEnforced: false,
      systemStatusBarContrastEnforced: false,
    );
  }

  @override
  State<SonusSystemBars> createState() => _SonusSystemBarsState();
}

class _SonusSystemBarsState extends State<SonusSystemBars>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SonusSystemBars.enableEdgeToEdge();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // An activity appeared (for example after a headless Android Auto
    // start); it gets the same window setup.
    if (state == AppLifecycleState.resumed) {
      SonusSystemBars.enableEdgeToEdge();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SonusSystemBars.styleFor(Theme.of(context).brightness),
      child: widget.child,
    );
  }
}
