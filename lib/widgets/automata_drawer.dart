import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../markdown_file_screen.dart';

class AutomataDrawer extends StatelessWidget {
  final bool showHelpOverlay;
  final bool showSimulator;
  final bool isGuest;
  final String? accountLabel;
  final ValueChanged<bool> onShowHelpChanged;
  final ValueChanged<bool> onShowSimulatorChanged;
  final VoidCallback onBatchSimulator;
  final VoidCallback onExport;
  final VoidCallback onImport;
  final VoidCallback onExportHistory;
  final Future<void> Function()? onSignOut;

  const AutomataDrawer({
    super.key,
    required this.showHelpOverlay,
    required this.showSimulator,
    this.isGuest = false,
    this.accountLabel,
    required this.onShowHelpChanged,
    required this.onShowSimulatorChanged,
    required this.onBatchSimulator,
    required this.onExport,
    required this.onImport,
    required this.onExportHistory,
    this.onSignOut,
  });

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            const SizedBox(height: 8),
            if (accountLabel != null)
              ListTile(
                leading: Icon(isGuest ? Icons.person_outline : Icons.account_circle),
                title: Text(
                  isGuest ? 'Guest mode' : 'Signed in',
                  style: GoogleFonts.courierPrime(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(accountLabel!),
              ),
            ListTile(
              title: Text('Batch Simulator', style: GoogleFonts.courierPrime()),
              onTap: () {
                Navigator.pop(context);
                onBatchSimulator();
              },
            ),
            SwitchListTile(
              title: const Text('Show Help'),
              subtitle: const Text('Displays controls and textbox commands.'),
              value: showHelpOverlay,
              onChanged: onShowHelpChanged,
            ),
            SwitchListTile(
              title: const Text('String Simulator'),
              subtitle: const Text('Show/hide the simulator panel.'),
              value: showSimulator,
              onChanged: onShowSimulatorChanged,
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.upload_file),
              title: const Text('Export'),
              subtitle: const Text('Copy graph to clipboard'),
              onTap: () {
                Navigator.pop(context);
                onExport();
              },
            ),
            ListTile(
              leading: const Icon(Icons.download),
              title: const Text('Import'),
              subtitle: const Text('Load graph from clipboard or text input'),
              onTap: () {
                Navigator.pop(context);
                onImport();
              },
            ),
            const Divider(),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.history),
              title: const Text('Export History'),
              subtitle: const Text('View saved exports'),
              onTap: () {
                Navigator.pop(context);
                onExportHistory();
              },
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const MarkdownFileScreen(title: 'About', assetPath: 'assets/About.md'),
                  ),
                );
              },
              child: const Text('View About'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const MarkdownFileScreen(title: 'Changelog', assetPath: 'assets/Changelog.md'),
                  ),
                );
              },
              child: const Text('View Changelog'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const MarkdownFileScreen(title: 'Version', assetPath: 'assets/Version.md'),
                  ),
                );
              },
              child: const Text('View Version'),
            ),
            if (onSignOut != null) ...[
              const Divider(),
              ListTile(
                leading: const Icon(Icons.logout),
                title: const Text('Sign out'),
                onTap: () async {
                  Navigator.pop(context);
                  await onSignOut!();
                },
              ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
