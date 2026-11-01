import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Keeps a closed keyboard from leaving an empty gap (SN-50 device QA).
///
/// Every page, dialog and sheet sits below it, so one rule covers them all:
///
/// - **Returning to Sonus.** When Sonus is sent to the background while a
///   text field has focus, Flutter restores that focus on return and asks
///   for the keyboard again while the activity is still resuming. On the
///   device the keyboard may not come back, yet its inset stays reported,
///   leaving a gap where it was. Instead, a field that was being edited
///   when Sonus went to the background is left unfocused on return and the
///   keyboard is asked to close; the text typed so far stays in the field,
///   and a tap on it opens the keyboard again.
/// - **No field, no keyboard space.** A bottom inset only reserves space
///   while a text field has focus. Without one, any keyboard inset still
///   reported is stale, so pages and sheets lay out as if it were closed.
///
/// A short interruption that keeps Sonus visible (the notification shade,
/// a permission prompt) is not "the background": Flutter restores the
/// field and its keyboard as usual.
class KeyboardInsetGuard extends StatefulWidget {
  const KeyboardInsetGuard({super.key, required this.child});

  final Widget child;

  @override
  State<KeyboardInsetGuard> createState() => _KeyboardInsetGuardState();
}

class _KeyboardInsetGuardState extends State<KeyboardInsetGuard>
    with WidgetsBindingObserver {
  /// The field being edited the last time Sonus was in the foreground.
  FocusNode? _editedNode;

  /// Sonus went to the background while [_editedNode] was being edited.
  bool _leftWhileEditing = false;

  bool _editing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    FocusManager.instance.addListener(_handleFocusChange);
    // Read focus once this frame is built: during a rebuild of the app
    // (a restore reload) focus can still point into the tree being
    // replaced, which must not be looked up.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _handleFocusChange();
    });
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_handleFocusChange);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  static bool _resumed() {
    final state = WidgetsBinding.instance.lifecycleState;
    return state == null || state == AppLifecycleState.resumed;
  }

  /// Whether the focused node belongs to a text field.
  static bool _isEditing() {
    final context = FocusManager.instance.primaryFocus?.context;
    if (context == null || !context.mounted) return false;
    return context.widget is EditableText ||
        context.findAncestorStateOfType<EditableTextState>() != null;
  }

  void _handleFocusChange() {
    final editing = _isEditing();
    // While Sonus is not in the foreground, Flutter parks focus and gives
    // it back later; that is not the field being closed.
    if (_resumed()) {
      _editedNode = editing ? FocusManager.instance.primaryFocus : null;
    }
    if (editing != _editing && mounted) setState(() => _editing = editing);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        if (_editedNode != null) _leftWhileEditing = true;
      case AppLifecycleState.resumed:
        if (!_leftWhileEditing) break;
        _leftWhileEditing = false;
        final node = _editedNode;
        _editedNode = null;
        // Flutter gives the field its focus back in a microtask; take it
        // away once that has happened, before the keyboard is asked for
        // again by anything else.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (node != null && node.context != null && node.hasFocus) {
            node.unfocus();
          } else if (_isEditing()) {
            FocusManager.instance.primaryFocus?.unfocus();
          }
          SystemChannels.textInput
              .invokeMethod<void>('TextInput.hide')
              .catchError((Object _) {});
        });
        WidgetsBinding.instance.scheduleFrame();
      case AppLifecycleState.inactive:
        break;
    }
    // Whether a field's space is held depends on the lifecycle too.
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final data = MediaQuery.of(context);
    // While Sonus is briefly inactive with a field open, keep its space.
    final holdsKeyboard = _editing || (!_resumed() && _editedNode != null);
    if (holdsKeyboard || data.viewInsets.bottom == 0) return widget.child;

    return MediaQuery(
      data: data.copyWith(viewInsets: data.viewInsets.copyWith(bottom: 0)),
      child: widget.child,
    );
  }
}
