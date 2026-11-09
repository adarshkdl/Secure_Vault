import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/expiry.dart';
import '../../application/providers.dart';
import 'credential_detail_screen.dart';

/// Overdue and upcoming expiry / renewal dates. Shows titles and dates only.
class ExpiryScreen extends ConsumerWidget {
  const ExpiryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(vaultProvider.select((s) => s.data));
    final lead = ref.watch(settingsProvider.select((s) => s.expiryLeadDays));
    if (data == null) return const SizedBox.shrink();
    final report = buildExpiryReport(data, leadDays: lead);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Expiry reminders')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            lead <= 0
                ? 'Reminders are off. Turn them on in Settings.'
                : 'Date fields that are overdue or due within $lead days. Checked on this device while the vault is unlocked; no notifications are sent, so nothing can appear on your lock screen.',
          ),
          const SizedBox(height: 16),
          if (report.isEmpty && lead > 0) const Text('Nothing is due soon.'),
          for (final i in report.items)
            Card(
              child: ListTile(
                leading: Icon(
                  i.isOverdue ? Icons.error_outline : Icons.event_outlined,
                  color: i.isOverdue ? scheme.error : scheme.primary,
                ),
                title: Text(i.credential.title),
                subtitle: Text(
                  '${i.fieldLabel}: ${i.date.toIso8601String().substring(0, 10)} (${describeDays(i.daysLeft)})',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => CredentialDetailScreen(id: i.credential.id),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
