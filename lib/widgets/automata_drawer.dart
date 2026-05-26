import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../markdown_file_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  _HoverTile — list tile with tooltip description on hover, no extra height
// ─────────────────────────────────────────────────────────────────────────────

class _HoverTile extends StatelessWidget {
  final Widget title;
  final String subtitle;
  final Widget? leading;
  final VoidCallback? onTap;

  const _HoverTile({
    required this.title,
    required this.subtitle,
    this.leading,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: subtitle,
      waitDuration: const Duration(milliseconds: 400),
      child: ListTile(
        leading: leading,
        title: title,
        onTap: onTap,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  _HoverSwitch — switch tile with tooltip description on hover, no extra height
// ─────────────────────────────────────────────────────────────────────────────

class _HoverSwitch extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _HoverSwitch({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: subtitle,
      waitDuration: const Duration(milliseconds: 400),
      child: SwitchListTile(
        title: Text(title),
        value: value,
        onChanged: onChanged,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  AutomataDrawer
// ─────────────────────────────────────────────────────────────────────────────

class AutomataDrawer extends StatelessWidget {
  final bool showHelpOverlay;
  final bool showSimulator;
  final bool showPdaMode;
  final bool isGuest;
  final String? accountLabel;
  final ValueChanged<bool> onShowHelpChanged;
  final ValueChanged<bool> onShowSimulatorChanged;
  final ValueChanged<bool> onShowPdaModeChanged;
  final VoidCallback onBatchSimulator;
  final VoidCallback onExport;
  final VoidCallback onImport;
  final VoidCallback onExportHistory;
  final VoidCallback onReset;
  final Future<void> Function()? onSignOut;

  const AutomataDrawer({
    super.key,
    required this.showHelpOverlay,
    required this.showSimulator,
    required this.showPdaMode,
    this.isGuest = false,
    this.accountLabel,
    required this.onShowHelpChanged,
    required this.onShowSimulatorChanged,
    required this.onShowPdaModeChanged,
    required this.onBatchSimulator,
    required this.onExport,
    required this.onImport,
    required this.onExportHistory,
    required this.onReset,
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

            // ── Account ───────────────────────────────────────────────────
            if (accountLabel != null)
              ListTile(
                leading: Icon(isGuest ? Icons.person_outline : Icons.account_circle),
                title: Text(
                  isGuest ? 'Guest mode' : 'Signed in',
                  style: GoogleFonts.courierPrime(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(accountLabel!),
              ),

            const Divider(),

            // ── Toggles ───────────────────────────────────────────────────
            _HoverSwitch(
              title: 'Show Help',
              subtitle: 'Displays controls and textbox commands.',
              value: showHelpOverlay,
              onChanged: onShowHelpChanged,
            ),
            _HoverSwitch(
              title: 'String Simulator',
              subtitle: 'Show/hide the simulator panel.',
              value: showSimulator,
              onChanged: onShowSimulatorChanged,
            ),
            _HoverSwitch(
              title: 'PDA Mode',
              subtitle: 'PDA simulator: labels use read,pop|push format.',
              value: showPdaMode,
              onChanged: onShowPdaModeChanged,
            ),

            const Divider(),

            // ── Actions ───────────────────────────────────────────────────
            _HoverTile(
              leading: const Icon(Icons.science_outlined),
              title: const Text('Batch Simulator'),
              subtitle: 'Test multiple strings at once.',
              onTap: () {
                Navigator.pop(context);
                onBatchSimulator();
              },
            ),
            _HoverTile(
              leading: const Icon(Icons.upload_file),
              title: const Text('Export'),
              subtitle: 'Copy graph DSL to clipboard.',
              onTap: () {
                Navigator.pop(context);
                onExport();
              },
            ),
            _HoverTile(
              leading: const Icon(Icons.download),
              title: const Text('Import'),
              subtitle: 'Load graph from clipboard or text input.',
              onTap: () {
                Navigator.pop(context);
                onImport();
              },
            ),
            _HoverTile(
              leading: const Icon(Icons.history),
              title: const Text('Export History'),
              subtitle: 'View and restore saved exports.',
              onTap: () {
                Navigator.pop(context);
                onExportHistory();
              },
            ),

            const Divider(),

            // ── Docs ──────────────────────────────────────────────────────
            _HoverTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('About'),
              subtitle: 'App info and credits.',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const MarkdownFileScreen(
                        title: 'About', assetPath: 'assets/About.md'),
                  ),
                );
              },
            ),
            _HoverTile(
              leading: const Icon(Icons.update),
              title: const Text('Changelog'),
              subtitle: 'What\'s new in each version.',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const MarkdownFileScreen(
                        title: 'Changelog', assetPath: 'assets/Changelog.md'),
                  ),
                );
              },
            ),
            _HoverTile(
              leading: const Icon(Icons.tag),
              title: const Text('Version'),
              subtitle: 'Current build version.',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const MarkdownFileScreen(
                        title: 'Version', assetPath: 'assets/Version.md'),
                  ),
                );
              },
            ),

            const Divider(),

            // ── Danger zone ───────────────────────────────────────────────
            _HoverTile(
              leading: const Icon(Icons.delete_sweep, color: Colors.red),
              title: const Text('Reset Canvas',
                  style: TextStyle(color: Colors.red)),
              subtitle: 'Clear all nodes, transitions, and the start arrow.',
              onTap: () {
                Navigator.pop(context);
                showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Reset canvas?'),
                    content: const Text(
                        'This will clear all nodes, transitions, and the start arrow.'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancel'),
                      ),
                      FilledButton(
                        style: FilledButton.styleFrom(
                            backgroundColor: Colors.red),
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Reset'),
                      ),
                    ],
                  ),
                ).then((confirmed) {
                  if (confirmed == true) onReset();
                });
              },
            ),

            if (onSignOut != null)
              _HoverTile(
                leading: const Icon(Icons.logout),
                title: const Text('Sign out'),
                subtitle: 'Return to the login screen.',
                onTap: () async {
                  Navigator.pop(context);
                  await onSignOut!();
                },
              ),

            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}