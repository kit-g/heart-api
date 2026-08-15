import 'package:heart_models/heart_models.dart';

abstract interface class TemplateFoldersResponse implements Model {
  Iterable<TemplateFolder> get folders;

  factory({required Iterable<TemplateFolder> folders}) = _TemplateFoldersResponse.new;
}

class _TemplateFoldersResponse implements TemplateFoldersResponse {
  @override
  final Iterable<TemplateFolder> folders;

  new({required this.folders});

  @override
  Map<String, dynamic> toMap() {
    return {
      'folders': folders.map((each) => each.toMap()).toList(),
    };
  }
}

/// The result of assigning a folder: one share per template that went. Empty
/// when the folder was empty — assigning nothing is a no-op, not an error.
abstract interface class TemplateSharesResponse implements Model {
  Iterable<TemplateShare> get shares;

  factory({required Iterable<TemplateShare> shares}) = _TemplateSharesResponse.new;
}

class _TemplateSharesResponse implements TemplateSharesResponse {
  @override
  final Iterable<TemplateShare> shares;

  new({required this.shares});

  @override
  Map<String, dynamic> toMap() {
    return {
      'shares': shares.map((each) => each.toMap()).toList(),
    };
  }
}
