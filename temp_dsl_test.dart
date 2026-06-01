import 'dart:io';
import 'lib/dsl_code.dart';
import 'lib/models.dart';
void main() {
  final tests = [
    r'aaR\nXXR',
    r'\\0\\0R',
    r'\\0\\0R'.replaceAll(r'\\', r'\\'),
  ];
  for (final raw in tests) {
    print('raw: ' + raw);
    final escaped = DslCodec._escapeDsl(raw); // won't compile if private, need workaround
    print('escaped: ' + escaped);
  }
}
