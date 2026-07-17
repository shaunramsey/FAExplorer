import 'package:flutter/material.dart';
// Core Flutter Material widgets: Dialog, TextField, Icon, Row/Column, etc.

import 'package:google_fonts/google_fonts.dart';
// Supplies GoogleFonts.courierPrime(), the monospace/"terminal" font used
// for every DSL-adjacent label and text field in this dialog.

import 'package:provider/provider.dart';
// Gives BuildContext the `.watch<T>()` extension used below to subscribe
// to AppThemeNotifier and rebuild when the theme changes.

import '../models.dart';
// Defines NodeData — the automaton-node model this dialog reads from and
// writes back to (blackBoxDsl, blackBoxDescription, blackBoxActiveTapes).

import '../import_export.dart';
// Defines DslCodec.importFromDsl(), the parser used for live validation
// of whatever the user types into the DSL text field.

import '../widgets/automata_drawer.dart' show AutomataMode;
// Only the AutomataMode enum (ndfa / pda / tm) is pulled in via `show` —
// nothing else from automata_drawer.dart is needed here.

import 'app_theme.dart';
// Defines AppThemeNotifier, the color/typography provider consumed via
// `context.watch<AppThemeNotifier>()` in build().

// ─────────────────────────────────────────────────────────────────────────────
//  BlackBoxEditDialog  (improved)
//
//  Changes vs. the original:
//
//  1. Live DSL validation — as the user types, the dialog attempts to parse
//     the DSL and shows a green ✓ / red ✗ badge next to the "Machine DSL"
//     label, plus a one-line error message when parsing fails.  This catches
//     copy-paste mistakes before the user taps Save.
//
//  2. Automaton type badge — when the DSL is valid the detected type (NFA,
//     PDA, TM) is shown as a small pill, so the user can confirm they pasted
//     the right kind of machine.
//
//  3. Quick-insert bar — a row of small chips for common TM label tokens
//     (∅, ~, R, L, S, ~) inserted at the cursor position.  Saves typing
//     special characters on mobile.
//
//  4. Tap-to-open-tape-routing shortcut — a "Tape routing →" link at the
//     bottom opens the tape dialog inline without closing the current dialog,
//     via the [onOpenTapeRouting] callback supplied by the parent screen.
//
//  5. Cleaner layout — description and DSL fields are visually separated with
//     a divider rather than just spacing, making the two purposes unambiguous.
//
//  The public API is backward-compatible: the existing [show] helper still
//  works unchanged.  The [onOpenTapeRouting] callback is optional; when omitted
//  the tape-routing shortcut is simply not shown.
// ─────────────────────────────────────────────────────────────────────────────

class BlackBoxEditDialog extends StatefulWidget {
  // StatelessWidget-style "shell": holds only the immutable inputs the
  // dialog needs. All mutable UI state (controllers, validation result)
  // lives in _BlackBoxEditDialogState below.
  const BlackBoxEditDialog({
    super.key,
    required this.node,          // the node being edited — required, no default
    this.onOpenTapeRouting,      // optional — dialog degrades gracefully without it
  });

  final NodeData node;
  // The single source of truth for this node's black-box program. Its
  // fields are read into controllers in initState() and written back to
  // it directly (mutation, not a copy) in _save().

  /// Optional callback invoked when the user taps the "Tape routing →" link.
  /// The parent screen can use this to open [BlackBoxTapeEditDialog] and then
  /// call [setState] to reflect any changes without closing this dialog.
  final VoidCallback? onOpenTapeRouting;
  // Nullable — the "Tape routing" button (see build(), line ~230) only
  // renders `if (widget.onOpenTapeRouting != null)`.

  /// Convenience helper — backward-compatible with the original signature.
  static Future<bool?> show(
    BuildContext context, {
    required NodeData node,
    VoidCallback? onOpenTapeRouting,
  }) {
    return showDialog<bool>(
      // Generic <bool> matches what Navigator.pop(...) is called with in
      // _save() (pop(true)) and the Cancel button (pop(false)); dismissing
      // by tapping outside the dialog resolves this Future to null instead.
      context: context,
      builder: (_) => BlackBoxEditDialog(
        node: node,
        onOpenTapeRouting: onOpenTapeRouting,
      ),
    );
  }

  @override
  State<BlackBoxEditDialog> createState() => _BlackBoxEditDialogState();
}

// ── Validation result ─────────────────────────────────────────────────────────

enum _DslStatus { empty, valid, invalid }
// Three-way status rather than a plain bool: "empty" is deliberately
// distinguished from "invalid" so an untouched/cleared field doesn't show
// a red error badge — see _ValidationBadge.build() below, which renders
// nothing for `empty`.

class _DslValidation {
  const _DslValidation(this.status, {this.type, this.error});
  // `type` and `error` are mutually exclusive in practice: `type` is set
  // only on success, `error` only on failure — but nothing enforces that
  // at the type level (both are just nullable fields on the same class).

  final _DslStatus status;
  final String? type;   // e.g. 'NFA', 'PDA', 'TM'  — populated only when status == valid
  final String? error;  // human-readable parse error — populated only when status == invalid
}

_DslValidation _validate(String raw) {
  // Free function (not a method) — has no dependency on widget/state, so
  // it's kept top-level and reusable/testable independent of the widget.
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return const _DslValidation(_DslStatus.empty);
  // Whitespace-only input is treated as "empty", not "invalid" — avoids
  // flashing a red error the instant the field is focused/cleared.
  try {
    final graph = DslCodec.importFromDsl(trimmed);
    // The actual parse attempt. Throws on malformed DSL — caught below.

    // Map the detected mode to a human-readable label.
    const modeLabel = {
      AutomataMode.ndfa: 'NFA / DFA',
      AutomataMode.pda:  'PDA',
      AutomataMode.tm:   'TM',
    };
    final typeLabel = modeLabel[graph.automataMode] ?? graph.automataMode.name.toUpperCase();
    // Falls back to the raw enum name (uppercased) if a new AutomataMode
    // value is ever added without updating modeLabel — avoids a null
    // lookup crashing the whole validation path.
    return _DslValidation(_DslStatus.valid, type: typeLabel);
  } catch (e) {
    // Surface only the most useful part of a parse error.
    final msg = e.toString().replaceFirst('Exception: ', '').replaceFirst('FormatException: ', '');
    // Strips the generic Dart exception-class prefixes so the user sees
    // just the parser's own message, not "Exception: FormatException: ...".
    return _DslValidation(_DslStatus.invalid, error: msg.length > 120 ? '${msg.substring(0, 120)}…' : msg);
    // Truncates to 120 chars + ellipsis so a very long parser message
    // can't blow out the dialog's fixed-width layout.
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _BlackBoxEditDialogState extends State<BlackBoxEditDialog> {
  late final TextEditingController _dslController;
  late final TextEditingController _descController;
  late final TextEditingController _tapesController;
  // Three independent controllers, one per editable field — all `late
  // final` because they're constructed in initState() using `widget.node`
  // (not available at field-initializer time) but never reassigned after.

  late _DslValidation _validation;
  // Cached validation result for the *current* text in _dslController.
  // Recomputed by _onDslChanged() on every keystroke rather than inline
  // in build(), so build() can stay a pure function of this field.

  // Focus node for the DSL field, so we can insert text at the cursor.
  final FocusNode _dslFocus = FocusNode();
  // Not `late` — constructed eagerly since it takes no constructor args.

  @override
  void initState() {
    super.initState();
    _dslController = TextEditingController(text: widget.node.blackBoxDsl);
    _descController = TextEditingController(text: widget.node.blackBoxDescription);
    _tapesController = TextEditingController(
      text: widget.node.blackBoxActiveTapes.join(','),
      // int list -> comma string, e.g. [2, 3] -> "2,3" — inverse of
      // _parseActiveTapes() below, which parses this same format back.
    );
    _validation = _validate(_dslController.text);
    // Compute the initial badge/error state immediately, so if the node
    // already has (possibly stale/invalid) DSL, the dialog opens already
    // showing the correct ✓/✗ rather than waiting for the first keystroke.
    _dslController.addListener(_onDslChanged);
    // Re-validate on every change to the DSL field. Note: no listeners are
    // attached to _descController / _tapesController — only the DSL field
    // needs live feedback; description/tapes are free-form/lenient.
  }

  @override
  void dispose() {
    _dslController.removeListener(_onDslChanged);
    // Explicitly removed before dispose() — technically redundant since
    // disposing the controller drops its listeners anyway, but it's
    // defensive/explicit and costs nothing.
    _dslController.dispose();
    _descController.dispose();
    _tapesController.dispose();
    _dslFocus.dispose();
    super.dispose();
    // super.dispose() called last, per Flutter convention — all local
    // cleanup happens before the framework tears down the State object.
  }

  void _onDslChanged() {
    final v = _validate(_dslController.text);
    if (v.status != _validation.status ||
        v.type != _validation.type ||
        v.error != _validation.error) {
      // Field-by-field equality check (not `v != _validation`, since
      // _DslValidation doesn't override == / hashCode) — avoids calling
      // setState() on every keystroke when the *result* hasn't actually
      // changed (e.g. typing more characters into an already-valid DSL
      // where `type` stays the same), which would otherwise rebuild the
      // whole dialog on every single character.
      setState(() => _validation = v);
    }
  }

  void _save() {
    widget.node.blackBoxDsl = _dslController.text.trim();
    widget.node.blackBoxDescription = _descController.text.trim();
    widget.node.blackBoxActiveTapes = _parseActiveTapes(_tapesController.text);
    // Mutates the NodeData passed in by the caller directly — there is no
    // local "draft" copy that gets swapped in atomically; if the user
    // cancels, whatever was typed simply isn't read back into `node`.
    Navigator.of(context).pop(true);
    // Resolves the Future<bool?> from BlackBoxEditDialog.show(...) with
    // `true`, signalling "saved" to the caller.
  }

  void _clear() {
    setState(() {
      _dslController.clear();
      _descController.clear();
      _tapesController.clear();
      // .clear() on a TextEditingController both empties `.text` and
      // resets the selection — triggers _dslController's listener
      // (_onDslChanged), which will itself call setState() again with the
      // new "empty" validation status. The setState() wrapping this block
      // is what makes the "Clear" button (which is conditionally shown)
      // disappear immediately once all three fields are empty.
    });
  }

  /// Parses the comma-separated "Active tapes" field (e.g. `3` or `2,3`)
  /// into a list of 1-based tape indices, dropping anything malformed.
  /// A blank field yields an empty list, which preserves the default
  /// positional triple → tape mapping (see [NodeData.blackBoxActiveTapes]).
  static List<int> _parseActiveTapes(String raw) {
    // `static` — doesn't touch instance state, so it's callable/testable
    // without a live _BlackBoxEditDialogState.
    if (raw.trim().isEmpty) return <int>[];
    return raw
        .split(',')                              // "2, 3" -> ["2", " 3"]
        .map((t) => int.tryParse(t.trim()))       // " 3" -> 3 ; "abc" -> null
        .whereType<int>()                         // drops the nulls from failed parses
        .where((t) => t >= 1)                     // drops non-positive/zero indices (tapes are 1-based)
        .toList();
  }

  /// Insert [text] at the current cursor position in the DSL field.
  void _insertToken(String text) {
    _dslFocus.requestFocus();
    // Ensures the DSL field visibly has focus/cursor after a quick-insert
    // chip tap, even if the user had tapped away from the field (e.g. to
    // hit a chip that lost the field's focus).
    final ctrl = _dslController;
    final sel = ctrl.selection;
    final current = ctrl.text;
    final start = sel.start < 0 ? current.length : sel.start;
    final end = sel.end < 0 ? current.length : sel.end;
    // TextSelection can be "invalid" (start/end == -1) if the field has
    // never been focused/had a selection set — in that case both start
    // and end fall back to the end of the current text, so the token is
    // appended rather than crashing on a negative-index replaceRange.
    final newText = current.replaceRange(start, end, text);
    // If start == end (no selection, just a cursor), this is a pure
    // insertion. If start != end (a range is selected), the selected text
    // is replaced by `text` — same behavior as typing over a selection.
    ctrl.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: start + text.length),
      // Places the cursor immediately after the inserted token so the
      // user can keep typing (or tap another chip) without having to
      // manually reposition the cursor.
    );
  }

  // ── build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppThemeNotifier>();
    // `watch` (not `read`) — this widget rebuilds whenever the app theme
    // changes (e.g. light/dark toggle) while this dialog is open.
    final nodeName = widget.node.label.trim().isEmpty
        ? 'this black box'
        : '"${widget.node.label.trim()}"';
    // Falls back to a generic phrase when the node has no user-given
    // label, so the subtitle text below never reads as `""`.

    return Dialog(
      backgroundColor: theme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: theme.borderMid),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        // Caps the dialog's width on wide/desktop screens; on narrow
        // screens Dialog's own default insetPadding still shrinks it
        // further, so this is only an upper bound, not a fixed width.
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            // Column sizes to its children's height rather than expanding
            // to fill the Dialog — necessary since Dialog itself doesn't
            // impose a height, only the maxWidth constraint above.
            crossAxisAlignment: CrossAxisAlignment.start,
            // Left-aligns children by default; the Row-based header/action
            // bars override this locally via mainAxisAlignment on the Row.
            children: [
              // ── Title ────────────────────────────────────────────────
              Row(
                children: [
                  Icon(Icons.memory, size: 18, color: theme.accent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Black Box Program',
                      style: GoogleFonts.courierPrime(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: theme.accent,
                      ),
                    ),
                  ),
                  // Expanded pushes the optional "Tape routing" button (if
                  // present) to the far right of the title row.

                  // Tape routing shortcut
                  if (widget.onOpenTapeRouting != null)
                    TextButton.icon(
                      onPressed: widget.onOpenTapeRouting,
                      // Note: this callback is invoked directly — this
                      // dialog itself is NOT popped/closed when tapped
                      // (per the file-header doc comment: the parent is
                      // expected to open BlackBoxTapeEditDialog *on top of*
                      // or alongside this one, not replace it).
                      icon: Icon(Icons.settings_input_component,
                          size: 13, color: theme.textDim),
                      label: Text(
                        'Tape routing',
                        style: GoogleFonts.courierPrime(
                            fontSize: 11, color: theme.textDim),
                      ),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        minimumSize: const Size(0, 28),
                        // Shrinks the button's default hit-target height
                        // (Material default is 36-48px) so it fits neatly
                        // inline with the 18px title icon/16px title text.
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Edit the inner machine $nodeName runs against the tape it '
                'reads and writes.',
                style: TextStyle(fontSize: 12, color: theme.textMid, height: 1.4),
              ),

              const SizedBox(height: 16),

              // ── Description ──────────────────────────────────────────
              _FieldLabel(text: 'Description', theme: theme),
              const SizedBox(height: 6),
              TextField(
                controller: _descController,
                style: GoogleFonts.courierPrime(fontSize: 13, color: theme.textLight),
                maxLines: 2,
                minLines: 1,
                // minLines/maxLines both set (rather than just maxLines)
                // so the field can grow from 1 to 2 lines as the user
                // types, instead of always reserving 2 lines of height.
                decoration: _inputDecoration(
                  theme: theme,
                  hint: 'e.g. "Increments a binary number by 1"',
                ),
              ),

              const SizedBox(height: 12),

              // ── Active tapes ─────────────────────────────────────────
              _FieldLabel(text: 'Active tapes (optional)', theme: theme),
              const SizedBox(height: 6),
              TextField(
                controller: _tapesController,
                style: GoogleFonts.courierPrime(fontSize: 13, color: theme.textLight),
                decoration: _inputDecoration(
                  theme: theme,
                  hint: 'e.g. 3  or  2,3 — leave blank for default',
                ),
                // Single-line by default (no minLines/maxLines override) —
                // this field only ever holds a short comma-separated list.
              ),
              const SizedBox(height: 4),
              Text(
                'Which tapes the outgoing-line RWD triples address, in order. '
                'Leave blank for the default (triple 1 → tape 1, triple 2 → '
                'tape 2, …); tapes not listed are left untouched.',
                style: TextStyle(fontSize: 11, color: theme.textDim, height: 1.3),
              ),

              const SizedBox(height: 14),
              Divider(height: 1, color: theme.borderMid),
              // Visually separates the "metadata" fields above (description,
              // active tapes) from the "program" fields below (DSL) — see
              // file-header comment #5.
              const SizedBox(height: 14),

              // ── DSL field header ─────────────────────────────────────
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _FieldLabel(text: 'Machine DSL', theme: theme),
                  const SizedBox(width: 8),
                  _ValidationBadge(validation: _validation, theme: theme),
                  // Live ✓/✗/blank badge — rebuilds whenever _validation
                  // changes via _onDslChanged()'s setState() call.
                  const Spacer(),
                  // Pushes "Clear" (if shown) to the far right, mirroring
                  // the title row's Expanded-then-trailing-button pattern.
                  if (_dslController.text.trim().isNotEmpty ||
                      _descController.text.trim().isNotEmpty ||
                      _tapesController.text.trim().isNotEmpty)
                    // "Clear" only appears once *any* of the three fields
                    // has content — reading `.text` directly here (rather
                    // than from a cached/state field) works because build()
                    // re-runs on every setState(), including the ones fired
                    // by _onDslChanged() and _clear() itself.
                    TextButton.icon(
                      onPressed: _clear,
                      icon: Icon(Icons.delete_outline, size: 13, color: theme.textDim),
                      label: Text(
                        'Clear',
                        style: GoogleFonts.courierPrime(
                            fontSize: 11, color: theme.textDim),
                      ),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        minimumSize: const Size(0, 28),
                      ),
                    ),
                ],
              ),

              // Validation error message
              if (_validation.status == _DslStatus.invalid &&
                  _validation.error != null) ...[
                // Both checks are technically redundant given _validate()'s
                // implementation (error is only ever non-null when status
                // is invalid), but the null-check keeps the `!` below safe
                // even if that invariant is ever loosened.
                const SizedBox(height: 4),
                Text(
                  _validation.error!,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFFFF5252),
                    // Same red used for the ✗ icon in _ValidationBadge and
                    // for the DSL field's border below — kept in sync by
                    // being the same literal color in all three spots.
                    height: 1.3,
                  ),
                ),
              ],

              const SizedBox(height: 6),

              // DSL text area
              Container(
                decoration: BoxDecoration(
                  color: theme.bg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _validation.status == _DslStatus.invalid
                        ? const Color(0xFFFF5252).withValues(alpha: 0.6)
                        : _validation.status == _DslStatus.valid
                            ? theme.accentGreen.withValues(alpha: 0.4)
                            : theme.borderMid,
                    // Three-way border color, mirroring _validation.status:
                    // red (invalid) / green (valid) / neutral (empty) —
                    // gives an at-a-glance status without needing to read
                    // the badge or error text.
                  ),
                ),
                child: TextField(
                  controller: _dslController,
                  focusNode: _dslFocus,
                  // Wired to the same FocusNode that _insertToken() calls
                  // .requestFocus() on, so quick-insert chips can restore
                  // focus/cursor to this exact field.
                  style: GoogleFonts.courierPrime(
                      fontSize: 12, color: theme.textLight),
                  maxLines: 8,
                  minLines: 6,
                  // Fixed-ish multi-line area (6-8 lines) sized for typical
                  // DSL program lengths — unlike the Description field,
                  // this doesn't need to start at 1 line since DSL input
                  // is expected to be substantial.
                  decoration: InputDecoration(
                    isCollapsed: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    // All internal TextField borders are suppressed because
                    // the surrounding Container (above) already draws the
                    // status-colored border — avoids a doubled/clashing
                    // border effect.
                    hintText:
                        'No machine assigned — paste a DSL definition exported\n'
                        'from another graph, or write one directly.',
                    hintStyle: TextStyle(
                      fontSize: 12,
                      color: theme.textDim.withValues(alpha: 0.6),
                    ),
                    contentPadding: const EdgeInsets.all(10),
                  ),
                ),
              ),

              const SizedBox(height: 8),

              // ── Quick-insert bar ─────────────────────────────────────
              _QuickInsertBar(onInsert: _insertToken, theme: theme),
              // Passes _insertToken directly as the callback — each chip
              // tap ultimately calls back into this State's DSL controller.

              const SizedBox(height: 10),

              // ── Info box ─────────────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.accent.withValues(alpha: 0.07),
                  // Very low-alpha tint of the accent color — a subtle
                  // "info" background rather than a bold callout.
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: theme.accent.withValues(alpha: 0.25)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  // `start` (not `center`) so the info icon aligns with the
                  // *first line* of the (possibly multi-line) text next to
                  // it, rather than being vertically centered against the
                  // whole paragraph.
                  children: [
                    Icon(Icons.info_outline, size: 14, color: theme.accent),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Tape routing is encoded in the outgoing line labels '
                        'as RWD triples per tape — e.g. aXRa1R means '
                        '"tape 1: read a, write X, Right; tape 2: read a, '
                        'write 1, Right". With "Active tapes" set (e.g. 3), a '
                        'label of just 10R addresses tape 3 alone — no '
                        'padding for the other tapes needed. No separate '
                        'tape-routing dialog needed.',
                        style: TextStyle(
                            fontSize: 11, color: theme.textMid, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // ── Actions ──────────────────────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                // Right-aligns Cancel/Save — the one place in this dialog
                // that overrides the Column's default start-alignment.
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    // Explicit `false` result — distinguishable by the
                    // caller from the `null` you'd get by dismissing the
                    // dialog (e.g. tapping the scrim outside it).
                    child: Text('Cancel',
                        style: TextStyle(color: theme.textDim)),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    // Disable Save when the DSL is non-empty but invalid.
                    onPressed: _validation.status == _DslStatus.invalid
                        ? null
                        : _save,
                    // Note: an *empty* DSL is still saveable (status ==
                    // empty, not invalid) — a black box can apparently be
                    // saved with no program assigned yet; only a DSL that
                    // was typed but fails to parse blocks Save.
                    style: FilledButton.styleFrom(
                      backgroundColor: theme.accent,
                      disabledBackgroundColor:
                          theme.accent.withValues(alpha: 0.35),
                      // Dims the accent color rather than switching to a
                      // generic grey, so the disabled state still reads as
                      // "this button, just inactive" rather than a
                      // different button entirely.
                    ),
                    child: const Text('Save'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration({
    required AppThemeNotifier theme,
    required String hint,
  }) {
    // Shared decoration factory for the Description and Active-tapes
    // fields (the DSL field builds its own InputDecoration inline above,
    // since it needs isCollapsed/no-border behavior this helper doesn't
    // provide).
    return InputDecoration(
      isDense: true,
      // Tightens vertical padding Material normally adds — keeps these
      // single/double-line fields compact within the dialog.
      hintText: hint,
      hintStyle: TextStyle(color: theme.textDim.withValues(alpha: 0.6)),
      filled: true,
      fillColor: theme.bg,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: theme.borderMid),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: theme.borderMid),
      ),
      // `border` and `enabledBorder` are set to the same style — Material
      // uses `border` as a fallback for any state without a more specific
      // override (like `focusedBorder` below), so both are specified
      // explicitly to guarantee the unfocused look is theme.borderMid in
      // every state except focused.
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: theme.accent),
        // Only the border color changes on focus (borderMid -> accent);
        // radius and width stay constant, so focusing doesn't shift the
        // field's layout.
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  _ValidationBadge — green ✓ / red ✗ / grey (empty) chip
// ─────────────────────────────────────────────────────────────────────────────

class _ValidationBadge extends StatelessWidget {
  const _ValidationBadge({required this.validation, required this.theme});
  // Pure function of its constructor params — no internal state; the
  // parent State rebuilds it wholesale whenever _validation changes.

  final _DslValidation validation;
  final AppThemeNotifier theme;

  @override
  Widget build(BuildContext context) {
    switch (validation.status) {
      case _DslStatus.empty:
        return const SizedBox.shrink();
        // Renders literally nothing (zero-size box) — matches the doc
        // comment's "grey (empty)" description only loosely: in practice
        // "empty" is invisible, not grey.
      case _DslStatus.valid:
        return Row(
          mainAxisSize: MainAxisSize.min,
          // Sizes to content, not to the available width — necessary
          // since this Row sits inline inside another Row (the DSL field
          // header) alongside a label, Spacer, and Clear button.
          children: [
            const Icon(Icons.check_circle_outline,
                size: 13, color: Color(0xFF1FD99A)),
            const SizedBox(width: 4),
            if (validation.type != null)
              // Defensive null-check: _validate() always sets `type` when
              // status is `valid`, but the pill is still guarded in case
              // that invariant is ever broken.
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: const Color(0xFF1FD99A).withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                      color: const Color(0xFF1FD99A).withValues(alpha: 0.4)),
                ),
                child: Text(
                  validation.type!,
                  // e.g. "NFA / DFA", "PDA", "TM" — see modeLabel map in
                  // _validate() above.
                  style: GoogleFonts.courierPrime(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF1FD99A),
                    // Same green (0xFF1FD99A) used for the check icon,
                    // pill fill, and pill border/text — one literal color
                    // repeated 4x in this branch rather than a shared
                    // constant.
                  ),
                ),
              ),
          ],
        );
      case _DslStatus.invalid:
        return const Icon(Icons.error_outline,
            size: 13, color: Color(0xFFFF5252));
        // Just the icon, no pill/type label — an invalid DSL has no
        // detected type to show, so the error message (rendered
        // separately, below the field-header Row in build()) carries the
        // detail instead.
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  _QuickInsertBar — one-tap insertion of common TM symbols
// ─────────────────────────────────────────────────────────────────────────────

class _QuickInsertBar extends StatelessWidget {
  const _QuickInsertBar({
    required this.onInsert,
    required this.theme,
  });

  final ValueChanged<String> onInsert;
  // Callback signature matches _insertToken(String) exactly, so the
  // parent just passes that method reference directly (no wrapping
  // closure needed).
  final AppThemeNotifier theme;

  static const _tokens = [
    ('∅', 'blank'),
    ('~',  '~-jump'),
    ('R',  'right'),
    ('L',  'left'),
    ('S',  'stay'),
    ('~',  'tilda'),
    // Note: '~' appears twice in this list (as '~-jump' and 'tilda') —
    // both entries render identical chips with different tooltips, which
    // is likely an unintentional duplicate rather than two distinct tokens.
    ('1:', 'tape 1'),
    ('2:', 'tape 2'),
    ('b1', 'cross-write'),
    ('b2', 'parallel'),
  ];
  // List of (token, tooltip) record pairs — Dart 3 record syntax. `token`
  // is what gets inserted into the DSL field; `tooltip` is only shown on
  // long-press/hover via the Tooltip widget below, never rendered as
  // visible text on the chip itself.

  @override
  Widget build(BuildContext context) {
    return Wrap(
      // Wrap (not Row) so the chips flow onto a second line on narrow
      // dialog widths instead of overflowing horizontally.
      spacing: 5,
      runSpacing: 5,
      // `spacing` = horizontal gap between chips on the same line;
      // `runSpacing` = vertical gap between wrapped lines.
      children: [
        Text(
          'Insert:',
          style: GoogleFonts.courierPrime(
              fontSize: 10, color: theme.textDim),
        ),
        // The "Insert:" label is itself just another Wrap child — it can
        // end up on its own line if the first chip doesn't fit next to it,
        // since Wrap doesn't treat it specially.
        for (final (token, label) in _tokens)
          // Dart pattern-matching destructure of each (token, label)
          // record directly in the for-loop header.
          Tooltip(
            message: label,
            child: GestureDetector(
              onTap: () => onInsert(token),
              // GestureDetector (not a Material button) — chips have no
              // built-in ripple/press feedback, just an opaque tap target.
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: theme.bg,
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(color: theme.borderMid),
                ),
                child: Text(
                  token,
                  style: GoogleFonts.courierPrime(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: theme.textLight,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Small helpers
// ─────────────────────────────────────────────────────────────────────────────

class _FieldLabel extends StatelessWidget {
  const _FieldLabel({required this.text, required this.theme});
  // Tiny reusable label widget — used for "Description", "Active tapes
  // (optional)", and "Machine DSL" headers, so their styling (font, size,
  // weight, color) can't drift out of sync between the three fields.

  final String text;
  final AppThemeNotifier theme;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: GoogleFonts.courierPrime(
        fontSize: 11,
        fontWeight: FontWeight.bold,
        color: theme.textDim,
      ),
    );
  }
}