import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/providers.dart';
import 'helpers.dart';
import 'screens/setup_screen.dart';
import 'screens/splash_screen.dart';
import 'screens/shell_screen.dart';
import 'screens/unlock_screen.dart';
import 'theme.dart';

final navigatorKey = GlobalKey<NavigatorState>();

class SecureVaultApp extends ConsumerStatefulWidget {
  const SecureVaultApp({super.key});

  @override
  ConsumerState<SecureVaultApp> createState() => _SecureVaultAppState();
}

class _SecureVaultAppState extends ConsumerState<SecureVaultApp> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(vaultProvider.notifier).init());
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);

    // Locking must also dismiss any screens pushed on top of the root.
    ref.listen(vaultProvider.select((s) => s.status), (prev, next) {
      if (next != VaultStatus.unlocked) {
        navigatorKey.currentState?.popUntil((r) => r.isFirst);
      }
    });

    return MaterialApp(
      title: 'SecureVault',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: settings.themeMode,
      builder: (context, child) =>
          PrivacyAndAutoLock(child: child ?? const SizedBox()),
      home: const RootGate(),
    );
  }
}

/// Minimum time the splash stays up on a cold start. Tests override it to zero.
final splashMinDurationProvider = Provider<Duration>(
  (ref) => const Duration(milliseconds: 1400),
);

class RootGate extends ConsumerStatefulWidget {
  const RootGate({super.key});

  @override
  ConsumerState<RootGate> createState() => _RootGateState();
}

class _RootGateState extends ConsumerState<RootGate> {
  Timer? _timer;
  bool _splashDone = false;

  @override
  void initState() {
    super.initState();
    final d = ref.read(splashMinDurationProvider);
    if (d == Duration.zero) {
      _splashDone = true;
    } else {
      _timer = Timer(d, () {
        if (mounted) setState(() => _splashDone = true);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(vaultProvider.select((s) => s.status));
    if (!_splashDone) return const SplashScreen();
    return switch (status) {
      VaultStatus.loading => const SplashScreen(),
      VaultStatus.noVault => const SetupScreen(),
      VaultStatus.locked => const UnlockScreen(),
      VaultStatus.unlocked => const ShellScreen(),
    };
  }
}

/// Inactivity auto-lock, lock-on-background, and a privacy cover so the
/// app-switcher snapshot never shows vault content.
class PrivacyAndAutoLock extends ConsumerStatefulWidget {
  const PrivacyAndAutoLock({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<PrivacyAndAutoLock> createState() => _PrivacyAndAutoLockState();
}

class _PrivacyAndAutoLockState extends ConsumerState<PrivacyAndAutoLock>
    with WidgetsBindingObserver {
  Timer? _timer;
  bool _covered = false;
  DateTime? _backgroundedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  bool get _unlocked => ref.read(vaultProvider).status == VaultStatus.unlocked;

  void _resetTimer() {
    _timer?.cancel();
    if (!_unlocked) return;
    final minutes = ref.read(settingsProvider).autoLockMinutes;
    if (minutes <= 0) return;
    _timer = Timer(Duration(minutes: minutes), _lockIfIdle);
  }

  void _lockIfIdle() {
    if (!_unlocked) return;
    if (ref.read(lockGuardProvider).active) {
      _resetTimer();
      return;
    }
    ref.read(vaultProvider.notifier).lock();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final away = state != AppLifecycleState.resumed;
    if (_covered != away) setState(() => _covered = away);
    if (!_unlocked) return;
    final guarded = ref.read(lockGuardProvider).active;

    if (away) {
      _backgroundedAt ??= DateTime.now();
      if (!guarded &&
          state == AppLifecycleState.paused &&
          ref.read(settingsProvider).lockOnBackground) {
        ref.read(vaultProvider.notifier).lock();
      }
    } else {
      // Resumed: enforce the inactivity timeout even if timers were frozen.
      final since = _backgroundedAt;
      _backgroundedAt = null;
      final minutes = ref.read(settingsProvider).autoLockMinutes;
      if (since != null &&
          !guarded &&
          minutes > 0 &&
          DateTime.now().difference(since) >= Duration(minutes: minutes)) {
        ref.read(vaultProvider.notifier).lock();
      } else {
        _resetTimer();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Re-arm whenever status or the timeout setting changes.
    ref.listen(vaultProvider.select((s) => s.status), (_, _) => _resetTimer());
    ref.listen(
      settingsProvider.select((s) => s.autoLockMinutes),
      (_, _) => _resetTimer(),
    );
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _resetTimer(),
      onPointerSignal: (_) => _resetTimer(),
      child: Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          if (_covered)
            ColoredBox(
              color: Theme.of(context).colorScheme.surface,
              child: const Center(child: Icon(Icons.lock_outline, size: 64)),
            ),
        ],
      ),
    );
  }
}
