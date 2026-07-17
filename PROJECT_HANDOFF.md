# Automata Designer — Project Handoff Guide

This document explains what every meaningful file in the project does, how the pieces fit together, and where to look when you need to change something. It is written for a future developer taking over maintenance or feature work on **Automata Designer** (Flutter package name: `automata_designer`).

**Live web build:** [https://shaunramsey.github.io/FAExplorer](https://shaunramsey.github.io/FAExplorer)

**Attribution:** See `About.md` — Washington College, Shaun D. Ramsey PhD, with student contributors.

---

## Table of Contents

1. [What This App Does](#what-this-app-does)
2. [Getting Started](#getting-started)
3. [Architecture Overview](#architecture-overview)
4. [Flutter & Dart APIs Reference](#flutter--dart-apis-reference)
5. [Key Concepts](#key-concepts)
6. [Application Modes](#application-modes)
7. [Source Files (`lib/`)](#source-files-lib)
8. [Deep Dives — Important Files](#deep-dives--important-files)
9. [Tests (`test/`)](#tests-test)
10. [Assets (`assets/`)](#assets-assets)
11. [Root Configuration & Docs](#root-configuration--docs)
12. [Platform Folders (Brief)](#platform-folders-brief)
13. [Common Maintenance Tasks](#common-maintenance-tasks)
14. [Where to Start for Common Changes](#where-to-start-for-common-changes)

---

## What This App Does

Automata Designer is a cross-platform Flutter application for **Theory of Computation** education. Users can:

- **Design** finite automata (DFA/NFA), pushdown automata (PDA), and Turing machines (TM) on an interactive canvas
- **Simulate** input strings step-by-step and see which states/transitions are active
- **Import/export** machines in a custom DSL, SVG (with embedded data), and LaTeX/TikZ
- **Play puzzle levels** (Game Mode) where they must build a machine equivalent to a target
- **Practice** with procedurally generated challenges (Study Mode) for regex↔DFA, PDA, and TM problems

Authentication is optional: **Guest mode** stores everything locally; signed-in users can sync workspace data to Firebase Firestore.

---

## Getting Started

### Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) compatible with Dart `^3.9.0` (see `pubspec.yaml`)
- For Firebase sign-in/cloud sync: follow `FIREBASE_SETUP.md`

### Run the app

```bash
cd FAExplorer
flutter pub get
flutter run              # default device
flutter run -d chrome    # web
```

VS Code launch configs are in `.vscode/launch.json` (standard Flutter + web-server).

### Run tests

```bash
flutter test
```

---

## Architecture Overview

```
main.dart
  └── AppGate (router after auth)
        ├── LoginScreen / ModeSelectScreen
        ├── AutomataScreen        (Sandbox — free-form editor)
        ├── LevelSelectScreen     (Game Mode — level map)
        │     └── GamePuzzleScreen / TutorialScreen
        └── StudyModeScreen       (Study Mode — practice challenges)

Shared core:
  models.dart          — graph data (nodes, lines, geometry)
  simulator.dart       — DFA/NFA, PDA, TM simulation engines
  regex_engine.dart    — regex → NFA → DFA conversion
  import_export.dart   — DSL, SVG, LaTeX import/export
  persistence.dart     — auth + local/cloud session storage
  widgets/             — canvas rendering, drawer, panels, theme
  dialogs/             — equivalence checking, batch sim, import/export UI
```

**State management:** [Provider](https://pub.dev/packages/provider) for theming (`AppThemeNotifier`). Most screen state is held in `StatefulWidget` classes. Persistence goes through `AutomataSessionStore` (sandbox workspace) and `GameProgressStore` (level completion).

**Data flow for the canvas:** User gestures in `AutomataScreen` mutate [`Map<String, NodeData>`](https://api.flutter.dev/flutter/dart-core/Map-class.html) and `Map<String, LineData>`. Simulators (`AutomataSimulator`, `PdaSimulator`, `TmSimulator`) read those maps and produce step histories. `DslCodec` serializes/deserializes the same structures for save/load.

---

## Flutter & Dart APIs Reference

This project is a standard Flutter app. The tables below link Flutter/Dart APIs that appear repeatedly in the codebase to their official documentation. When you are debugging UI behavior, start with the relevant link here before searching the web.

### State, lifecycle, and memory

| API | Used for in this project | Documentation |
|-----|--------------------------|---------------|
| `StatefulWidget` / `State` | Every major screen (`AutomataScreen`, `LoginScreen`, `StudyModeScreen`, …) | [State.dispose](https://api.flutter.dev/flutter/widgets/State/dispose.html) |
| `TextEditingController` | Simulation input, transition label textboxes, login fields, batch simulator, black-box DSL editor | [TextEditingController](https://api.flutter.dev/flutter/widgets/TextEditingController-class.html) |
| `FocusNode` / `FocusScope` | Canvas keyboard shortcuts; inline label editing on nodes and lines | [Focus](https://api.flutter.dev/flutter/widgets/Focus-class.html) |
| `WidgetsBindingObserver` | Flush debounced autosave when app goes to background (`AutomataScreen`) | [AppLifecycleState](https://api.flutter.dev/flutter/dart-ui/AppLifecycleState.html) |
| `Provider` / `ChangeNotifier` | Theme propagation via `AppThemeNotifier` | [provider package](https://pub.dev/packages/provider) |

**Important lifecycle pattern:** Any `State` that creates a `TextEditingController`, `FocusNode`, `AnimationController`, or `Timer` must dispose them in [`dispose()`](https://api.flutter.dev/flutter/widgets/State/dispose.html). Examples: `login_screen.dart` (email/password controllers), `graph_widgets.dart` (label controllers on every line/node), `automata_screen.dart` (sim input + tape controllers + debounce timer). Forgetting disposal causes memory leaks and "setState() called after dispose()" errors.

### Input, gestures, and keyboard

| API | Used for in this project | Documentation |
|-----|--------------------------|---------------|
| `GestureDetector` | Canvas pan, tap, drag for nodes/lines/start arrow | [Gestures cookbook](https://docs.flutter.dev/ui/interactivity/gestures) |
| `KeyboardListener` | Shift toggles line mode on canvas (`AutomataScreen`, `AutomataCanvasEmbed`, `GamePuzzleScreen`) | [KeyboardListener](https://api.flutter.dev/flutter/widgets/KeyboardListener-class.html) |
| `LogicalKeyboardKey` | Detecting Shift, Enter, Backspace | [LogicalKeyboardKey](https://api.flutter.dev/flutter/services/LogicalKeyboardKey-class.html) |
| `InkWell` | Tappable drawer rows, mode-select cards, panel buttons | [InkWell](https://api.flutter.dev/flutter/material/InkWell-class.html) |
| `Switch` | Drawer toggles (simulator visibility, help overlay, …) via `_HoverSwitch` | [Switch](https://api.flutter.dev/flutter/material/Switch-class.html) |

**Why Shift instead of Alt:** Alt+click causes browser focus issues on web builds. Line mode is toggled with Shift (keyboard) or the FAB (touch/mouse). See the gesture stack in `AutomataScreen.build()`: `KeyboardListener` wraps a `GestureDetector` wraps the canvas `Stack`.

### Layout and lists

| API | Used for in this project | Documentation |
|-----|--------------------------|---------------|
| `Scaffold` / `Drawer` | Main screen shells and hamburger menu | [Scaffold](https://api.flutter.dev/flutter/material/Scaffold-class.html) |
| `ListView` / `ListView.separated` | Drawer menu, export history, TM tape history, batch results | [ListView](https://api.flutter.dev/flutter/widgets/ListView-class.html) |
| `ListTile` | Some drawer rows and settings entries | [ListTile](https://api.flutter.dev/flutter/material/ListTile-class.html) |
| `Expanded` / `Flexible` | Splitting canvas vs side panels; form layouts | [Expanded](https://api.flutter.dev/flutter/widgets/Expanded-class.html) |
| `ConstrainedBox` / `SizedBox` | Fixed panel widths, level-map card sizing | [ConstrainedBox](https://api.flutter.dev/flutter/widgets/ConstrainedBox-class.html) |
| `BoxDecoration` | Themed cards, panels, node backgrounds, level-select glow | [BoxDecoration](https://api.flutter.dev/flutter/painting/BoxDecoration-class.html) |
| `Divider` | Separators in drawer and settings sheets | [Divider](https://api.flutter.dev/flutter/material/Divider-class.html) |

### Navigation, dialogs, and feedback

| API | Used for in this project | Documentation |
|-----|--------------------------|---------------|
| `Navigator` | Closing dialogs, pushing tutorial/study screens | [Navigator](https://api.flutter.dev/flutter/widgets/Navigator-class.html) |
| `showDialog` / `Dialog` | Import/export, black-box editor, batch simulator, equivalence | [Dialog](https://api.flutter.dev/flutter/material/Dialog-class.html) |
| `ScaffoldMessenger` / `SnackBar` | Copy-to-clipboard confirmations, import errors, cheat-code feedback | [Snackbars cookbook](https://docs.flutter.dev/cookbook/design/snackbars) · [ScaffoldMessenger](https://api.flutter.dev/flutter/material/ScaffoldMessenger-class.html) |
| `SelectableText` | Export output, changelog/about viewer, FA→regex results (user can copy) | [SelectableText](https://api.flutter.dev/flutter/material/SelectableText-class.html) |

### Visual effects and icons

| API | Used for in this project | Documentation |
|-----|--------------------------|---------------|
| `Icons` | FABs, drawer entries, mode-select cards | [Icons](https://api.flutter.dev/flutter/material/Icons-class.html) |
| `AnimatedRotation` | Drawer section chevrons expand/collapse | [AnimatedRotation](https://api.flutter.dev/flutter/widgets/AnimatedRotation-class.html) |
| `CustomPainter` | Transition lines, nodes, rubber-band preview, login grid background | [CustomPainter](https://api.flutter.dev/flutter/rendering/CustomPainter-class.html) |

### Third-party packages (see also [Dependency Summary](#dependency-summary))

| Package | Used for | Documentation |
|---------|----------|---------------|
| `file_picker` | Import `.txt` batch string files in batch simulator dialog | [file_picker on pub.dev](https://pub.dev/packages/file_picker) |
| `google_fonts` | Orbitron + Source Code Pro typography | [google_fonts on pub.dev](https://pub.dev/packages/google_fonts) |
| `shared_preferences` | Guest workspace, theme, game progress | [shared_preferences on pub.dev](https://pub.dev/packages/shared_preferences) |

### Material 3 button note

Some older Flutter button APIs were deprecated. If you add new buttons, follow current Material guidance: [Flutter breaking changes — buttons](https://docs.flutter.dev/release/breaking-changes/buttons).

---

## Key Concepts

### Automaton modes (`AutomataMode`)

Defined in `lib/widgets/automata_drawer.dart`:

| Mode | Purpose |
|------|---------|
| **NDFA** | Non-deterministic / deterministic finite automata |
| **PDA** | Pushdown automata with stack operations |
| **TM** | Multi-tape Turing machines with read/write/move |
| **Regex** | Regex panel for converting expressions to automata |

Switching modes changes which simulator runs, which transition label syntax is valid, and which special node types are available (e.g. halt states, black boxes).

### Epsilon transitions

The app uses **`~`** (tilde) for epsilon, not the Greek letter δ or empty string. This is consistent across DSL import/export, simulators, and study mode.

### Transition label syntax (high level)

- **DFA/NFA:** Comma- or newline-separated alternatives on one edge (e.g. `a,b` or `a\nb`). Wildcard `.` matches any single symbol. Negated wildcard `.-abc` matches anything except `a`, `b`, or `c`.
- **PDA:** Labels encode input symbol, stack pop, and stack push (see `HelpOverlay` and simulator code).
- **TM:** Labels use tape triples like `1R` (write 1, move Right) per tape; multi-tape machines pad unused tapes with `~`.

### Special tokens in labels

Users can type `[[TOKEN]]` in labels to insert Unicode symbols (Greek letters, arrows, etc.). See `lib/token_replacements.dart` for the full map. Example: `[[DELTA]]` → δ.

### Graph model

- **Nodes** (`NodeData`): states on the canvas — normal accept, halt-accept, halt-reject, or TM black-box sub-machines
- **Lines** (`LineData`): directed transitions with curved geometry, editable label textboxes, and hit-testing
- **Start arrow** (`StartArrowData`): points to the initial state
- **IDs:** Internal ids are `n0`, `n1`, … and `l0`, `l1`, … Display labels default to spreadsheet-style letters (A, B, … Z, AA, …) via `nodeIdToAlpha()`

### Persistence

| Store | Location | Contents |
|-------|----------|----------|
| Guest workspace | SharedPreferences (local) | Graph DSL, export history, UI toggles |
| Signed-in workspace | Firestore `users/{uid}/workspace/main` | Same fields as guest |
| Game progress | SharedPreferences | Completed level IDs, difficulty choices |
| Theme | SharedPreferences | Palette, light/dark, custom colors |

Firebase is controlled by `kFirebaseConfigured` in `lib/persistence.dart`. When false or init fails, the app runs in guest/local-only mode.

---

## Application Modes

### Sandbox (`AutomataScreen`)

The main editor. Full canvas editing, all three simulators, import/export, batch testing, equivalence checking, black-box editing, and the settings drawer. This is the largest single file in the project (~1,700 lines).

### Game Mode (`LevelSelectScreen` → `GamePuzzleScreen`)

Levels are defined in `lib/game_level.dart` as `GameLevel` records in `kAllLevels`. Each level has:

- A **target machine** (embedded DSL or SVG asset path)
- An **unlock rule** (prerequisite levels)
- A **puzzle variant** (draw on canvas, match regex, read-only DFA, etc.)
- Map coordinates for the neural-network-style level select UI

Completion is checked via **equivalence** (`dialogs/equivalence_dialog.dart`) — the user's machine must accept/reject the same language as the target.

### Study Mode (`StudyModeScreen`)

Procedurally generates unlimited practice problems:

- Regex ↔ DFA conversion
- Natural-language description → FA
- PDA construction (with reference solutions in `pda_study_solutions.dart`)
- TM construction (with reference solutions in `tm_study_solutions.dart`)

Grading uses the same simulators and equivalence logic as Game Mode. After three wrong attempts, a canonical solution can be revealed.

---

## Source Files (`lib/`)

### Entry point & routing

#### `lib/main.dart`

**Purpose:** Application entry point and top-level navigation shell.

**Responsibilities:**
1. Validates game level data at startup (`kLayerConstraintErrors` — crashes loudly if level prerequisites are malformed, even in release builds)
2. Loads saved theme before first frame
3. Initializes Firebase optionally (app continues if it fails)
4. Provides `AuthService` and `AppThemeNotifier` via Provider
5. Routes authenticated users through `AppGate` to Login → Mode Select → Sandbox / Game / Study

**Key types:** `MyApp`, `AppGate`, `_AppMode` (internal enum)

**Depends on:** `automata_screen.dart`, `login_screen.dart`, `persistence.dart`, `study_mode_screen.dart`, `game_level.dart`, `widgets/app_theme.dart`

---

### Core data & algorithms

#### `lib/models.dart`

**Purpose:** Central graph data model used by every mode — canvas, simulators, import/export, and game/study grading.

**Key exports:**
- `NodeData` — state position, labels, accept/halt/black-box flags, TM tape indices
- `LineData` — edge between two nodes, label text, curve geometry, hit-testing
- `StartArrowData` — initial state indicator
- `LineGeometry` — computed arc/straight-line rendering math
- `nodeIdToAlpha()`, `displayNodeLabel()` — id → user-visible label conversion
- `applyAutomatonLayout()` — automatic graph layout helper

**Depends on:** Flutter `material.dart`, `dart:math`

**Notes:** This file is foundational. Before changing node/line behavior, read how `computeGeometry()` and `containsPoint()` work — they affect both rendering and tap targets.

---

#### `lib/simulator.dart`

**Purpose:** Step-by-step simulation for all automaton types. One of the most complex files (~3,700 lines).

**Key exports:**
- `AutomataSimulator` — DFA/NFA string simulation with black-box sub-machine support
- `PdaSimulator` — PDA with stack and epsilon closure
- `TmSimulator` — multi-tape TM with configurable step limits
- `SimResult`, `PdaSimResult`, `TmResult` — accept/reject outcomes
- Step snapshot types for UI highlighting
- Re-exports `regex_engine.dart` for backward-compatible imports

**Depends on:** `models.dart`, `import_export.dart`, `token_replacements.dart`, `widgets/automata_drawer.dart`

**Notes:** Simulators precompute step histories on `rebuild()`. The UI reads snapshots to highlight active nodes, lines, and (for TM) tape contents. Wildcard and negated-wildcard matching live here.

---

#### `lib/regex_engine.dart`

**Purpose:** Converts regular expressions to NFAs (Thompson construction), then DFAs (subset construction), with optional minimization.

**Key exports:** `RegexConversionResult`, `regexToDfa()`, `regexToNfa()`

**Regex dialect:** `*` = Kleene star, `+` = union, `~` = epsilon, parentheses for grouping

**Depends on:** `models.dart`

**Used by:** Study mode, regex panel in sandbox, some game/tutorial levels

---

#### `lib/import_export.dart`

**Purpose:** All serialization formats merged into one module (~3,100 lines). Formerly split across `dsl_code.dart`, `svg_export.dart`, `latex_export.dart`, `fa_to_regex.dart`, and dialog files.

**Key exports:**
- `GraphState` — plain container for nodes + lines + start arrow + mode
- `DslCodec` — text DSL import/export (primary save format)
- `SvgExporter` / `DslCodec.importFromSvg()` — visual export with embedded JSON
- `LatexExporter` / `LatexImporter` — TikZ round-trip
- `faToRegex()` — state elimination FA → regex
- Dialog helpers: `showLatexExportDialog()`, `showFaToRegexDialog()`, etc.

**Depends on:** `models.dart`, `widgets/automata_drawer.dart`, `widgets/app_theme.dart`

**Notes:** The DSL format is the canonical interchange format between persistence, game level targets, and black-box sub-programs. If you add a new node/line property, you must update `DslCodec` export and import paths.

---

#### `lib/token_replacements.dart`

**Purpose:** Parses `[[TOKEN]]` syntax in transition labels and simulation input into Unicode characters.

**Key exports:** `kTokenReplacements` (map), `parseTokenText()`

**Depends on:** `characters` package

---

#### `lib/persistence.dart`

**Purpose:** Authentication, Firebase configuration, and workspace session storage (~900 lines).

**Key exports:**
- `DefaultFirebaseOptions`, `kFirebaseConfigured` — Firebase on/off switch
- `AuthService`, `AuthMode` — email sign-in, registration, guest mode
- `SavedExport`, `PersistedSnapshot` — export history records
- `PreferencesStore` — low-level SharedPreferences wrapper
- `AutomataSessionStore` — abstract interface
- `LocalSessionStore` — guest/local persistence
- `FirebaseSessionStore` — cloud sync for signed-in users

**Depends on:** Firebase packages, `shared_preferences`

**Notes:** Game progress is **not** here — see `game_data.dart`. See `FIREBASE_SETUP.md` for setup steps.

---

### Screens

#### `lib/automata_screen.dart`

**Purpose:** Main sandbox canvas editor. Owns the full editing experience.

**Responsibilities:**
- Node/line creation, dragging, deletion, line mode (Shift or FAB)
- Pan and zoom
- Three parallel simulators (rebuilt when graph or mode changes)
- Auto-save via `AutomataSessionStore`
- Drawer, help overlay, regex panel, string simulator panel, PDA stack panel, TM config panel
- Import/export, batch simulator, equivalence dialog, black-box editor

**Key exports:** `AutomataScreen`

**Depends on:** Nearly all widgets, dialogs, core modules listed above

---

#### `lib/login_screen.dart`

**Purpose:** Pre-app authentication and mode selection landing page.

**Key exports:**
- `LoginScreen` — email/password auth and guest entry
- `ModeSelectScreen` — cards for Sandbox, Game, Study

**Depends on:** `persistence.dart`, `game_data.dart`, `widgets/app_theme.dart`

---

#### `lib/level_select_screen.dart`

**Purpose:** Game Mode level map — horizontal scrollable neural-network layout with prerequisite edges, difficulty picker, and navigation to puzzles or tutorials.

**Key exports:** `LevelSelectScreen`

**Depends on:** `game_level.dart`, `game_data.dart`, `game_puzzle.dart`, `tutorial_screen.dart`, `widgets/responsive_layout.dart`

---

#### `lib/game_puzzle.dart`

**Purpose:** Single puzzle level screen. Embeds the canvas (or variant UI for regex/read-only levels), runs equivalence check against the level target, saves completion to `GameProgressStore`.

**Key exports:** `GamePuzzleScreen`

**Depends on:** `game_level.dart`, `simulator.dart`, `dialogs/equivalence_dialog.dart`, `widgets/graph_widgets.dart`

---

#### `lib/tutorial_screen.dart`

**Purpose:** Animated slideshow tutorials for introductory game levels.

**Key exports:** `TutorialSlide`, `TutorialIllustration`, `TutorialScreen`

**Depends on:** `game_level.dart`, `game_data.dart`

---

#### `lib/study_mode_screen.dart`

**Purpose:** Study Mode hub (~3,200 lines). Generates challenges, manages a challenge queue, grades submissions, and hosts embedded canvas widgets.

**Key exports:** `StudyModeScreen`

**Depends on:** `study_mode_pda.dart`, `study_mode_tm.dart`, `study_mode_symbols.dart`, `simulator.dart`, `widgets/automata_canvas_embed.dart`

**Notes:** Regex↔DFA and description→FA logic largely lives here. PDA and TM challenges delegate to their dedicated modules.

---

### Game data

#### `lib/game_level.dart`

**Purpose:** Complete Game Mode level registry (~5,400 lines). **Read the header comment** for the level-authoring workflow.

**Key exports:**
- `UnlockRule` hierarchy — `AlwaysUnlocked`, `RequireLevel`, `RequireAll`, `RequireAny`, `RequireExpression`
- `GameLevel`, `LevelDifficulty`, `PuzzleVariant`, `EasyModeNode`
- `kAllLevels` — full catalog of all levels
- `computeLevelLayers()`, `kLayerConstraintErrors` — layout validation at startup

**Depends on:** `tutorial_screen.dart`, `dialogs/equivalence_dialog.dart`

**Notes:** Level targets are mostly embedded DSL strings in `kAllLevels`. Some levels reference SVG assets under `assets/levels/` (when present). The level-select map uses `x`/`y` coordinates in defined layout bands (FA, PDA, TM columns).

---

#### `lib/game_data.dart`

**Purpose:** Game progress persistence and automaton-type validation helpers for puzzle grading.

**Key exports:** `GameProgressStore`, `GamePreferenceKeys`, `buildTypeErrorMessage()`, type-check display types

**Depends on:** `shared_preferences`, `game_level.dart`, `dialogs/equivalence_dialog.dart`

---

### Study mode modules

#### `lib/study_mode_symbols.dart`

**Purpose:** Shared alphabet pool for randomized study challenges (digits + lowercase letters, excluding ambiguous `l` and `o`).

**Key exports:** `kStudySymbolPool`, `randomStudyAlphabet()`

---

#### `lib/study_mode_layout.dart`

**Purpose:** Post-processes generated solution graphs for readable spacing (curve bending, label clearance, self-loop spacing).

**Key exports:** `applyStudyModeLayout()`

**Depends on:** `models.dart`

---

#### `lib/study_mode_pda.dart`

**Purpose:** PDA study challenge generation, grading, and UI widgets (drawing area, test-case strip).

**Key exports:** `StudyPdaChallenge`, `generateStudyPdaChallenges()`, `gradeStudyPda()`, `StudyPdaDrawingArea`, etc.

**Depends on:** `pda_study_solutions.dart`, `simulator.dart`, `widgets/automata_canvas_embed.dart`

---

#### `lib/pda_study_solutions.dart`

**Purpose:** Builds canonical reference PDA graphs shown after repeated wrong answers (a^n b^n, palindromes, nested patterns, etc.).

**Key exports:** `PdaSolutionKind`, `PdaSolutionSpec`, `buildStudyPdaSolution()`

**Depends on:** `import_export.dart`, `models.dart`

---

#### `lib/study_mode_tm.dart`

**Purpose:** TM study challenge generation, grading, and UI. Covers ten language families (a^n b^n, a^n b^n c^n, palindrome, divisible-by-k, copy language, etc.).

**Key exports:** `StudyTmChallenge`, `generateStudyTmChallenges()`, `gradeStudyTm()`, `StudyTmDrawingArea`, `kStudyTmMaxSteps`

**Depends on:** `tm_study_solutions.dart`, `simulator.dart`

---

#### `lib/tm_study_solutions.dart`

**Purpose:** Canonical reference TM graph builders (~1,400 lines). Each solution was cross-checked against an independent Python reference model.

**Key exports:** `TmSolutionKind`, `TmSolutionSpec`, `buildStudyTmSolution()`

**Depends on:** `import_export.dart`, `models.dart`

---

### Widgets (`lib/widgets/`)

#### `lib/widgets/app_theme.dart`

**Purpose:** Complete theming system (~2,900 lines) — eight color palettes, WCAG contrast helpers, persistence, settings sheet, and themed FAB.

**Key exports:** `AppThemeData`, `AppThemeNotifier`, `buildMaterialTheme()`, `showAppThemeSettings()`, `PaletteFab`

**Depends on:** `shared_preferences`, `google_fonts`, `provider`

---

#### `lib/widgets/automata_drawer.dart`

**Purpose:** Hamburger menu drawer for sandbox and study mode.

**Key exports:** `AutomataMode` (enum), `AutomataDrawer`, `MarkdownFileScreen` (renders About/Changelog from assets)

**Features:** Mode switching, simulator toggles, import/export links, help/changelog/about, sign-out, navigation to other app modes

---

#### `lib/widgets/graph_widgets.dart`

**Purpose:** Low-level canvas rendering — the visual building blocks.

**Key exports:** `LineWidget`, `LinePainter`, `Node`, `StartArrowWidget`, `RubberBandPainter`

**Depends on:** `models.dart`, `app_theme.dart`, `token_replacements.dart`

---

#### `lib/widgets/automata_canvas_embed.dart`

**Purpose:** Self-contained embeddable canvas for Study Mode and previews. Supports read-only mode. No persistence or simulators — just draw/edit gestures.

**Key exports:** `AutomataCanvasEmbed`

---

#### `lib/widgets/sim_panels.dart`

**Purpose:** Floating side panels for simulation UI (~2,800 lines).

**Key exports:**
- `StringSimulatorPanel` — DFA/NFA string input and step controls
- `PdaStackPanel` — stack visualization for PDA
- `TmConfigPanel` — multi-tape TM configuration and step view
- `RegexPanel` — regex entry and conversion to automaton

---

#### `lib/widgets/help_overlay.dart`

**Purpose:** Compact floating cheat sheet for canvas controls and mode-specific syntax.

**Key exports:** `HelpOverlay`

**Notes:** Content adapts to the current `AutomataMode` so PDA/TM tips only show when relevant.

---

#### `lib/widgets/black_box_input_dialog.dart`

**Purpose:** Dialog for editing TM black-box sub-program DSL with live validation and quick-insert chips.

**Key exports:** `BlackBoxEditDialog`

---

#### `lib/widgets/responsive_layout.dart`

**Purpose:** Breakpoint helpers for phone vs tablet/desktop (used by level select and other wide layouts).

**Key exports:** `isCompactLayout()`, `responsiveHorizontalPadding()`, `levelMapLayoutScale()`

---

### Dialogs (`lib/dialogs/`)

#### `lib/dialogs/equivalence_dialog.dart`

**Purpose:** Core grading logic — checks whether two automata accept the same language. Also validates automaton type (DFA vs NFA, etc.) for game levels.

**Key exports:** `checkEquivalence()`, `checkPdaEquivalence()`, `checkTmEquivalence()`, `AutomatonTypeChecker`, `showEquivalenceDialog()`

**Depends on:** `simulator.dart`, `import_export.dart`, `models.dart`

**Notes:** This is the backbone of Game Mode win conditions and Study Mode grading.

---

#### `lib/dialogs/automata_dialogs.dart`

**Purpose:** Export/import/history dialogs and black-box runner for testing embedded sub-machines.

**Key exports:** `showExportDialog()`, `showImportDialog()`, `showExportHistoryDialog()`, `showBlackBoxRunnerDialog()`

---

#### `lib/dialogs/batch_simulator_dialog.dart`

**Purpose:** Paste multiple input strings, run them all through the active simulator, display accept/reject results in a table.

**Key exports:** `showBatchSimulatorDialog()`

**Flutter APIs:** [`Dialog`](https://api.flutter.dev/flutter/material/Dialog-class.html), [`TextEditingController`](https://api.flutter.dev/flutter/widgets/TextEditingController-class.html) (custom `_BatchHighlightController` subclass for inline green/red line coloring), [`file_picker`](https://pub.dev/packages/file_picker) for importing a `.txt` file of test strings.

---

## Deep Dives — Important Files

These are the files most likely to confuse a new maintainer. Each subsection explains internal structure, not just the file's role.

### `lib/automata_screen.dart` (~1,700 lines)

The sandbox heart of the app. `_AutomataScreenState` mixes three concerns that are intentionally kept in one class:

**1. Graph state (the model)**

```dart
final Map<String, NodeData> _nodes = {};
final Map<String, LineData> _lines = {};
StartArrowData? _startArrow;
int _nodeCounter = 0;
int _lineCounter = 0;
```

Nodes and lines use [`Map`](https://api.flutter.dev/flutter/dart-core/Map-class.html) keyed by stable ids (`n0`, `l0`, …) so hit-testing during pan gestures is O(1). The maps are passed by reference into `GraphState` via the `_graphState` getter — they are not copied on every read.

**2. Interaction mode flags (mutually exclusive editing modes)**

| Flag | Meaning |
|------|---------|
| `_lineMode` | Drag from node A to node B to create a transition |
| `_placingStartArrow` | Next tap places/moves the start arrow |
| `_deleteMode` | Next tap deletes the touched node/line/arrow |

Only one "gesture interpretation" is active at a time. Turning on delete mode clears line mode and start-arrow placement.

**3. Three simulators kept alive in parallel**

```dart
late final AutomataSimulator _simulator;
late final PdaSimulator _pdaSimulator;
late final TmSimulator _tmSimulator;
```

All three are rebuilt on every graph edit via `_refreshSimulation()` → `_simRebuild()`, regardless of current mode, so switching NDFA → PDA → TM does not lose step history. Highlight sets come from `_simHighlight`, which reads `activeNodes`/`activeLines` from the active simulator.

**Keyboard and focus**

- A root [`FocusNode`](https://api.flutter.dev/flutter/widgets/Focus-class.html) (`_focusNode`) captures canvas focus so [`KeyboardListener`](https://api.flutter.dev/flutter/widgets/KeyboardListener-class.html) receives Shift key events ([`LogicalKeyboardKey.shiftLeft`](https://api.flutter.dev/flutter/services/LogicalKeyboardKey-class.html) / `shiftRight`) to toggle line mode.
- Tapping empty canvas calls `FocusScope.of(context).requestFocus(_focusNode)` to unfocus inline label [`TextEditingController`](https://api.flutter.dev/flutter/widgets/TextEditingController-class.html)s on nodes/lines.

**Persistence**

- Debounced autosave: `_schedulePersist()` starts a 400 ms [`Timer`](https://api.flutter.dev/flutter/dart-async/Timer-class.html); `_persistNow()` writes via `AutomataSessionStore`.
- [`WidgetsBindingObserver`](https://api.flutter.dev/flutter/widgets/WidgetsBindingObserver-class.html): on `AppLifecycleState.paused`/`detached`, pending saves flush immediately.
- [`dispose()`](https://api.flutter.dev/flutter/widgets/State/dispose.html): cancels timer, disposes `_simController`, all `_tapeControllers`, `_focusNode`, and fires a best-effort final save.

**Build tree (simplified)**

```
Scaffold
  drawer: AutomataDrawer
  body: KeyboardListener
    child: GestureDetector (pan/tap)
      child: Stack
        ├── Transform (pan/zoom canvas)
        │     ├── LineWidget × N
        │     ├── Node × N
        │     └── StartArrowWidget
        ├── RubberBandPainter (line-mode preview)
        ├── HelpOverlay (optional)
        └── StringSimulatorPanel / PdaStackPanel / TmConfigPanel / RegexPanel
```

See also: [Gestures cookbook](https://docs.flutter.dev/ui/interactivity/gestures).

---

### `lib/models.dart` (~980 lines)

Pure data + geometry — no widgets except `Offset` from Flutter. Everything else imports this file.

**`NodeData`** — one automaton state:
- `position` is top-left of bounding box; `center` getter accounts for circle (100×100) vs black-box rectangle (140×100)
- `connectedLineIds` — maintained when lines are added/removed
- `containsPoint(Offset)` — circular or rectangular hit test for taps
- Black-box fields: `blackBoxDsl`, `blackBoxReadTape`, `blackBoxWriteTape`, `blackBoxActiveTapes`

**`LineData`** — one directed transition:
- `label` — raw text in the on-canvas textbox
- `labelAlternatives` — splits on comma/newline for NFA multi-symbol edges
- `perpendicularPart` — user-draggable curve control; negative = bend the other way
- `computeGeometry(centerA, centerB)` → `LineGeometry` — the math for straight segments, circular arcs, and self-loops
- Constants `kSelfLoopRadius`, `kSelfLoopOffset` are exported so `study_mode_layout.dart` can predict spacing without duplicating magic numbers

**`applyAutomatonLayout()`** — force-directed-ish repositioning used after regex import and in some study solutions.

If simulation says a transition should fire but the UI doesn't highlight it, check both the label parsing in `simulator.dart` and whether `LineData.id` is still in the map after an import.

---

### `lib/simulator.dart` (~3,700 lines)

Three classes, one file, shared tokenizer helpers at the top.

**`AutomataSimulator`**
- On `rebuild(input, graph, startArrow)`: tokenizes input via `parseTokenText`, BFS/DFS explores configurations `(nodeId, tokens, inputPos)`
- Black-box nodes: `_runBlackBox` imports nested DSL via `DslCodec.importFromDsl`, runs inner machine, rewrites remaining tokens
- Exposes `states`, `usedLines`, `activeNodes`, `activeLines`, `step`, `maxStep` for UI stepping
- Wildcard `.` and negated `.-xyz` handled in `_labelMatches`

**`PdaSimulator`**
- Configuration: `(nodeId, inputPos, stack)` — stack is `List<String>` with bottom marker `kStackBottom` (`⊥`)
- Epsilon closure before consuming input; no infinite loops (each config visited at most once per step)
- `PdaStepSnapshot` includes stack contents for `PdaStackPanel`

**`TmSimulator`**
- Multi-tape: `List<TmTape>` each with head index and cell map
- Step limit `kStudyTmMaxSteps` in study mode prevents runaway loops during grading
- Halt-accept / halt-reject nodes stop computation immediately when entered
- `~` transitions: no read/write, always enabled

**Re-export:** `export 'regex_engine.dart'` so files importing only `simulator.dart` still get `regexToDfa`.

---

### `lib/widgets/graph_widgets.dart` (~1,250 lines)

Visual layer only — receives `NodeData`/`LineData` and paints them. Does **not** mutate the graph.

**`LinePainter`** (`CustomPainter`) — draws arc or straight segment + arrowhead. Color priority: delete mode > error > simulation highlight > default. `pulseOpacity` drives blinking during simulation.

**`LineWidget`** — wraps `LinePainter` + positions the label `TextField`:
- Owns [`TextEditingController`](https://api.flutter.dev/flutter/widgets/TextEditingController-class.html) and [`FocusNode`](https://api.flutter.dev/flutter/widgets/Focus-class.html)
- On focus loss, commits label to `LineData.label` via callback
- [`dispose()`](https://api.flutter.dev/flutter/widgets/State/dispose.html) disposes controller, focus node, and pulse animation controller

**`Node`** — similar pattern for state circles, octagons (halt), and black-box rectangles. Duplicate label detection tints node orange via theme callback.

**`RubberBandPainter`** — dashed preview line while dragging a new transition in line mode.

**`StartArrowWidget`** — draggable initial-state arrow independent of any node.

---

### `lib/widgets/automata_drawer.dart` (~1,200 lines)

Hamburger menu built from [`ListView`](https://api.flutter.dev/flutter/widgets/ListView-class.html) sections.

- **`AutomataMode` enum** — lives here because drawer owns mode switching; imported elsewhere with `show AutomataMode`
- **`_HoverSwitch`** — full-row [`InkWell`](https://api.flutter.dev/flutter/material/InkWell-class.html) + [`Switch`](https://api.flutter.dev/flutter/material/Switch-class.html) for toggles (simulator panel, help overlay, …)
- **Collapsible sections** — [`AnimatedRotation`](https://api.flutter.dev/flutter/widgets/AnimatedRotation-class.html) on chevron [`Icons`](https://api.flutter.dev/flutter/material/Icons-class.html) rotates 200 ms when expanding
- **`MarkdownFileScreen`** — loads `assets/About.md` / `assets/Changelog.md` via [`rootBundle`](https://api.flutter.dev/flutter/services/rootBundle.html), displays as [`SelectableText`](https://api.flutter.dev/flutter/material/SelectableText-class.html) so users can copy text
- Navigation callbacks (`onGoToGame`, `onSignOut`, …) are passed in from parent — drawer does not use [`Navigator`](https://api.flutter.dev/flutter/widgets/Navigator-class.html) for mode switches

---

### `lib/widgets/sim_panels.dart` (~2,800 lines)

Floating panels docked beside the canvas.

| Widget | Role |
|--------|------|
| `StringSimulatorPanel` | Input field, step forward/back, accept/reject indicator |
| `PdaStackPanel` | Stack contents per step |
| `TmConfigPanel` | Multi-tape tabs, head positions, alternate branch picker |
| `RegexPanel` | Regex text field + "Convert to automaton" button |

Each panel uses [`ListView.separated`](https://api.flutter.dev/flutter/widgets/ListView-class.html) for step history where needed. TM panel owns multiple [`TextEditingController`](https://api.flutter.dev/flutter/widgets/TextEditingController-class.html)s for additional tape inputs and must dispose them in [`dispose()`](https://api.flutter.dev/flutter/widgets/State/dispose.html).

---

### `lib/import_export.dart` (~3,100 lines)

Five former files merged. Internal sections marked with comments: `dsl_code`, `latex_export`, `fa_to_regex`, etc.

**`DslCodec.exportToDsl` / `importFromDsl`** — canonical text format. Rough shape:

```
MODE ndfa
NODE n0 100 200 label="" accept=0 ...
LINE l0 n0 n1 label="a,b" perp=0 ...
START n0 50 150
```

**`GraphState`** — immutable snapshot bag; `nodeAt(Offset)` / `lineAt(Offset)` delegate hit tests to contained maps.

**Dialogs in this file** use [`showDialog`](https://api.flutter.dev/flutter/material/Dialog-class.html), [`SelectableText`](https://api.flutter.dev/flutter/material/SelectableText-class.html) for output users should copy, and [`ScaffoldMessenger.of(context).showSnackBar`](https://api.flutter.dev/flutter/material/ScaffoldMessenger-class.html) for "Copied!" feedback ([Snackbars cookbook](https://docs.flutter.dev/cookbook/design/snackbars)).

**When adding a new `NodeData` field:** update export, import, SVG embedded JSON, and any DSL version comments — or old saves will silently drop the new property.

---

### `lib/persistence.dart` (~900 lines)

Four logical sections in one file:

1. **`DefaultFirebaseOptions`** — hand-maintained Firebase config; `kFirebaseConfigured` global switch
2. **`AuthService`** — sign in, register, sign out, continue as guest; persists `AuthMode` to SharedPreferences
3. **`PreferencesStore`** — thin JSON encode/decode wrapper for primitive-only SharedPreferences storage
4. **`AutomataSessionStore`** — abstract interface with `LocalSessionStore` (guest) and `FirebaseSessionStore` (signed-in)

**Firestore document shape** (`users/{uid}/workspace/main`):

| Field | Type | Meaning |
|-------|------|---------|
| `graphDsl` | string | Full canvas exported via `DslCodec` |
| `savedExports` | JSON array | Named export history |
| `showSimulator` | bool | Panel visibility |
| `showHelpOverlay` | bool | Help overlay visibility |
| `simInput` | string | Last simulation input string |
| `simStep` | int | Last simulation step index |
| `updatedAt` | timestamp | Cloud conflict hint |

`AppGate` in `main.dart` lazily constructs the correct store implementation after auth — guest always gets `LocalSessionStore`.

---

### `lib/dialogs/equivalence_dialog.dart` (~1,670 lines)

Three sections, deliberately separable:

**Section 1 — Algorithms (pure Dart, no UI)**
- `checkEquivalence()` — DFA/NFA: product construction + BFS; returns `EquivalenceResult` with distinguishing witness string
- `checkPdaEquivalence()` / `checkTmEquivalence()` — bounded search; may return `unknownCapReached` (undecidable in general)
- Imported by `game_puzzle.dart`, `game_data.dart`, `study_mode_*.dart` **without** opening any dialog

**Section 2 — Type checking**
- `AutomatonTypeChecker.check()` — is this graph a valid DFA? NFA? Used when a level requires a specific type

**Section 3 — UI**
- `showEquivalenceDialog()` — paste two DSL strings, run check, display result

Game Mode win condition: `GamePuzzleScreen` calls section 1 directly, then saves to `GameProgressStore` on success.

---

### `lib/game_level.dart` (~5,400 lines)

**`kAllLevels`** — const list of every `GameLevel`. Each entry includes:
- `id`, `title`, `description`
- `targetDsl` or `svgAsset` — reference solution
- `unlockRule` — AST node (`RequireLevel`, `RequireAll`, …)
- `x`, `y` — position on level-select map (0.0–1.0 normalized)
- `variant` — `PuzzleVariant` (canvas draw, regex entry, tutorial redirect, …)
- `requiredType` — optional DFA/NFA enforcement
- `difficulties` — easy mode may pre-place nodes via `EasyModeNode`

**`kLayerConstraintErrors`** — computed at startup; `main.dart` throws if non-empty. Validates that prerequisite levels don't create impossible unlock graphs.

**Layout bands** (x coordinate):
- 0.00–0.64 — FA levels
- 0.68–0.80 — PDA levels
- 0.84–0.97 — TM levels

---

### `lib/study_mode_screen.dart` (~3,200 lines)

Orchestrates all study types from one screen:

1. **Challenge queue** — generates N upcoming problems per category
2. **Grading** — calls `gradeStudyPda` / `gradeStudyTm` / internal regex checks / `checkEquivalence`
3. **Embedded canvas** — `AutomataCanvasEmbed` for user drawings (lighter than full `AutomataScreen`)
4. **Reveal logic** — after 3 wrong attempts, shows solution from `pda_study_solutions.dart` or `tm_study_solutions.dart`
5. **Tutorial sheet** — links to selected tutorial levels from `game_level.dart`

Challenge generators randomize alphabets via `randomStudyAlphabet()` from `study_mode_symbols.dart`.

---

### `lib/login_screen.dart` (~1,035 lines)

Two screens, one file, shared dark "grid glow" aesthetic.

**`LoginScreen`**
- [`TextEditingController`](https://api.flutter.dev/flutter/widgets/TextEditingController-class.html) for email/password; disposed in [`dispose()`](https://api.flutter.dev/flutter/widgets/State/dispose.html)
- `firebaseEnabled == false` → only "Continue as Guest" works; email fields disabled
- `AnimationController` drives `_GridPainter` background (purely cosmetic)

**`ModeSelectScreen`**
- Three [`InkWell`](https://api.flutter.dev/flutter/material/InkWell-class.html) cards with [`BoxDecoration`](https://api.flutter.dev/flutter/painting/BoxDecoration-class.html) glow for Sandbox / Game / Study
- Reads `GameProgressStore` for completed level count badge

---

### `lib/level_select_screen.dart` (~800 lines)

Horizontal scrolling "neural network" map.

- Custom painter draws prerequisite edges (green = satisfied, amber = partial, gray = locked)
- [`ListView`](https://api.flutter.dev/flutter/widgets/ListView-class.html) or scroll controller + slider for keyboard/mouse navigation
- [`KeyboardListener`](https://api.flutter.dev/flutter/widgets/KeyboardListener-class.html) for debug cheat codes (Enter/Backspace sequence)
- [`ScaffoldMessenger`](https://api.flutter.dev/flutter/material/ScaffoldMessenger-class.html) shows cheat activation snackbar
- Uses `responsive_layout.dart` for compact vs wide layouts ([`ConstrainedBox`](https://api.flutter.dev/flutter/widgets/ConstrainedBox-class.html) scaling)

---

### `lib/widgets/automata_canvas_embed.dart` (~850 lines)

Stripped-down `AutomataScreen` for Study Mode:
- Same gesture/keyboard patterns ([`KeyboardListener`](https://api.flutter.dev/flutter/widgets/KeyboardListener-class.html) + Shift line mode)
- **No** simulators, **no** persistence, **no** drawer
- `readOnly` flag disables editing (used for solution reveal)
- Parent owns the `Map<String, NodeData>` / `Map<String, LineData>` and receives updates via callbacks

---

## Tests (`test/`)

### `test/models_test.dart`

Tests `LineData` geometry edge cases (collinear arc fallback to straight line) and `labelAlternatives` splitting on comma/newline.

### `test/simulator_test.dart`

Tests `AutomataSimulator` transition label parsing, tokenizer edge cases (unclosed quotes, malformed `[[` tokens), and `PdaSimulator` step preservation on rebuild.

**Running:** `flutter test`

**Note:** Test coverage is minimal relative to codebase size. The simulators and equivalence checker are the highest-value areas for additional tests.

---

## Assets (`assets/`)

| File | Purpose |
|------|---------|
| `assets/About.md` | In-app About text (loaded by drawer) |
| `assets/Changelog.md` | In-app changelog mirror of root `Changelog.md` |
| `assets/Version.md` | Placeholder overwritten by deploy script for web builds |

Game level SVG assets may live under `assets/levels/` when checked in; many levels currently embed target DSL directly in `game_level.dart` instead.

The entire `assets/` folder is registered in `pubspec.yaml`.

---

## Root Configuration & Docs

| File | Purpose |
|------|---------|
| `pubspec.yaml` | Package manifest, dependencies, asset registration, version `1.0.0+1` |
| `pubspec.lock` | Locked dependency versions (commit this file) |
| `analysis_options.yaml` | Linter rules (`flutter_lints`), 120-char formatter width |
| `firebase.json` | FlutterFire CLI config (points at Firebase project `toc-fa-ramsey`) |
| `README.md` | Minimal readme with link to published web build |
| `About.md` | Copyright and contributor attribution (root copy) |
| `Changelog.md` | Detailed development log (May 2025 – July 2026) |
| `FIREBASE_SETUP.md` | Step-by-step Firebase Auth + Firestore setup |
| `.vscode/launch.json` | VS Code debug configurations |
| `.gitignore` | Standard Flutter ignores |
| `.metadata` | Flutter project metadata (auto-generated) |

---

## Platform Folders (Brief)

These are standard Flutter platform scaffolding. You rarely need to edit them unless adding native permissions, app icons, or Firebase platform config files.

| Folder | Notes |
|--------|-------|
| `android/` | Android build; add `google-services.json` for Firebase |
| `ios/` | iOS build; add `GoogleService-Info.plist` for Firebase |
| `web/` | Web entry (`index.html`, `manifest.json`, icons) — used for GitHub Pages deploy |
| `windows/` / `linux/` / `macos/` | Desktop platform runners |

Generated plugin registrant files under `*/flutter/` are build artifacts — do not edit manually.

---

## Common Maintenance Tasks

### Add a new Game Mode level

1. Read the workflow comment at the top of `lib/game_level.dart`
2. Create target machine (DSL or SVG with embedded `automata-data` script)
3. Add a `GameLevel` entry to `kAllLevels` with `id`, `title`, `description`, `unlockRule`, and map `x`/`y`
4. Restart the app — `main.dart` validates layer constraints at startup

### Add a new Study Mode PDA/TM language

1. Add a generator case in `study_mode_pda.dart` or `study_mode_tm.dart`
2. Add a reference solution builder in `pda_study_solutions.dart` or `tm_study_solutions.dart`
3. Add test cases that the grader will run against the user's machine

### Change how machines are saved

1. Update `DslCodec` in `import_export.dart` (export and import)
2. Update `PersistedSnapshot` fields in `persistence.dart` if new UI state needs persisting
3. Consider backward compatibility — old saved exports in user history should still load

### Enable or disable Firebase

1. Set `kFirebaseConfigured` in `lib/persistence.dart`
2. Follow `FIREBASE_SETUP.md` for platform config files and Firestore rules
3. Guest mode always works without Firebase

### Change app colors / theme

Edit `lib/widgets/app_theme.dart` — palette definitions, `AppThemeData`, and the settings sheet UI.

---

## Where to Start for Common Changes

| I want to… | Start here |
|------------|------------|
| Fix string simulation | `lib/simulator.dart` → `AutomataSimulator` |
| Fix PDA stack behavior | `lib/simulator.dart` → `PdaSimulator` |
| Fix TM tape stepping | `lib/simulator.dart` → `TmSimulator` |
| Change canvas drawing/editing | `lib/automata_screen.dart`, `lib/widgets/graph_widgets.dart` |
| Change how edges look or bend | `lib/models.dart` → `LineData.computeGeometry()` |
| Fix level not unlocking | `lib/game_level.dart` → unlock rules for that level |
| Fix "you win" not triggering | `lib/dialogs/equivalence_dialog.dart` |
| Add regex conversion feature | `lib/regex_engine.dart`, `lib/widgets/sim_panels.dart` |
| Change login / guest behavior | `lib/persistence.dart` → `AuthService` |
| Change cloud sync fields | `lib/persistence.dart` → `FirebaseSessionStore` |
| Change study question types | `lib/study_mode_screen.dart` + PDA/TM modules |
| Update in-app About/Changelog | `assets/About.md`, `assets/Changelog.md` |

---

## Dependency Summary

Main third-party packages (see `pubspec.yaml` for versions):

| Package | Used for |
|---------|----------|
| `provider` | Theme state propagation |
| `shared_preferences` | Local persistence (guest, theme, game progress) |
| `firebase_core`, `firebase_auth`, `cloud_firestore` | Optional cloud auth and sync |
| `google_fonts` | Typography (Courier-style monospace feel) |
| `file_picker` | File import on desktop/mobile |
| `characters` | Unicode-safe string handling in token parser |
| `cupertino_icons` | iOS-style icons |

---

## Final Notes for Future Maintainers

1. **Read file headers.** Many source files have detailed block comments at the top explaining design decisions — especially `main.dart`, `simulator.dart`, `game_level.dart`, and `import_export.dart`.

2. **Startup validation is intentional.** The app throws on malformed level prerequisites rather than shipping a broken level-select screen.

3. **Firebase is optional by design.** Never assume a user is signed in or that Firestore is available.

4. **Epsilon is `~`.** Keep this consistent across DSL, UI labels, simulators, and study generators.

5. **Large files are normal here.** `automata_screen.dart`, `simulator.dart`, `game_level.dart`, `study_mode_screen.dart`, and `app_theme.dart` are intentionally monolithic from mid-project refactors that merged smaller files. Consider extracting modules if you add major features, but avoid drive-by splits.

6. **Changelog discipline.** Update both root `Changelog.md` and `assets/Changelog.md` when shipping user-visible changes (the drawer reads the assets copy).

---

*Last updated: July 2026 — written for project handoff.*
