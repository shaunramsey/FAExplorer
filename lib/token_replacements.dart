/// Shared symbol-substitution table and text parser used by nodes, lines,
/// start arrows, and the simulator.  A single source of truth replaces the
/// three identical copies that previously lived in node.dart, line.dart, and
/// start_arrow.dart.
library token_replacements;

// ─────────────────────────────────────────────────────────────────────────────
//  REPLACEMENT TABLE
// ─────────────────────────────────────────────────────────────────────────────

const Map<String, String> kTokenReplacements = {
  // Control
  r'\0': '∅',

  // Greek lowercase
  'ALPHA': 'α', 'BETA': 'β', 'GAMMA': 'γ', 'ZETA': 'ζ', 'ETA': 'η',
  'THETA': 'θ', 'IOTA': 'ι', 'KAPPA': 'κ', 'LAMDA': 'λ', 'DELTA': 'δ',
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
  'CHECK': '✓', 'X': '✗', 'STAR': '★', 'HEART': '♥', 'BULLET': '•',
  'QUESTION': '?', 'ELLIPSIS': '…', 'COPY': '©', 'REGISTERED': '®',
  'TRADEMARK': '™', 'DEGREE': '°', 'PARAGRAPH': '¶', 'SECTION': '§',
  'CURRENCY': '¤', 'PILCROW': '¶',

  // Emoji / dingbats
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
String parseTokenText(String input) {
  return input.replaceAllMapped(RegExp(r'\\?\[\[(.*?)\]\]'), (match) {
    final full = match.group(0)!;

    // Escaped: \[[KEY]] → [[KEY]]
    if (full.startsWith(r'\')) return full.substring(1);

    final key = (match.group(1) ?? '').trim();

    // Strikethrough overlay: [[/word]]
    if (key.startsWith('/')) {
      final text = key.substring(1);
      return text.runes.map((ch) => ch == 32 ? String.fromCharCode(ch) : '${String.fromCharCode(ch)}\u0338').join();
    }

    return kTokenReplacements[key] ?? full;
  });
}