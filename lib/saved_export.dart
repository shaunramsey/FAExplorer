enum SavedExportType { graph, blackBox }

class SavedExport {
  String name;
  String dsl;
  SavedExportType type;
  String blackBoxDescription;

  SavedExport({
    required this.name,
    required this.dsl,
    this.type = SavedExportType.graph,
    this.blackBoxDescription = '',
  });

  bool get isBlackBox => type == SavedExportType.blackBox;
}
