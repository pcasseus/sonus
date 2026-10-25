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
/// The bar is hidden while nothing is queued and while the keyboard is
/// open. While Now Playing opens, the bar folds away in step with it, so
/// the page underneath never jumps and there is only ever one player
/// surface on screen.
///
/// SN-45: the host also owns the system navigation area. Routes are laid
/// out above it, and it is painted with the page background, so no content
/// runs under a gesture handle or the three-button bar, and no stray black
/// panel shows there. Now Playing alone draws its atmosphere behind it.
///
/// The bar's look is [barBuilder]'s: the playback slot by default.
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

  /// The route observer of the enclosing host, or null outside a host.
  static PlaybackHostRouteObserver? routesOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_PlaybackHostScope>()?.routes;

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
            routes: widget.routes,
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
    final systemBottom = MediaQuery.paddingOf(context).bottom;
    final showBar = hasTrack && !keyboardOpen;

    return ValueListenableBuilder<double>(
      valueListenable: routes.nowPlayingCoverage,
      builder: (context, coverage, _) {
        // How much of the bottom area is still shown: all of it normally,
        // none once Now Playing has fully opened.
        final shown = (1 - coverage).clamp(0.0, 1.0);
        final reserves = shown > 0 && (showBar || systemBottom > 0);

        final Widget bottom = showBar
            ? KeyedSubtree(
                key: const ValueKey<String>('playback-host-bar'),
                child: barBuilder(context),
              )
            : ColoredBox(
                key: const ValueKey<String>('playback-host-system-inset'),
                color: Theme.of(context).scaffoldBackgroundColor,
                child: SizedBox(height: systemBottom, width: double.infinity),
              );

        return Column(
          children: [
            Expanded(
              // The bottom area takes the bottom safe area; routes above
              // it must not pad for it again.
              child: reserves
                  ? MediaQuery.removePadding(
                      context: context,
                      removeBottom: true,
                      child: child,
                    )
                  : child,
            ),
            if (shown > 0 && (showBar || systemBottom > 0))
              ClipRect(
                child: Align(
                  alignment: Alignment.topCenter,
                  heightFactor: shown,
                  child: ExcludeFocus(
                    // Folding away under Now Playing: not reachable, not
                    // announced.
                    excluding: coverage > 0,
                    child: ExcludeSemantics(
                      excluding: coverage > 0,
                      child: bottom,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _PlaybackHostScope extends InheritedWidget {
  const _PlaybackHostScope({
    required this.navigatorKey,
    required this.routes,
    required super.child,
  });

  final GlobalKey<NavigatorState> navigatorKey;
  final PlaybackHostRouteObserver routes;

  @override
  bool updateShouldNotify(_PlaybackHostScope oldWidget) =>
      oldWidget.navigatorKey != navigatorKey || oldWidget.routes != routes;
}

/// Tracks Now Playing on the root navigator.
class PlaybackHostRouteObserver extends NavigatorObserver {
  /// Whether Now Playing is the top route.
  final ValueNotifier<bool> nowPlayingOnTop = ValueNotifier(false);

  /// How far Now Playing covers the screen, from 0 to 1, following its
  /// route animation as it opens and closes. 0 when another route is on
  /// top of it.
  final ValueNotifier<double> nowPlayingCoverage = ValueNotifier(0);

  final List<Route<dynamic>> _stack = [];
  ModalRoute<dynamic>? _nowPlaying;
  Animation<double>? _animation;

  /// Set while a just-pushed Now Playing has not animated yet. At push
  /// time its animation can still read as finished for one frame, which
  /// would hide the bar and bring it back: a visible jump.
  bool _awaitingFirstTick = false;

  /// Whether a Now Playing route is open or opening (to avoid stacking a
  /// second one).
  bool get hasNowPlaying => _nowPlaying != null;

  void _update() {
    final top = _stack.isEmpty ? null : _stack.last;
    nowPlayingOnTop.value =
        top != null && top.settings.name == NowPlayingPage.routeName;
    _updateCoverage();
  }

  void _updateCoverage() {
    final route = _nowPlaying;
    final animation = _animation;

    if (route == null || animation == null || _awaitingFirstTick) {
      nowPlayingCoverage.value = 0;
      return;
    }

    final isTop = _stack.isNotEmpty && identical(_stack.last, route);
    final closing = !_stack.contains(route);
    nowPlayingCoverage.value = isTop || closing ? animation.value : 0;
  }

  void _track(Route<dynamic> route) {
    if (route.settings.name != NowPlayingPage.routeName ||
        route is! ModalRoute<dynamic>) {
      return;
    }

    _animation?.removeListener(_onTick);
    _animation?.removeStatusListener(_onStatus);
    _nowPlaying = route;
    // A route without a transition (reduced motion) is open at once.
    _awaitingFirstTick = route.transitionDuration > Duration.zero;
    _animation = route.animation
      ?..addListener(_onTick)
      ..addStatusListener(_onStatus);
  }

  void _onTick() {
    if (_isPushArtifact()) return;
    _awaitingFirstTick = false;
    _updateCoverage();
  }

  /// While a route is being pushed its animation can briefly report a
  /// finished state before its transition starts. A route that animates
  /// cannot really be finished before its first tick.
  bool _isPushArtifact() {
    final route = _nowPlaying;
    final animation = _animation;
    return _awaitingFirstTick &&
        route != null &&
        route.transitionDuration > Duration.zero &&
        animation != null &&
        animation.status == AnimationStatus.completed;
  }

  void _onStatus(AnimationStatus status) {
    // A route with no transition (reduced motion) reports completion
    // without ticking.
    if (_isPushArtifact()) return;
    _awaitingFirstTick = false;

    // Fully closed: forget the route once it has left the stack.
    if (status == AnimationStatus.dismissed &&
        _nowPlaying != null &&
        !_stack.contains(_nowPlaying)) {
      _animation?.removeListener(_onTick);
      _animation?.removeStatusListener(_onStatus);
      _nowPlaying = null;
      _animation = null;
    }
    _updateCoverage();
  }

  void _forget(Route<dynamic> route) {
    // A route removed without animating (removeRoute) never reports
    // dismissed.
    if (identical(route, _nowPlaying) &&
        (_animation == null || _animation!.isDismissed)) {
      _onStatus(AnimationStatus.dismissed);
    }
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _stack.add(route);
    _track(route);
    _update();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _stack.remove(route);
    _update();
    _forget(route);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _stack.remove(route);
    _update();
    if (identical(route, _nowPlaying)) {
      _animation?.removeListener(_onTick);
      _animation?.removeStatusListener(_onStatus);
      _nowPlaying = null;
      _animation = null;
      _updateCoverage();
    }
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final index = oldRoute == null ? -1 : _stack.indexOf(oldRoute);
    if (index >= 0 && newRoute != null) {
      _stack[index] = newRoute;
    } else if (newRoute != null) {
      _stack.add(newRoute);
    }
    if (newRoute != null) _track(newRoute);
    _update();
  }
}
