part of 'inputs.dart';

/// `POST /template-folders` — `{name, order?}`.
class TemplateFolderCreateIn {
  final String name;
  final int order;

  const new _({required this.name, required this.order});

  static Future<TemplateFolderCreateIn> fromRequest(Request req) async {
    final json = await req.json();
    return TemplateFolderCreateIn._(
      name: json.folderName(),
      order: json.folderOrder(),
    );
  }

  TemplateFolder get folder => TemplateFolder(name: name, order: order);
}

/// `PUT /template-folders/:folderId` — `{name, order?}`. A full replace of the
/// two things a folder has; the templates inside are moved by updating the
/// templates, not the folder.
class TemplateFolderUpdateIn {
  final String name;
  final int order;

  const new _({required this.name, required this.order});

  static Future<TemplateFolderUpdateIn> fromRequest(Request req) async {
    final json = await req.json();
    return TemplateFolderUpdateIn._(
      name: json.folderName(),
      order: json.folderOrder(),
    );
  }

  TemplateFolder get folder => TemplateFolder(name: name, order: order);
}

extension on Map<String, dynamic> {
  /// Folder names are trimmed here rather than in the database so that what the
  /// uniqueness index sees is what the user will be shown.
  String folderName() {
    return switch (this['name']) {
      final String n when n.trim().isNotEmpty && n.trim().length <= 80 => n.trim(),
      _ => throw const BadRequest(reason: 'name must be a non-empty string (max 80 chars)'),
    };
  }

  int folderOrder() {
    return switch (this['order']) {
      null => 0,
      final num o when o >= 0 => o.toInt(),
      _ => throw const BadRequest(reason: 'order must be a number no less than 0'),
    };
  }
}
