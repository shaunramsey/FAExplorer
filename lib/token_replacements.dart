import 'package:characters/characters.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  token_replacements.dart
//
//  Turns typed tokens like `[[DELTA]]` into their Unicode symbol (`δ`), so
//  users can type transition/label text on a normal keyboard without a
//  special symbol picker. Two independent mechanisms live here:
//    1. A literal lookup table (kTokenReplacements) for named symbols.
//    2. A special `[[/text]]` syntax that overlays a combining "long
//       solidus" (strikethrough) on every character of `text`, used e.g.
//       for negated symbols.
//  parseTokenText() is the single entry point that applies both.
// ─────────────────────────────────────────────────────────────────────────────

// ─────────────────────────────────────────────────────────────────────────────
//  REPLACEMENT TABLE
// ─────────────────────────────────────────────────────────────────────────────

/// Maps a bracketed token *name* (the text between `[[` and `]]`, case
/// sensitive, matched exactly as written below) to the Unicode character it
/// should be replaced with. Lookup in parseTokenText is a plain Dart Map
/// lookup, so a typed token must match one of these keys **exactly**,
/// including case — `[[infinity]]` will NOT match `'INFINITY'`.
const Map<String, String> kTokenReplacements = {
  // Control
  // `\0` here is the two-character string backslash-zero (r'' is a raw
  // string literal, so no actual escaping happens — this key is literally
  // the characters '\' and '0'). Typing the literal six characters
  // "[[\0]]" therefore renders as ∅ (empty set) directly via this table
  // entry. This is a *different* code path from typing "[[/0]]", which
  // instead falls into the strikethrough branch in parseTokenText() below
  // and renders as a zero with a combining slash through it (0̸) — visually
  // similar to ∅ but a distinct glyph, not this table's ∅ character. Both
  // exist; neither is a bug, but they're easy to confuse with each other
  // when reading call sites.
  r'\0': '∅',

  // Greek lowercase
  'ALPHA': 'α', 'BETA': 'β', 'GAMMA': 'γ', 'ZETA': 'ζ', 'ETA': 'η',
  'THETA': 'θ', 'IOTA': 'ι', 'KAPPA': 'κ',
  // BUG: this key is spelled 'LAMDA' (missing the 'B'). help_overlay.dart's
  // symbol legend advertises the shortcut as `[[LAMBDA]]` (correctly
  // spelled) for the λ symbol chip. Because Map lookups are exact-string,
  // typing the token exactly as the in-app help tells users to
  // (`[[LAMBDA]]`) will NOT match this key and will silently pass through
  // unchanged as the literal text "[[LAMBDA]]" instead of rendering λ.
  // Only the misspelled `[[LAMDA]]` currently works. Fix by either
  // correcting this key to 'LAMBDA', or adding 'LAMBDA' as a second key
  // aliasing the same 'λ' value (mirroring how PARAGRAPH/PILCROW below
  // alias the same character) so both spellings work.
  'LAMDA': 'λ',
  'DELTA': 'δ',
  'EPSILON': 'ε', 'MU': 'μ', 'PI': 'π', 'SIGMA': 'σ', 'OMEGA': 'ω',
  'PHI': 'φ',

  // Greek uppercase
  'GAMMA_CAP': 'Γ', 'DELTA_CAP': 'Δ', 'PI_CAP': 'Π',
  'SIGMA_CAP': 'Σ', 'OMEGA_CAP': 'Ω', 'PHI_CAP': 'Φ',

  // Math
  'INFINITY': '∞', 'SQRT': '√', 'PLUSMINUS': '±', 'NOTEQUAL': '≠',
  'LESSEQ': '≤', 'GREATEREQ': '≥', 'APPROX': '≈', 'MULTIPLY': '×',
  'DIVIDE': '÷',

  // Arrows
  'LEFT': '←', 'RIGHT': '→', 'UP': '↑', 'DOWN': '↓', 'LEFTRIGHT': '↔',

  // Punctuation / misc symbols
  'CHECK': '✓',
  // Note: key is the bare letter 'X', not e.g. 'XMARK'. Typing `[[X]]`
  // therefore produces a ballot-X glyph ('✗'), not the literal letter X —
  // intentional (there'd be no reason to "replace" a literal X with
  // itself), but worth knowing if this table is ever searched for "why
  // did my X turn into a cross".
  'X': '✗', 'STAR': '★', 'HEART': '♥', 'BULLET': '•',
  'QUESTION': '?', 'ELLIPSIS': '…', 'COPY': '©', 'REGISTERED': '®',
  'TRADEMARK': '™', 'DEGREE': '°',
  // PARAGRAPH and PILCROW below are two different key spellings for the
  // *same* character (¶ is formally called a "pilcrow"). Not a bug — both
  // are intentionally kept so either word works as the token name — but
  // note it's a deliberate alias, unlike the LAMDA/LAMBDA case above where
  // only one spelling was actually wired up.
  'PARAGRAPH': '¶', 'SECTION': '§',
  'CURRENCY': '¤', 'PILCROW': '¶',

  // Emoji / dingbats
  //
  // Naming inconsistency to be aware of: every key above this point is a
  // single word (plus the `_CAP` suffix convention for uppercase Greek).
  // Several keys below contain literal spaces (e.g. 'YIN YANG',
  // 'BLACK SMILEY', 'MUSIC NOTE', 'BEAMED EIGHTH NOTES',
  // 'STAR AND CRESCENT', 'FALLING STAR', 'HAMMER AND SICKLE',
  // 'HOT SPRINGS'). These still work correctly (the token regex's `.*?`
  // capture group matches spaces fine, and Map lookup matches the space
  // verbatim), but a user has to reproduce the exact spacing, e.g.
  // `[[YIN YANG]]`, which is easy to get wrong and easy to typo compared
  // to the single-word tokens elsewhere in this table.
  'PEACE': '☮', 'YIN YANG': '☯', 'SMILEY': '☺', 'BLACK SMILEY': '☻',
  'SUN': '☀', 'CLOUD': '☁', 'UMBRELLA': '☂', 'SNOWFLAKE': '❄',
  'SKULL': '☠', 'SPADE': '♠', 'CLUB': '♣', 'DIAMOND': '♦',
  'MUSIC NOTE': '♪', 'BEAMED EIGHTH NOTES': '♫', 'RADIOACTIVE': '☢',
  'BIOHAZARD': '☣', 'CLOVER': '☘', 'HANDS': '☝', 'MALE': '♂',
  'FEMALE': '♀', 'STAR AND CRESCENT': '☪', 'FALLING STAR': '☫',
  'HAMMER AND SICKLE': '☭', 'HOT SPRINGS': '♨', 'HOTEL': '🏨',
  'HOSPITAL': '🏥', 'HOURGLASS': '⌛',
};

// ─────────────────────────────────────────────────────────────────────────────
//  PARSER
// ─────────────────────────────────────────────────────────────────────────────

/// Replaces every `[[KEY]]` token in [input] with its symbol.
///
/// * `\[[KEY]]` (escaped) is left as `[[KEY]]` literally.
/// * `[[/text]]` applies a combining-solidus overlay to each character.
///
/// Unmatched tokens (a `[[...]]` whose inner text isn't a key in
/// [kTokenReplacements] and doesn't start with `/`) are left completely
/// unchanged, brackets and all — see the `?? full` fallback below. This is
/// why the LAMDA/LAMBDA bug noted above fails silently rather than
/// throwing or showing a placeholder: an unrecognized token is
/// indistinguishable, from the caller's point of view, from a string that
/// was never meant to be a token at all.
String parseTokenText(String input) {
  // Regex breakdown of r'\\?\[\[(.*?)\]\]':
  //   \\?        - an optional literal backslash immediately before the
  //                opening brackets (this is what marks an "escaped" token)
  //   \[\[       - literal "[["
  //   (.*?)      - LAZY capture of the token body. Lazy (not greedy) matters
  //                here: with a greedy `.*`, an input containing two tokens
  //                on one line, e.g. "[[A]] text [[B]]", would incorrectly
  //                capture "A]] text [[B" as one giant token body instead of
  //                matching "A" and "B" as two separate tokens. `.` does not
  //                match newlines by default in Dart, so a token body can't
  //                span multiple lines (not an issue in practice — every key
  //                in kTokenReplacements is single-line).
  //   \]\]       - literal "]]"
  return input.replaceAllMapped(RegExp(r'\\?\[\[(.*?)\]\]'), (match) {
    // The entire matched substring, e.g. "[[DELTA]]" or "\[[DELTA]]"
    // (including the leading backslash if present — group(0) always
    // includes everything the whole pattern matched, not just captured
    // groups).
    final full = match.group(0)!;

    // Escaped form: a literal backslash was typed directly before the
    // brackets, e.g. the user wanted to type the literal text "[[DELTA]]"
    // rather than trigger the replacement. Strip just the leading
    // backslash and return the rest (`[[DELTA]]`) verbatim — this is the
    // *only* branch that can produce literal, un-substituted "[[...]]"
    // text in the output on purpose.
    if (full.startsWith(r'\')) return full.substring(1);

    // Non-escaped path: pull out just the captured token body (group 1),
    // e.g. "DELTA" from "[[DELTA]]", and trim incidental whitespace a user
    // might have typed inside the brackets (e.g. "[[ DELTA ]]").
    final key = (match.group(1) ?? '').trim();

    // Strikethrough overlay: `[[/word]]`. Any token body starting with '/'
    // is NOT looked up in kTokenReplacements at all — it's treated as a
    // request to strike through the text that follows the slash.
    if (key.startsWith('/')) {
      // Drop the leading '/' to get the text to strike through, e.g.
      // "word" from "/word", or "0" from "/0" (this is the `[[/0]]` path
      // referenced in the kTokenReplacements comment above — distinct from
      // the literal `\0` -> ∅ table entry).
      final text = key.substring(1);

      // Iterate by Unicode grapheme cluster (`.characters`), NOT by raw
      // UTF-16 code unit (`String` indexing / `.split('')`). This matters
      // for correctness: naively splitting a String containing characters
      // outside the Basic Multilingual Plane (e.g. some emoji, which are
      // encoded as UTF-16 surrogate pairs) with `.split('')` would break a
      // single visual character into two invalid halves and then append a
      // combining mark to each half separately, corrupting the glyph.
      // `characters` guarantees each `ch` here is one whole, correctly-
      // grouped user-perceived character.
      //
      // Spaces are left untouched (a combining slash through a space
      // renders as a stray floating slash mark with nothing to strike,
      // which looks like a rendering glitch rather than "space, struck
      // through") — every other character gets U+0338 COMBINING LONG
      // SOLIDUS OVERLAY appended immediately after it, which is how a
      // "strikethrough single character" is represented in Unicode
      // (combining marks render visually on top of/through the preceding
      // base character rather than needing real strikethrough text
      // styling).
      return text.characters.map((ch) => ch == ' ' ? ch : '$ch\u0338').join();
    }

    // Plain lookup path: look the (trimmed, case-sensitive) key up in the
    // replacement table. If it's not found, `?? full` falls back to
    // returning the *entire original match* unchanged (brackets included)
    // rather than e.g. an empty string or an error marker — so unknown
    // tokens degrade gracefully to plain text instead of vanishing or
    // crashing. This is also exactly the behavior that makes the
    // LAMDA/LAMBDA mismatch above invisible at runtime: `[[LAMBDA]]` is
    // simply left as the literal string "[[LAMBDA]]" in whatever label the
    // user typed it into.
    return kTokenReplacements[key] ?? full;
  });
}