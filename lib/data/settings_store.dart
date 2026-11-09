import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Non-secret preferences and unlock-attempt counters.
class AppSettings {
  const AppSettings({
    this.themeMode = ThemeMode.light,
    this.autoLockMinutes = 2,
    this.lockOnBackground = true,
    this.clipboardClearSeconds = 30,
    this.requireAuthForSecrets = false,
    this.biometricEnabled = false,
    this.expiryLeadDays = 30,
  });

  final ThemeMode themeMode;
  final int autoLockMinutes; // inactivity timeout
  final bool lockOnBackground;
  final int clipboardClearSeconds; // 0 = never
  final bool requireAuthForSecrets;
  final bool biometricEnabled;
  final int expiryLeadDays; // 0 = expiry reminders off

  AppSettings copyWith({
    ThemeMode? themeMode,
    int? autoLockMinutes,
    bool? lockOnBackground,
    int? clipboardClearSeconds,
    bool? requireAuthForSecrets,
    bool? biometricEnabled,
    int? expiryLeadDays,
  }) => AppSettings(
    themeMode: themeMode ?? this.themeMode,
    autoLockMinutes: autoLockMinutes ?? this.autoLockMinutes,
    lockOnBackground: lockOnBackground ?? this.lockOnBackground,
    clipboardClearSeconds: clipboardClearSeconds ?? this.clipboardClearSeconds,
    requireAuthForSecrets: requireAuthForSecrets ?? this.requireAuthForSecrets,
    biometricEnabled: biometricEnabled ?? this.biometricEnabled,
    expiryLeadDays: expiryLeadDays ?? this.expiryLeadDays,
  );
}

class SettingsStore {
  SettingsStore(this._p);
  final SharedPreferences _p;

  AppSettings load() => AppSettings(
    themeMode: ThemeMode.values.firstWhere(
      (m) => m.name == _p.getString('theme'),
      orElse: () => ThemeMode.light,
    ),
    autoLockMinutes: _p.getInt('autoLockMinutes') ?? 2,
    lockOnBackground: _p.getBool('lockOnBackground') ?? true,
    clipboardClearSeconds: _p.getInt('clipboardClear') ?? 30,
    requireAuthForSecrets: _p.getBool('requireAuth') ?? false,
    biometricEnabled: _p.getBool('biometric') ?? false,
    expiryLeadDays: _p.getInt('expiryLeadDays') ?? 30,
  );

  Future<void> save(AppSettings s) async {
    await _p.setString('theme', s.themeMode.name);
    await _p.setInt('autoLockMinutes', s.autoLockMinutes);
    await _p.setBool('lockOnBackground', s.lockOnBackground);
    await _p.setInt('clipboardClear', s.clipboardClearSeconds);
    await _p.setBool('requireAuth', s.requireAuthForSecrets);
    await _p.setBool('biometric', s.biometricEnabled);
    await _p.setInt('expiryLeadDays', s.expiryLeadDays);
  }

  int get failedAttempts => _p.getInt('failedAttempts') ?? 0;
  DateTime? get lockedUntil {
    final ms = _p.getInt('lockedUntil');
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  Future<void> saveAttempts(int failed, DateTime? lockedUntil) async {
    await _p.setInt('failedAttempts', failed);
    if (lockedUntil == null) {
      await _p.remove('lockedUntil');
    } else {
      await _p.setInt('lockedUntil', lockedUntil.millisecondsSinceEpoch);
    }
  }

  Future<void> clearAll() => _p.clear();
}
