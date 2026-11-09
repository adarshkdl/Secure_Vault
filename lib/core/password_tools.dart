import 'dart:math';

enum Strength { veryWeak, weak, fair, strong, veryStrong }

class PasswordTools {
  static const _lower = 'abcdefghijkmnopqrstuvwxyz';
  static const _upper = 'ABCDEFGHJKLMNPQRSTUVWXYZ';
  static const _digits = '23456789';
  static const _symbols = '!@#\$%^&*()-_=+[]{};:,.?';

  /// Generates a password using the OS CSPRNG, guaranteeing at least one
  /// character from each selected class.
  static String generate({
    int length = 20,
    bool lower = true,
    bool upper = true,
    bool digits = true,
    bool symbols = true,
    Random? random,
  }) {
    final rng = random ?? Random.secure();
    final pools = <String>[
      if (lower) _lower,
      if (upper) _upper,
      if (digits) _digits,
      if (symbols) _symbols,
    ];
    if (pools.isEmpty) pools.add(_lower);
    final len = max(length, pools.length);
    final all = pools.join();
    final chars = <String>[
      for (final p in pools) p[rng.nextInt(p.length)],
      for (var i = pools.length; i < len; i++) all[rng.nextInt(all.length)],
    ]..shuffle(rng);
    return chars.join();
  }

  /// Rough entropy estimate in bits (character-class based). Local only.
  static double entropyBits(String p) {
    if (p.isEmpty) return 0;
    var pool = 0;
    if (RegExp('[a-z]').hasMatch(p)) pool += 26;
    if (RegExp('[A-Z]').hasMatch(p)) pool += 26;
    if (RegExp(r'\d').hasMatch(p)) pool += 10;
    if (RegExp(r'[^A-Za-z0-9]').hasMatch(p)) pool += 32;
    var bits = p.length * (log(pool) / ln2);
    // Penalise repetition / very few distinct characters.
    final distinct = p.split('').toSet().length;
    if (distinct < p.length / 2) bits *= 0.6;
    return bits;
  }

  static Strength strength(String p) {
    final b = entropyBits(p);
    if (b < 28) return Strength.veryWeak;
    if (b < 45) return Strength.weak;
    if (b < 60) return Strength.fair;
    if (b < 80) return Strength.strong;
    return Strength.veryStrong;
  }

  static String label(Strength s) => switch (s) {
    Strength.veryWeak => 'Very weak',
    Strength.weak => 'Weak',
    Strength.fair => 'Fair',
    Strength.strong => 'Strong',
    Strength.veryStrong => 'Very strong',
  };

  static bool isWeak(String p) => strength(p).index <= Strength.weak.index;
}
