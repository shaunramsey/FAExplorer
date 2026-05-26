import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

class MarkdownFileScreen extends StatefulWidget {
  final String title;
  final String assetPath;

  const MarkdownFileScreen({super.key, required this.title, required this.assetPath});

  @override
  State<MarkdownFileScreen> createState() => _MarkdownFileScreenState();
}

class _MarkdownFileScreenState extends State<MarkdownFileScreen> {
  String _content = 'Loading...';

  @override
  void initState() {
    super.initState();
    _loadFile();
  }

  Future<void> _loadFile() async {
    try {
      final text = await rootBundle.loadString(widget.assetPath);
      setState(() => _content = text);
    } catch (e) {
      setState(() => _content = 'Failed to load ${widget.assetPath}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: SelectableText(_content, style: GoogleFonts.courierPrime(fontSize: 16)),
      ),
    );
  }
}
