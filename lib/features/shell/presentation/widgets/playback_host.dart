import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../player/presentation/controllers/playback_state_controller.dart';
import '../../../player/presentation/pages/now_playing_page.dart';
import 'shell_playback_slot.dart';

/// The one place playback controls live: below every route of the app.
///
/// Installed once, by [MaterialApp.builder] around the root navigator, so
/// Home, Library, pushed pages, Studios, Import, Settings, Queue and Lyrics
/// all get the same mini-player without each page adding one. The routes
/// sit above the bar, so it never covers their content or controls.
///
/// The bar is hidden while nothing is queued, while the keyboard is open,
/// and while Now Playing, which has its own full controls, is on top.
///
/// The bar's look is [barBuilder]'s: the playback slot by default, and the
/// SN-48 SonusMiniPlayer once it is wired to playback.
class PlaybackHost extends StatefulWidget {
  const PlaybackHost({
    super.key,
    required this.navigatorKey,
    required this.routes,
    required this.child,
    this.barBuilder,
  });

  /// The root navigator, which the bar opens Now Playing and Queue on.
  final GlobalKey<NavigatorState> navigatorKey;

  /// Registered as a navigator observer of the root navigator.
  final PlaybackHostRouteObserver routes;

  /// The root navigator, as given to [MaterialApp.builder].
  final Widget child;

  final WidgetBuilder? barBuilder;

  /// The navigator the bar navigates with, or null outside a host.
  static NavigatorState? navigatorOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<_PlaybackHostScope>()
      ?.navigatorKey
      .currentState;

  @override
  State<PlaybackHost> createState() => _PlaybackHostState();
}

class _PlaybackHostState extends State<PlaybackHost> {
  @override
  Widget build(BuildContext context) {
    // An overlay of its own, so the bar's tooltips and menus work although
    // it sits outside the navigator's overlay.
    return Overlay(
      initialEntries: [
        OverlayEntry(
          builder: (context) => _PlaybackHostScope(
            navigatorKey: widget.navigatorKey,
            child: _HostLayout(
              routes: widget.routes,
              barBuilder: widget.barBuilder ?? (_) => const ShellPlaybackSlot(),
              child: widget.child,
            ),
          ),
        ),
      ],
    );
  }
}

class _HostLayout extends StatelessWidget {
  const _HostLayout({
    required this.routes,
    required this.barBuilder,
    required this.child,
  });

  final PlaybackHostRouteObserver routes;
  final WidgetBuilder barBuilder;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final hasTrack = context.select<PlaybackStateController, bool>(
      (controller) => controller.state.queue.currentTrack != null,
    );
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;

    return ValueListenableBuilder<bool>(
      valueListenable: routes.nowPlayingOnTop,
      builder: (context, nowPlayingOnTop, _) {
        final showBar = hasTrack && !keyboardOpen && !nowPlayingOnTop;

        return Column(
          children: [
            Expanded(
              // The bar takes the bottom safe area; routes above it must
              // not pad for it again.
              child: showBar
                  ? MediaQuery.removePadding(
                      context: context,
                      removeBottom: true,
                      child: child,
                    )
                  : child,
            ),
            if (showBar)
              KeyedSubtree(
                key: const ValueKey<String>('playback-host-bar'),
                child: barBuilder(context),
              ),
          ],
        );
      },
    );
  }
}

class _PlaybackHostScope extends InheritedWidget {
  const _PlaybackHostScope({required this.navigatorKey, required super.child});

  final GlobalKey<NavigatorState> navigatorKey;

  @override
  bool updateShouldNotify(_PlaybackHostScope oldWidget) =>
      oldWidget.navigatorKey != navigatorKey;
}

/// Tracks whether Now Playing is the top route of the root navigator.
class PlaybackHostRouteObserver extends NavigatorObserver {
  final ValueNotifier<bool> nowPlayingOnTop = ValueNotifier(false);

  final List<Route<dynamic>> _stack = [];

  void _update() {
    nowPlayingOnTop.value =
        _stack.isNotEmpty &&
        _stack.last.settings.name == NowPlayingPage.routeName;
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _stack.add(route);
    _update();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _stack.remove(route);
    _update();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _stack.remove(route);
    _update();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final index = oldRoute == null ? -1 : _stack.indexOf(oldRoute);
    if (index >= 0 && newRoute != null) {
      _stack[index] = newRoute;
    } else if (newRoute != null) {
      _stack.add(newRoute);
    }
    _update();
  }
}
