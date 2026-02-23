// drop_target_interface.dart
// This file re-exports DropTarget using Dart's conditional import.
// On non-IO platforms (web), the stub is used.
// On all native IO platforms, we check at runtime via _isDesktopPlatform.

// Since desktop_drop only has desktop plugin implementations,
// we permanently use the stub class and check Platform at runtime.
// The real DropTarget is only active inside _isDesktopPlatform == true guards.

export 'package:speedshare/stubs/desktop_drop_stub.dart';
