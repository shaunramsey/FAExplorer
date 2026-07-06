import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  AutomataMode  — the three simulation modes
// ─────────────────────────────────────────────────────────────────────────────

enum AutomataMode { ndfa, pda, tm, regex }

// ─────────────────────────────────────────────────────────────────────────────
//  Small building blocks shared by the drawer below.
//
//  Visual language: every actionable row gets a tinted "badge" icon so the
//  eye can scan the drawer by colour/shape instead of reading every label,
//  rows are grouped under small-caps section labels instead of one long
//  undifferentiated list cut up by plain dividers, and colours/fonts come
//  from the app's own AppThemeNotifier so the drawer matches the canvas and
//  panels instead of falling back to generic Material defaults.
// ─────────────────────────────────────────────────────────────────────────────

/// Small-caps section header, e.g. "TOOLS", "DANGER ZONE".
class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel(this.label);

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppThemeNotifier>();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
      child: Text(
        label.toUpperCase(),
        style: GoogleFonts.courierPrime(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.1,
          color: theme.textDim,
        ),
      ),
    );
  }
}

/// Small tinted rounded-square icon badge used as the leading element of
/// every drawer row, so related actions share a recognisable colour.
class _IconBadge extends StatelessWidget {
  final IconData icon;
  final Color color;
  const _IconBadge({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(9),
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: 18, color: color),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  _HoverTile — icon-badged row with tooltip description on hover/long-press,
//  rounded ink feedback, and an optional colour override for danger items.
// ─────────────────────────────────────────────────────────────────────────────

class _HoverTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color? tint;
  final Color? titleColor;
  final VoidCallback? onTap;

  const _HoverTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.tint,
    this.titleColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppThemeNotifier>();
    final color = tint ?? theme.accent;
    return Tooltip(
      message: subtitle,
      waitDuration: const Duration(milliseconds: 400),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              child: Row(
                children: [
                  _IconBadge(icon: icon, color: color),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      title,
                      style: GoogleFonts.courierPrime(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: titleColor ?? theme.textLight,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  _HoverSwitch — switch row with tooltip description, icon reflects state.
// ─────────────────────────────────────────────────────────────────────────────

class _HoverSwitch extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _HoverSwitch({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppThemeNotifier>();
    return Tooltip(
      message: subtitle,
      waitDuration: const Duration(milliseconds: 400),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          HapticFeedback.selectionClick();
          onChanged(!value);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          child: Row(
            children: [
              Icon(icon, size: 18, color: value ? theme.accent : theme.textDim),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.courierPrime(fontSize: 13.5, color: theme.textLight),
                ),
              ),
              Switch(
                value: value,
                onChanged: (v) {
                  HapticFeedback.selectionClick();
                  onChanged(v);
                },
                activeThumbColor: theme.accent,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  _DropdownSection — collapsible boxed group used for the "Docs" and
//  "Settings" sections. Keeps rarely-used rows out of the way by default
//  while still living in the same visual language as the rest of the drawer
//  (tinted icon badge, rounded bordered box, courier heading).
// ─────────────────────────────────────────────────────────────────────────────

class _DropdownSection extends StatefulWidget {
  final IconData icon;
  final Color tint;
  final String title;
  final List<Widget> children;

  const _DropdownSection({
    required this.icon,
    required this.tint,
    required this.title,
    required this.children,
  });

  @override
  State<_DropdownSection> createState() => _DropdownSectionState();
}

class _DropdownSectionState extends State<_DropdownSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppThemeNotifier>();
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      decoration: BoxDecoration(
        color: theme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.borderMid),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _expanded = !_expanded);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                child: Row(
                  children: [
                    _IconBadge(icon: widget.icon, color: widget.tint),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        widget.title,
                        style: GoogleFonts.courierPrime(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: theme.textLight,
                        ),
                      ),
                    ),
                    AnimatedRotation(
                      turns: _expanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: Icon(Icons.keyboard_arrow_down, size: 20, color: theme.textDim),
                    ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox(width: double.infinity, height: 0),
            secondChild: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Divider(height: 1, color: theme.borderMid, indent: 14, endIndent: 14),
                ...widget.children,
                const SizedBox(height: 4),
              ],
            ),
            crossFadeState: _expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 200),
            sizeCurve: Curves.easeOut,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  _ModeRadioGroup  — compact 4-way segmented control for NDFA / PDA / TM / RegEx
// ─────────────────────────────────────────────────────────────────────────────

class _ModeRadioGroup extends StatelessWidget {
  final AutomataMode value;
  final ValueChanged<AutomataMode> onChanged;

  const _ModeRadioGroup({required this.value, required this.onChanged});

  static const _modes = [
    (
      mode: AutomataMode.ndfa,
      label: 'NDFA',
      icon: Icons.hub_outlined,
      tooltip: 'Non-deterministic Finite Automaton',
    ),
    (
      mode: AutomataMode.pda,
      label: 'PDA',
      icon: Icons.layers_outlined,
      tooltip: 'Pushdown Automaton — labels use read,pop|push format',
    ),
    (
      mode: AutomataMode.tm,
      label: 'TM',
      icon: Icons.memory_outlined,
      tooltip: 'Turing Machine — labels use read,write,direction format',
    ),
    (
      mode: AutomataMode.regex,
      label: 'RegEx',
      icon: Icons.functions,
      tooltip: 'Regular Expression — convert a regex to NFA or DFA on the canvas',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppThemeNotifier>();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Row(
        children: _modes.map((entry) {
          final selected = value == entry.mode;
          return Expanded(
            child: Tooltip(
              message: entry.tooltip,
              waitDuration: const Duration(milliseconds: 400),
              child: GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  onChanged(entry.mode);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  curve: Curves.easeOut,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: selected ? theme.accent.withValues(alpha: 0.16) : theme.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: selected ? theme.accent : theme.borderMid,
                      width: selected ? 1.4 : 1,
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        entry.icon,
                        size: 16,
                        color: selected ? theme.accent : theme.textDim,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        entry.label,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.courierPrime(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: selected ? theme.accent : theme.textMid,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  _DrawerHeader — app branding + account row. Replaces the old bare
//  "Signed in / email" ListTile with something that actually identifies the
//  app and gives Guest/Signed-in state a clear visual chip.
// ─────────────────────────────────────────────────────────────────────────────

class _DrawerHeader extends StatelessWidget {
  final bool isGuest;
  final String? accountLabel;

  const _DrawerHeader({required this.isGuest, required this.accountLabel});

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppThemeNotifier>();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      decoration: BoxDecoration(
        color: theme.surface,
        border: Border(bottom: BorderSide(color: theme.borderMid)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: theme.accent.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: theme.accent.withValues(alpha: 0.4)),
                ),
                alignment: Alignment.center,
                child: Icon(Icons.account_tree_rounded, color: theme.accent, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Automata Designer',
                  style: GoogleFonts.courierPrime(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: theme.textLight,
                  ),
                ),
              ),
            ],
          ),
          if (accountLabel != null) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Icon(
                  isGuest ? Icons.person_outline : Icons.account_circle,
                  size: 16,
                  color: theme.textDim,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    accountLabel!,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.courierPrime(fontSize: 12.5, color: theme.textMid),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: (isGuest ? theme.accentGreen : theme.accent).withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: (isGuest ? theme.accentGreen : theme.accent).withValues(alpha: 0.4),
                    ),
                  ),
                  child: Text(
                    isGuest ? 'GUEST' : 'SIGNED IN',
                    style: GoogleFonts.courierPrime(
                      fontSize: 9.5,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.6,
                      color: isGuest ? theme.accentGreen : theme.accent,
                    ),
                  ),
                ),
              ],
            ),
          ],
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
  final VoidCallback onEquivalenceChecker;

  /// Called when the user taps "NFA/DFA → Regex" in the drawer.
  /// Optional — callers that haven't wired this up yet simply won't show the
  /// menu item (see [build]).
  final VoidCallback? onFaToRegex;

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
    required this.onEquivalenceChecker,
    this.onFaToRegex,
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
    final theme = context.watch<AppThemeNotifier>();

    return Drawer(
      backgroundColor: theme.bg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topRight: Radius.circular(18),
          bottomRight: Radius.circular(18),
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            _DrawerHeader(isGuest: isGuest, accountLabel: accountLabel),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(top: 4, bottom: 12),
                children: [
                  // ── Display toggles ───────────────────────────────────────
                  const _SectionLabel('Display'),
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: theme.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: theme.borderMid),
                    ),
                    child: Column(
                      children: [
                        _HoverSwitch(
                          title: 'Show Help',
                          subtitle: 'Displays controls and textbox commands.',
                          icon: Icons.help_outline,
                          value: showHelpOverlay,
                          onChanged: onShowHelpChanged,
                        ),
                        Divider(height: 1, color: theme.borderMid, indent: 14, endIndent: 14),
                        _HoverSwitch(
                          title: 'String Simulator',
                          subtitle: 'Show/hide the simulator panel.',
                          icon: Icons.science_outlined,
                          value: showSimulator,
                          onChanged: onShowSimulatorChanged,
                        ),
                      ],
                    ),
                  ),

                  // ── Simulation mode ───────────────────────────────────────
                  const _SectionLabel('Simulation Mode'),
                  _ModeRadioGroup(
                    value: automataMode,
                    onChanged: (mode) {
                      Navigator.pop(context);
                      onModeChanged(mode);
                    },
                  ),

                  // ── Tools ─────────────────────────────────────────────────
                  const _SectionLabel('Tools'),
                  _HoverTile(
                    icon: Icons.science_outlined,
                    tint: theme.accent,
                    title: 'Batch Simulator',
                    subtitle: 'Test multiple strings at once.',
                    onTap: () {
                      Navigator.pop(context);
                      onBatchSimulator();
                    },
                  ),
                  _HoverTile(
                    icon: Icons.compare_arrows,
                    tint: theme.accent,
                    title: 'Equivalence Checker',
                    subtitle:
                        'Compare two automata and determine whether they accept the same language.',
                    onTap: () {
                      Navigator.pop(context);
                      onEquivalenceChecker();
                    },
                  ),
                  if (onFaToRegex != null)
                    _HoverTile(
                      icon: Icons.functions,
                      tint: theme.accent,
                      title: 'NFA / DFA  →  Regex',
                      subtitle:
                          'Derive a regular expression from the current automaton using state elimination.',
                      onTap: () {
                        Navigator.pop(context);
                        onFaToRegex!();
                      },
                    ),

                  // ── Data ──────────────────────────────────────────────────
                  const _SectionLabel('Data'),
                  _HoverTile(
                    icon: Icons.upload_file,
                    tint: theme.accentGreen,
                    title: 'Export',
                    subtitle: 'Copy graph DSL to clipboard.',
                    onTap: () {
                      Navigator.pop(context);
                      onExport();
                    },
                  ),
                  _HoverTile(
                    icon: Icons.download,
                    tint: theme.accentGreen,
                    title: 'Import',
                    subtitle: 'Load graph from clipboard or text input.',
                    onTap: () {
                      Navigator.pop(context);
                      onImport();
                    },
                  ),
                  _HoverTile(
                    icon: Icons.history,
                    tint: theme.textDim,
                    title: 'Export History',
                    subtitle: 'View and restore saved exports.',
                    onTap: () {
                      Navigator.pop(context);
                      onExportHistory();
                    },
                  ),

                  // ── Docs ──────────────────────────────────────────────────
                  // Collapsed by default — reference material, not something
                  // reached for mid-session.
                  _DropdownSection(
                    icon: Icons.menu_book_outlined,
                    tint: theme.textDim,
                    title: 'Docs',
                    children: [
                      _HoverTile(
                        icon: Icons.info_outline,
                        tint: theme.textDim,
                        title: 'About',
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
                      Divider(height: 1, color: theme.borderMid, indent: 14, endIndent: 14),
                      _HoverTile(
                        icon: Icons.update,
                        tint: theme.textDim,
                        title: 'Changelog',
                        subtitle: "What's new in each version.",
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const MarkdownFileScreen(
                                  title: 'Changelog', assetPath: 'assets/Changelog.md'),
                            ),
                          );
                        },
                      ),
                      Divider(height: 1, color: theme.borderMid, indent: 14, endIndent: 14),
                      _HoverTile(
                        icon: Icons.tag,
                        tint: theme.textDim,
                        title: 'Version',
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
                    ],
                  ),

                  // ── Settings ──────────────────────────────────────────────
                  // Collapsed by default; more prefs can be added here later
                  // without cluttering the always-visible part of the drawer.
                  _DropdownSection(
                    icon: Icons.settings_outlined,
                    tint: theme.accent,
                    title: 'Settings',
                    children: [
                      _HoverTile(
                        icon: Icons.palette_outlined,
                        tint: theme.accent,
                        title: 'Color Settings',
                        subtitle: 'Customize the accent, background, text, and border colors.',
                        onTap: () => showAppThemeSettings(context, popRoute: true),
                      ),
                    ],
                  ),

                  // ── Account ───────────────────────────────────────────────
                  if (onSignOut != null) ...[
                    const _SectionLabel('Account'),
                    _HoverTile(
                      icon: Icons.logout,
                      tint: theme.textMid,
                      title: 'Sign out',
                      subtitle: 'Return to the login screen.',
                      onTap: () async {
                        Navigator.pop(context);
                        await onSignOut!();
                      },
                    ),
                  ],

                  // ── Reset ─────────────────────────────────────────────────
                  // Renamed from "Danger Zone" — it's one button, not a
                  // warning label; the red styling already signals caution.
                  const _SectionLabel('Reset'),
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: theme.error.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: theme.error.withValues(alpha: 0.35)),
                    ),
                    child: _HoverTile(
                      icon: Icons.delete_sweep_outlined,
                      tint: theme.error,
                      titleColor: theme.error,
                      title: 'Reset Canvas',
                      subtitle: 'Clear all nodes, transitions, and the start arrow.',
                      onTap: () {
                        Navigator.pop(context);
                        showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            backgroundColor: theme.surface,
                            title: Text(
                              'Reset canvas?',
                              style: GoogleFonts.courierPrime(
                                fontWeight: FontWeight.bold,
                                color: theme.textLight,
                              ),
                            ),
                            content: Text(
                              'This will clear all nodes, transitions, and the start arrow.',
                              style: GoogleFonts.courierPrime(color: theme.textMid),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: const Text('Cancel'),
                              ),
                              FilledButton(
                                style: FilledButton.styleFrom(backgroundColor: theme.error),
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
                  ),

                  const SizedBox(height: 8),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  MarkdownFileScreen — plain-text viewer for bundled .md docs (About,
//  Changelog, Version). Only ever opened from the drawer above, so it lives
//  here rather than as a standalone file.
// ─────────────────────────────────────────────────────────────────────────────

class MarkdownFileScreen extends StatefulWidget {
  final String title;
  final String assetPath;

  const MarkdownFileScreen({super.key, required this.title, required this.assetPath});

  @override
  State<MarkdownFileScreen> createState() => _MarkdownFileScreenState();
}

class _MarkdownFileScreenState extends State<MarkdownFileScreen> {
  String? _content;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _loadFile();
  }

  Future<void> _loadFile() async {
    try {
      final text = await rootBundle.loadString(widget.assetPath);
      if (!mounted) return;
      setState(() => _content = text);
    } catch (e) {
      if (!mounted) return;
      setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppThemeNotifier>();
    return Scaffold(
      backgroundColor: theme.bg,
      appBar: AppBar(
        backgroundColor: theme.surface,
        title: Text(
          widget.title,
          style: GoogleFonts.courierPrime(fontWeight: FontWeight.bold, color: theme.textLight),
        ),
      ),
      body: _failed
          ? Center(
              child: Text(
                'Failed to load ${widget.assetPath}',
                style: GoogleFonts.courierPrime(color: theme.error),
              ),
            )
          : _content == null
              ? Center(child: CircularProgressIndicator(color: theme.accent))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: SelectableText(
                    _content!,
                    style: GoogleFonts.courierPrime(
                      fontSize: 15,
                      height: 1.5,
                      color: theme.textLight,
                    ),
                  ),
                ),
    );
  }
}