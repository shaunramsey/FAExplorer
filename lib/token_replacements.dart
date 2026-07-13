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

  r'\0': '∅',
  // Greek lowercase
  'ALPHA': 'α', 'BETA': 'β', 'GAMMA': 'γ', 'ZETA': 'ζ', 'ETA': 'η',
  'THETA': 'θ', 'IOTA': 'ι', 'KAPPA': 'κ','LAMBDA': 'λ','DELTA': 'δ',
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
  'CHECK': '✓','X': '✗', 'STAR': '★', 'HEART': '♥', 'BULLET': '•',
  'QUESTION': '?', 'ELLIPSIS': '…', 'COPY': '©', 'REGISTERED': '®',
  'TRADEMARK': '™', 'DEGREE': '°',
  // PARAGRAPH and PILCROW below are two different key spellings for the
  // *same* character (¶ is formally called a "pilcrow"). Not a bug — both
  // are intentionally kept so either word works as the token name
  'PARAGRAPH': '¶', 'SECTION': '§',
  'CURRENCY': '¤', 'PILCROW': '¶',

  // Emoji
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
/// unchanged, brackets and all — see the `?? full` fallback below. 
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
    // (including the leading backslash if present, group(0) always
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
      return text.characters.map((ch) => ch == ' ' ? ch : '$ch\u0338').join();
    }

    // Plain lookup path: look the (trimmed, case-sensitive) key up in the
    // replacement table. If it's not found, `?? full` falls back to
    // returning the *entire original match* unchanged (brackets included)
    // rather than e.g. an empty string or an error marker
    return kTokenReplacements[key] ?? full;
  });
}