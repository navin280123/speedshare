// Stub for desktop_drop on mobile/web platforms.
// This file is never actually imported — the real package is used on desktop.
// It exists only to satisfy Dart's conditional import system.

import 'package:flutter/material.dart';

/// No-op DropTarget for platforms that don't support desktop_drop.
class DropTarget extends StatelessWidget {
  final Widget child;
  final void Function(dynamic)? onDragDone;
  final void Function(dynamic)? onDragEntered;
  final void Function(dynamic)? onDragExited;

  const DropTarget({
    super.key,
    required this.child,
    this.onDragDone,
    this.onDragEntered,
    this.onDragExited,
  });

  @override
  Widget build(BuildContext context) => child;
}
