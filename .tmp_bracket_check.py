from pathlib import Path
text = Path('lib/study_mode_screen.dart').read_text(encoding='utf-8')
start = text.index('  @override\n  Widget build(BuildContext context) {')
end = text.index('}\n\n// ─────────────────────────────────────────────────────────────────────────────', start)
segment = text[start:end]
stack = []
for i, ch in enumerate(segment, start+1):
    if ch in '({[':
        stack.append((ch, i))
    elif ch in ')}]':
        if not stack:
            print('unmatched close', ch, 'at', i)
            break
        o, pos = stack.pop()
        if (o, ch) not in [('(', ')'), ('[', ']'), ('{', '}')]:
            print('mismatch', o, 'at', pos, 'with', ch, 'at', i)
            break
else:
    print('stack size', len(stack))
    if stack:
        for o, pos in stack[-20:]:
            print('unmatched open', o, 'at', pos)
