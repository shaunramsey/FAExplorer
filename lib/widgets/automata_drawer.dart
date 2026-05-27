import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../markdown_file_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  AutomataMode  — the three simulation modes
// ─────────────────────────────────────────────────────────────────────────────

enum AutomataMode { ndfa, pda, tm }

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
//  _ModeRadioGroup  — compact 3-way radio row for NDFA / PDA / TM
// ─────────────────────────────────────────────────────────────────────────────

class _ModeRadioGroup extends StatelessWidget {
  final AutomataMode value;
  final ValueChanged<AutomataMode> onChanged;

  const _ModeRadioGroup({required this.value, required this.onChanged});

  static const _modes = [
    (mode: AutomataMode.ndfa, label: 'NDFA', tooltip: 'Non-deterministic Finite Automaton'),
    (mode: AutomataMode.pda,  label: 'PDA',  tooltip: 'Pushdown Automaton — labels use read,pop|push format'),
    (mode: AutomataMode.tm,   label: 'TM',   tooltip: 'Turing Machine — labels use read,write,direction format'),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Simulation Mode',
            style: GoogleFonts.courierPrime(
              fontSize: 12,
              color: theme.colorScheme.onSurface.withOpacity(0.6),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: _modes.map((entry) {
              final selected = value == entry.mode;
              return Expanded(
                child: Tooltip(
                  message: entry.tooltip,
                  waitDuration: const Duration(milliseconds: 400),
                  child: GestureDetector(
                    onTap: () => onChanged(entry.mode),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: selected
                            ? theme.colorScheme.primary
                            : theme.colorScheme.surfaceVariant,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: selected
                              ? theme.colorScheme.primary
                              : theme.colorScheme.outline.withOpacity(0.4),
                        ),
                      ),
                      child: Text(
                        entry.label,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.courierPrime(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: selected
                              ? theme.colorScheme.onPrimary
                              : theme.colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
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

  /// Current simulation mode (NDFA / PDA / TM).
  final AutomataMode automataMode;

  final bool isGuest;
  final String? accountLabel;
  final ValueChanged<bool> onShowHelpChanged;
  final ValueChanged<bool> onShowSimulatorChanged;

  /// Called when the user picks a new simulation mode.
  final ValueChanged<AutomataMode> onModeChanged;

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
    required this.automataMode,
    this.isGuest = false,
    this.accountLabel,
    required this.onShowHelpChanged,
    required this.onShowSimulatorChanged,
    required this.onModeChanged,
    required this.onBatchSimulator,
    required this.onExport,
    required this.onImport,
    required this.onExportHistory,
    required this.onReset,
    this.onSignOut,

    // ── Legacy compat: old callers may still pass showPdaMode / onShowPdaModeChanged.
    //    We accept and silently ignore them so existing call-sites compile.
    @Deprecated('Use automataMode / onModeChanged instead') bool showPdaMode = false,
    @Deprecated('Use automataMode / onModeChanged instead') ValueChanged<bool>? onShowPdaModeChanged,
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

            const Divider(),

            // ── Simulation mode radio ─────────────────────────────────────
            _ModeRadioGroup(
              value: automataMode,
              onChanged: (mode) {
                Navigator.pop(context);
                onModeChanged(mode);
              },
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