import '../domain/field_def.dart';

class Validators {
  static final _email = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
  static final _mac = RegExp(r'^([0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}$');

  static bool isIPv4(String s) {
    final parts = s.split('.');
    if (parts.length != 4) return false;
    for (final p in parts) {
      if (p.isEmpty || p.length > 3 || !RegExp(r'^\d+$').hasMatch(p)) {
        return false;
      }
      final n = int.parse(p);
      if (n > 255) return false;
    }
    return true;
  }

  static bool isIPv6(String s) {
    if (s.isEmpty || !s.contains(':')) return false;
    try {
      final a = Uri.parseIPv6Address(s);
      return a.length == 16;
    } on FormatException {
      return false;
    }
  }

  static bool isIp(String s) => isIPv4(s) || isIPv6(s);

  /// Contiguous-ones IPv4 netmask such as 255.255.254.0.
  static bool isIPv4Mask(String s) {
    if (!isIPv4(s)) return false;
    var bits = 0;
    for (final p in s.split('.')) {
      bits = (bits << 8) | int.parse(p);
    }
    final inverted = (~bits) & 0xFFFFFFFF;
    return (inverted & (inverted + 1)) == 0;
  }

  /// Accepts "24", "/24", "255.255.255.0", or "192.168.1.0/24" / "fd00::/64".
  static bool isSubnet(String s) {
    var v = s.trim();
    if (v.isEmpty) return false;
    if (v.startsWith('/')) v = v.substring(1);
    if (v.contains('/')) {
      final i = v.indexOf('/');
      final addr = v.substring(0, i);
      final prefix = int.tryParse(v.substring(i + 1));
      if (prefix == null) return false;
      if (isIPv4(addr)) return prefix >= 0 && prefix <= 32;
      if (isIPv6(addr)) return prefix >= 0 && prefix <= 128;
      return false;
    }
    if (v.startsWith('/')) v = v.substring(1);
    final n = int.tryParse(v);
    if (n != null) return n >= 0 && n <= 128;
    return isIPv4Mask(v);
  }

  static bool isUrl(String s) {
    final v = s.contains('://') ? s : 'https://$s';
    final u = Uri.tryParse(v);
    return u != null && u.host.contains('.') && !u.host.contains(' ');
  }

  static bool isDate(String s) => DateTime.tryParse(s) != null;

  /// Returns an error message, or null when [value] is acceptable.
  static String? validate(FieldDef f, String? raw) {
    final value = (raw ?? '').trim();
    if (value.isEmpty) {
      return f.required ? '${f.label} is required' : null;
    }
    switch (f.type) {
      case FieldType.email:
        return _email.hasMatch(value) ? null : 'Enter a valid email address';
      case FieldType.url:
        return isUrl(value) ? null : 'Enter a valid URL';
      case FieldType.ip:
        return isIp(value) ? null : 'Enter a valid IPv4 or IPv6 address';
      case FieldType.subnet:
        return isSubnet(value)
            ? null
            : 'Enter a mask (255.255.255.0) or prefix (24, /64)';
      case FieldType.mac:
        return _mac.hasMatch(value) ? null : 'Use format AA:BB:CC:DD:EE:FF';
      case FieldType.port:
        final n = int.tryParse(value);
        return (n != null && n >= 1 && n <= 65535)
            ? null
            : 'Port must be 1-65535';
      case FieldType.number:
        return num.tryParse(value) != null ? null : 'Enter a number';
      case FieldType.date:
        return isDate(value) ? null : 'Enter a valid date (YYYY-MM-DD)';
      case FieldType.phoneList:
        return value
                .split('\n')
                .where((l) => l.trim().isNotEmpty)
                .every((l) => RegExp(r'^[+()\-.\s\d]{5,}$').hasMatch(l.trim()))
            ? null
            : 'Enter valid phone numbers';
      case FieldType.phone:
        return RegExp(r'^[+()\-.\s\d]{5,}$').hasMatch(value)
            ? null
            : 'Enter a valid phone number';
      default:
        return null;
    }
  }
}
