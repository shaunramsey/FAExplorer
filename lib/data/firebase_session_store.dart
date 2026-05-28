import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../preferences_store.dart';
import '../saved_export.dart';
import 'automata_session_store.dart';

/// Persists workspace data under `users/{uid}/workspace/main` in Firestore.
class FirebaseSessionStore implements AutomataSessionStore {
  FirebaseSessionStore({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  DocumentReference<Map<String, dynamic>>? get _doc {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return null;
    return _firestore.collection('users').doc(uid).collection('workspace').doc('main');
  }

  @override
  Future<PersistedSnapshot> load() async {
    final doc = _doc;
    if (doc == null) return const PersistedSnapshot();

    final snap = await doc.get();
    if (!snap.exists) return const PersistedSnapshot();

    final data = snap.data();
    if (data == null) return const PersistedSnapshot();

    return PersistedSnapshot(
      graphDsl: data['graphDsl'] as String?,
      savedExports: _decodeExports(data['savedExports']),
      showSimulator: data['showSimulator'] as bool? ?? true,
      showHelpOverlay: data['showHelpOverlay'] as bool? ?? false,
      simInput: data['simInput'] as String? ?? '',
      simStep: (data['simStep'] as num?)?.toInt() ?? -1,
    );
  }

  @override
  Future<void> save(PersistedSnapshot snapshot) async {
    final doc = _doc;
    if (doc == null) return;

    await doc.set(
      {
        'graphDsl': snapshot.graphDsl ?? '',
        'savedExports': snapshot.savedExports
            .map(
              (e) => {
                'name': e.name,
                'dsl': e.dsl,
                'type': e.type.name,
                'blackBoxDescription': e.blackBoxDescription,
              },
            )
            .toList(),
        'showSimulator': snapshot.showSimulator,
        'showHelpOverlay': snapshot.showHelpOverlay,
        'simInput': snapshot.simInput,
        'simStep': snapshot.simStep,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  static List<SavedExport> _decodeExports(dynamic raw) {
    if (raw is! List) return [];
    return [
      for (final item in raw)
        if (item is Map)
          SavedExport(
            name: item['name']?.toString() ?? 'Export',
            dsl: item['dsl']?.toString() ?? '',
            type: item['type']?.toString() == SavedExportType.blackBox.name
                ? SavedExportType.blackBox
                : SavedExportType.graph,
            blackBoxDescription:
                item['blackBoxDescription']?.toString() ?? '',
          ),
    ];
  }
}
