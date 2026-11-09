import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class _Brand {
  const _Brand(this.bg, this.glyph);
  final String bg;
  final String glyph;
}

// Simplified, original glyphs drawn on brand-coloured tiles (40x40 viewBox).
const Map<String, _Brand> _brands = {
  'Gmail': _Brand(
    '#FFFFFF',
    '<path d="M6 12v16h5V18l9 7 9-7v10h5V12l-3-2-11 8.5L9 10z" fill="#EA4335"/>'
        '<path d="M6 12l3-2 2 1.5V28H6z" fill="#C5221F"/>'
        '<path d="M34 12l-3-2-2 1.5V28h5z" fill="#34A853"/>'
        '<path d="M29 11.5V18l5-3.8V12l-3-2z" fill="#FBBC04"/>'
        '<path d="M11 11.5V18l-5-3.8V12l3-2z" fill="#4285F4"/>',
  ),
  'Outlook / Hotmail': _Brand(
    '#0A64C8',
    '<rect x="7" y="11" width="15" height="18" rx="2" fill="#fff" opacity=".25"/>'
        '<rect x="14" y="14" width="19" height="13" rx="1.5" fill="#fff"/>'
        '<path d="M14 15l9.5 7L33 15" stroke="#0A64C8" stroke-width="1.8" fill="none"/>'
        '<circle cx="14" cy="20" r="6.5" fill="#0A64C8" stroke="#fff" stroke-width="1.6"/>'
        '<ellipse cx="14" cy="20" rx="2.6" ry="3.4" fill="none" stroke="#fff" stroke-width="1.6"/>',
  ),
  'Yahoo': _Brand(
    '#6001D2',
    '<path d="M9 12h5l4.5 7.5L23 12h5l-7.5 12.5V32h-4.2v-7.5z" fill="#fff"/>'
        '<path d="M29 22h4.5L28 32h-4.5z" fill="#fff"/>',
  ),
  'Zoho': _Brand(
    '#E42527',
    '<path d="M11 12h18v4L16.5 26H29v4H11v-4l12.5-10H11z" fill="#fff"/>',
  ),
  'Proton': _Brand(
    '#6D4AFF',
    '<path d="M8 13l12 9 12-9v-1.5H8z" fill="#fff" opacity=".55"/>'
        '<path d="M8 13v14a2 2 0 002 2h20a2 2 0 002-2V13l-12 9z" fill="#fff"/>',
  ),
  'iCloud': _Brand(
    '#3B9CF5',
    '<path d="M13 28a6 6 0 01-.6-11.9A8 8 0 0128 15a6.5 6.5 0 01-1 13z" fill="#fff"/>',
  ),
  'Official / Govt (NIC)': _Brand(
    '#0F5E3A',
    '<path d="M20 8l11 4v7c0 7-5 11-11 13-6-2-11-6-11-13v-7z" fill="#fff"/>'
        '<circle cx="20" cy="19" r="5" fill="none" stroke="#0F5E3A" stroke-width="1.8"/>'
        '<path d="M20 14v10M15 19h10" stroke="#0F5E3A" stroke-width="1.4"/>',
  ),
  'Other': _Brand(
    '#64748B',
    '<rect x="8" y="12" width="24" height="16" rx="2.5" fill="#fff"/>'
        '<path d="M9 14l11 8 11-8" stroke="#64748B" stroke-width="2" fill="none"/>',
  ),
};

/// Rounded tile with the provider's icon. Unknown names show the generic mail
/// icon. Decorative: the provider name is always shown as text beside it.
class ProviderIcon extends StatelessWidget {
  const ProviderIcon(this.provider, {super.key, this.size = 40});
  final String provider;
  final double size;

  @override
  Widget build(BuildContext context) {
    final b = _brands[provider] ?? _brands['Other']!;
    final svg =
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 40 40">'
        '<rect width="40" height="40" rx="9" fill="${b.bg}"/>${b.glyph}</svg>';
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(size * 0.25),
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
            width: b.bg == '#FFFFFF' ? 1 : 0,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: SvgPicture.string(svg, width: size, height: size),
      ),
    );
  }
}
