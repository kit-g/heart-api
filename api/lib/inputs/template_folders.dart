part of 'inputs.dart';

/// `POST /template-folders` — `{name, order?}`.
class TemplateFolderCreateIn {
  final String name;
  final int order;

  const TemplateFolderCreateIn._({required this.name, required this.order});

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

  const TemplateFolderUpdateIn._({required this.name, required this.order});

  static Future<TemplateFolderUpdateIn> fromRequest(Request req) async {
    final json = await req.json();
    return TemplateFolderUpdateIn._(
      name: json.folderName(),
      order: json.folderOrder(),
    );
  }

  TemplateFolder get folder => TemplateFolder(name: name, order: order);
}

/// `GET /templates?cursor=&limit=&folder=` — the existing page query plus an
/// optional folder filter.
///
/// `folder=<uuid>` lists that folder; the literal `folder=none` lists the
/// templates in no folder at all. Omitting it lists everything the user owns,
/// which is what the app has always received.
class TemplateListQuery {
  static const unfiled = 'none';

  final PageQuery page;
  final String? folderId;
  final bool unfiledOnly;

  const TemplateListQuery._({required this.page, required this.folderId, required this.unfiledOnly});

  static TemplateListQuery fromRequest(Request req) {
    final folder = req.url.queryParameters.stringOrNull('folder');
    return TemplateListQuery._(
      page: PageQuery.fromRequest(req),
      folderId: folder == unfiled ? null : folder,
      unfiledOnly: folder == unfiled,
    );
  }
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
