import 'package:flutter/material.dart';

import '../widgets/app_logo.dart';

/// Shown while the app starts and the vault state loads. Matches the native
/// launch screen so there is no visible jump. Shows no vault data.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: brandDeepBlue,
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: splashGradient),
        child: SafeArea(
          child: Column(
            children: [
              const Spacer(flex: 5),
              const AppLogo(size: 128, onDark: true),
              const SizedBox(height: 24),
              const Text(
                'SecureVault',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Your Personal\nCredential Manager',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFFDCE7FF),
                  fontSize: 16,
                  height: 1.35,
                ),
              ),
              const Spacer(flex: 4),
              const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.white70,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Secure  •  Organize  •  Access',
                style: TextStyle(color: Color(0xFFDCE7FF), fontSize: 13),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
