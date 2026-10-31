// The shapes of what `/me` answers, generated from the `toMap()`s that write
// them, and checked against them at runtime.
//
// Reads each declared route of `meRoutes` (lib/routes/me_index.dart), the
// model its handler returns, and that model's `toMap()`: a key of the map
// literal is a property, its value's static type is the property's shape,
// `?value` and `if` make it optional, a nested `toMap()` is a shape of its
// own. What it cannot type (a raw map, a spread of one, a value built
// elsewhere) is a hole, and a hole fails the run unless
// lib/models/shape_overrides.dart says it by hand.
//
//   dart run tool/openapi/shapes.dart   (from api/; `make openapi` runs it)
//
// writes lib/models/shapes.g.dart, which is gitignored like the card scripts.

import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/session.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';

const generatedPath = 'lib/models/shapes.g.dart';
const overridesPath = 'lib/models/shape_overrides.dart';
const routesPath = 'lib/routes/me_index.dart';

Future<void> main() async {
  final api = Directory.current.absolute.path;
  final result = await generate(api);
  if (result.errors.isNotEmpty) {
    stderr.writeln('${result.errors.length} shapes the generator cannot read; say them in $overridesPath:');
    for (final error in result.errors) {
      stderr.writeln('  $error');
    }
    exitCode = 1;
    return;
  }
  final target = File('$api/$generatedPath');
  target.writeAsStringSync(result.source);
  stdout.writeln('wrote $generatedPath: ${result.objects} shapes, ${result.overridden} overridden');
}

/// The generated file's formatted source, or what stopped it.
typedef Generated = ({String source, List<String> errors, int objects, int overridden});

Future<Generated> generate(String api) async {
  final collection = AnalysisContextCollection(includedPaths: ['$api/lib']);
  final session = collection.contextFor('$api/$routesPath').currentSession;
  final generator = _Generator(session, api);
  await generator.readOverrides();
  final roots = await generator.roots();
  final unformatted = generator.emit(roots);
  if (generator.errors.isNotEmpty) {
    return (source: '', errors: generator.errors, objects: 0, overridden: 0);
  }
  return (
    source: await _format(api, unformatted),
    errors: const <String>[],
    objects: generator.emitted,
    overridden: generator.used.length,
  );
}

/// `dart format` with the package's own settings: the file is written under
/// the package so the formatter finds its analysis_options.
Future<String> _format(String api, String source) async {
  final scratch = Directory('$api/.dart_tool/openapi')..createSync(recursive: true);
  final file = File('${scratch.path}/shapes.g.dart')..writeAsStringSync(source);
  final result = await Process.run(Platform.resolvedExecutable, ['format', file.path]);
  if (result.exitCode != 0) throw StateError('dart format failed:\n${result.stderr}\n$source');
  return file.readAsStringSync();
}

// --------------------------------------------------------------------- shapes

/// What the generator knows of a value: a schema in the making, written out
/// as the `Shape` expression that describes it.
sealed class S {
  const new();
}

final class Prim extends S {
  final String dart;

  const new(this.dart);
}

final class EnumS extends S {
  final InterfaceElement element;
  final String accessor;

  const new(this.element, this.accessor);
}

final class ListS extends S {
  final S items;

  const new(this.items);
}

final class MapOfS extends S {
  final S values;

  const new(this.values);
}

final class NullS extends S {
  final S inner;

  const new(this.inner);
}

final class Ref extends S {
  final Obj obj;

  const new(this.obj);
}

final class Hole extends S {
  final String reason;
  final String where;

  const new(this.reason, this.where);
}

/// A record of positions, for `list.indexed`: only ever destructured.
final class Tuple extends S {
  final List<S> fields;

  const new(this.fields);
}

/// The `null` literal: only ever one side of a union.
final class NullLit extends S {
  const new();
}

final class Over extends S {
  final String key;

  const new(this.key);
}

class F {
  final S shape;
  final bool required;
  final String? description;

  const new(this.shape, {required this.required, this.description});
}

/// An object: a model's `toMap()` ([model] set) or a map literal written
/// inline. [hint] names it, and keys its overrides.
class Obj {
  final String hint;
  InterfaceElement? model;
  final fields = <String, F>{};
  String? open;
  String? description;
  String? name;

  new(this.hint, {this.model});

  String get key =>
      [for (final MapEntry(:key, :value) in fields.entries) '$key:${value.required}:${_key(value.shape)}'].join(',');
}

String _key(S s) => switch (s) {
  Prim(:final dart) => dart,
  EnumS(:final element, :final accessor) => '${element.name}.$accessor',
  ListS(:final items) => '[${_key(items)}]',
  MapOfS(:final values) => '{${_key(values)}}',
  NullS(:final inner) => '${_key(inner)}?',
  Ref(:final obj) => '#${identityHashCode(obj)}',
  Hole(:final reason) => 'hole($reason)',
  Tuple(:final fields) => '(${fields.map(_key).join(',')})',
  NullLit() => 'null',
  Over(:final key) => 'over($key)',
};

S nullable(S s) => switch (s) {
  NullS() || NullLit() || Hole() => s,
  _ => NullS(s),
};

S nonNull(S s) => switch (s) {
  NullS(:final inner) => inner,
  _ => s,
};

Hole? holeIn(S s) => switch (s) {
  Hole() => s,
  ListS(:final items) => holeIn(items),
  MapOfS(:final values) => holeIn(values),
  NullS(:final inner) => holeIn(inner),
  Tuple() => const Hole('a record, not a JSON value', '?'),
  NullLit() => const Hole('only ever null', '?'),
  Prim() || EnumS() || Ref() || Over() => null,
};

// ------------------------------------------------------------------ generator

class _Override {
  final bool shape;
  final String? description;
  final String? open;
  final Set<String> references;

  const new({required this.shape, this.description, this.open, this.references = const {}});
}

class _Generator {
  final AnalysisSession session;
  final String api;
  final errors = <String>[];
  final overrides = <String, _Override>{};
  final used = <String>{};
  final _libraries = <String, ResolvedLibraryResult>{};
  final _models = <InterfaceElement, Obj>{};
  final _literals = <AstNode, Obj>{};
  final _followed = <Element, S>{};
  final _following = <Element>{};

  /// The followed methods whose result is a list, which the file publishes
  /// under the method's name (`toWarnings` → `warningsShape`).
  final _lists = <String, S>{};
  final _imports = <String>{'package:heart/core/openapi/shape.dart'};
  var emitted = 0;

  new(this.session, this.api);

  // ------------------------------------------------------------- plumbing

  Future<AstNode?> declarationOf(Element element) async {
    final library = element.library;
    if (library == null || library.uri.scheme == 'dart') return null;
    final key = library.uri.toString();
    var resolved = _libraries[key];
    if (resolved == null) {
      final result = await session.getResolvedLibrary(library.firstFragment.source.fullName);
      if (result is! ResolvedLibraryResult) return null;
      _libraries[key] = resolved = result;
    }
    return resolved.getFragmentDeclaration(element.firstFragment)?.node;
  }

  Future<CompilationUnit> unit(String path) async {
    final result = await session.getResolvedUnit('$api/$path');
    if (result is! ResolvedUnitResult) throw StateError('cannot resolve $path');
    return result.unit;
  }

  String where(AstNode node) {
    final unit = node.root as CompilationUnit;
    final path = unit.declaredFragment?.source.fullName ?? '?';
    final line = unit.lineInfo.getLocation(node.offset).lineNumber;
    final package = path.contains('heart_models') ? 'heart_models/' : '';
    final short = path.contains('/lib/') ? path.substring(path.lastIndexOf('/lib/') + 1) : path;
    return '$package$short:$line';
  }

  // ------------------------------------------------------------ overrides

  Future<void> readOverrides() async {
    if (!File('$api/$overridesPath').existsSync()) return;
    final literal = _topLevel(await unit(overridesPath), 'shapeOverrides');
    for (final entry in literal.elements.cast<MapLiteralEntry>()) {
      final key = (entry.key as StringLiteral).stringValue!;
      final value = entry.value;
      final kind = RegExp(r'^(?:const\s+)?(?:ShapeOverride)?\.(shape|describe|open)\(')
          .firstMatch(value.toSource())?[1];
      final arguments = _firstArguments(value);
      String? named(String name) {
        for (final argument in arguments.whereType<NamedArgument>()) {
          if (argument.name.lexeme == name) return (argument.argumentExpression as StringLiteral).stringValue;
        }
        return null;
      }

      String? first() => switch (arguments.firstOrNull?.argumentExpression) {
        final StringLiteral literal => literal.stringValue,
        _ => null,
      };
      final references = <String>{};
      value.accept(_Visit(onIdentifier: (id) => id.name.endsWith('Shape') ? references.add(id.name) : null));
      overrides[key] = switch (kind) {
        'shape' => _Override(shape: true, description: named('description'), references: references),
        'describe' => _Override(shape: false, description: first()),
        'open' => _Override(shape: false, open: first()),
        _ => throw StateError('$overridesPath: $key is not .shape, .describe or .open'),
      };
    }
  }

  SetOrMapLiteral _topLevel(CompilationUnit unit, String name) {
    final variable = unit.declarations
        .whereType<TopLevelVariableDeclaration>()
        .expand((declaration) => declaration.variables.variables)
        .firstWhere((variable) => variable.name.lexeme == name);
    return variable.initializer as SetOrMapLiteral;
  }

  List<Argument> _firstArguments(AstNode node) {
    ArgumentList? found;
    node.accept(_Visit(onArguments: (list) => found ??= list));
    return found?.arguments.toList() ?? const [];
  }

  _Override? override(String key) {
    final found = overrides[key];
    if (found != null) used.add(key);
    return found;
  }

  // ---------------------------------------------------------------- roots

  /// The model each declared route answers, by its handler's return type: a
  /// `Paginated<T>` answers `T`s. A route whose reply is no model's (a file,
  /// a value nobody declares yet) is not the generator's.
  Future<List<Obj>> roots() async {
    final table = _topLevel(await unit(routesPath), 'meRoutes');
    final roots = <Obj>[];
    for (final entry in table.elements.cast<MapLiteralEntry>()) {
      final arguments = _firstArguments(entry.value);
      if (arguments.isEmpty) continue;
      final reply = arguments.whereType<NamedArgument>().where((argument) => argument.name.lexeme == 'reply');
      if (reply.any((argument) => RegExp(r'\.(unknown|download)\(').hasMatch(argument.toSource()))) continue;
      final handler = switch (arguments.first.argumentExpression) {
        final Identifier identifier => identifier.element,
        _ => null,
      };
      if (handler is! ExecutableElement) continue;
      var type = handler.returnType;
      if (type is InterfaceType && type.isDartAsyncFuture) type = type.typeArguments.first;
      if (type is InterfaceType && type.element.name == 'Paginated') type = type.typeArguments.first;
      if (type is InterfaceType && isModel(type)) roots.add(await model(type, entry));
    }
    return roots;
  }

  // ---------------------------------------------------------------- models

  bool isModel(InterfaceType type) =>
      type.element.name == 'Model' || type.allSupertypes.any((supertype) => supertype.element.name == 'Model');

  /// [type]'s `toMap()`, through a redirecting factory or the one class of its
  /// library that implements it (`Workout` is `_Workout`'s).
  Future<Obj> model(InterfaceType type, AstNode at) async {
    final element = type.element;
    if (_models[element] case final obj?) return obj;
    final obj = _models[element] = Obj(element.name!, model: element);
    // an API-owned model's doc is written for /me; a shared model's, for the app
    if (element.library.uri.toString().startsWith('package:heart/')) {
      obj.description = _sentence(element.documentationComment);
    }
    final method = await _toMap(element);
    final declaration = method == null ? null : await declarationOf(method);
    if (declaration is! MethodDeclaration) {
      obj.fields['?'] = F(Hole('no toMap() source for ${element.name}', where(at)), required: true);
      return obj;
    }
    final result = await returned(declaration.body, obj.hint, into: obj);
    if (obj.fields.isEmpty && result is Ref && result.obj != obj) _copy(result.obj, into: obj, optional: false);
    if (obj.fields.isEmpty && obj.open == null) {
      final hole = result is Hole
          ? result
          : Hole('toMap() of ${element.name} writes no key a literal shows', where(declaration));
      obj.fields['?'] = F(hole, required: true);
    }
    return obj;
  }

  Future<MethodElement?> _toMap(InterfaceElement element) async {
    MethodElement? concrete(InterfaceElement element) =>
        switch (element.lookUpConcreteMethod('toMap', element.library)) {
          final method? when !method.isAbstract => method,
          _ => null,
        };
    if (concrete(element) case final method?) return method;
    for (final constructor in element.constructors) {
      if (constructor.redirectedConstructor case final redirected?) {
        if (concrete(redirected.enclosingElement) case final method?) return method;
      }
    }
    final implementations = [
      for (final candidate in element.library.classes)
        if (candidate != element && candidate.allSupertypes.any((supertype) => supertype.element == element)) candidate,
    ];
    return implementations.length == 1 ? concrete(implementations.single) : null;
  }

  // ----------------------------------------------------------- expressions

  Future<S> returned(FunctionBody body, String hint, {Obj? into}) async {
    if (body is ExpressionFunctionBody) return expr(body.expression, hint, into: into);
    final returns = <ReturnStatement>[];
    body.accept(_Visit(onReturn: returns.add));
    final shapes = [
      for (final statement in returns)
        if (statement.expression case final expression?) await expr(expression, hint, into: into),
    ];
    if (shapes.isEmpty) return Hole('returns nothing', where(body));
    return union(shapes, body);
  }

  Future<S> expr(Expression e, String hint, {Obj? into}) async {
    switch (e) {
      case ParenthesizedExpression(:final expression):
        return expr(expression, hint, into: into);
      case SetOrMapLiteral() when e.isMap:
        return Ref(await mapLiteral(e, hint, into: into));
      case ListLiteral(:final elements):
        if (elements.isEmpty) return ListS(Hole('an empty list literal', where(e)));
        return ListS(union([for (final element in elements) await collectionElement(element, _singular(hint))], e));
      case StringLiteral():
        return const Prim('.string');
      case IntegerLiteral():
        return const Prim('.integer');
      case DoubleLiteral():
        return const Prim('.number');
      case BooleanLiteral():
        return const Prim('.boolean');
      case NullLiteral():
        return const NullLit();
      // `validated ? 1 : 0`: a boolean the wire writes as a number
      case ConditionalExpression(
            thenExpression: IntegerLiteral(value: 1 || 0) && final one,
            elseExpression: IntegerLiteral(value: 1 || 0) && final other,
          )
          when one.value != other.value:
        return const Prim('.flag');
      case ConditionalExpression(:final thenExpression, :final elseExpression):
        return union([await expr(thenExpression, hint), await expr(elseExpression, hint)], e);
      case SwitchExpression(:final cases):
        return union([for (final each in cases) await expr(each.expression, hint)], e);
      case BinaryExpression(:final leftOperand, :final rightOperand) when e.operator.lexeme == '??':
        return union([nonNull(await expr(leftOperand, hint)), await expr(rightOperand, hint)], e);
      case MethodInvocation():
        return invocation(e, hint, into: into);
      case PrefixedIdentifier(:final prefix, :final identifier):
        return property(e, prefix, identifier, hint);
      case PropertyAccess(:final realTarget, :final propertyName):
        return property(e, realTarget, propertyName, hint);
      case SimpleIdentifier():
        return identifier(e, hint, into: into);
      case AsExpression(:final expression):
        return expr(expression, hint, into: into);
      default:
        return byType(e.staticType, e, hint);
    }
  }

  /// A value by its static type alone.
  Future<S> byType(DartType? type, AstNode at, String hint) async {
    if (type == null || type is DynamicType) return Hole('a dynamic value', where(at));
    if (type.nullabilitySuffix == NullabilitySuffix.question && type is InterfaceType) {
      return nullable(await byType(type.element.thisType, at, hint).then((s) => _withArguments(s, type, at, hint)));
    }
    if (type is RecordType) return Hole('a record', where(at));
    if (type is! InterfaceType) return Hole('a $type', where(at));
    if (type.isDartCoreString) return const Prim('.string');
    if (type.isDartCoreInt) return const Prim('.integer');
    if (type.isDartCoreDouble || type.isDartCoreNum) return const Prim('.number');
    if (type.isDartCoreBool) return const Prim('.boolean');
    if (type.isDartCoreObject) return Hole('an Object', where(at));
    if (type.isDartCoreList || type.isDartCoreIterable || type.isDartCoreSet) {
      return ListS(await byType(type.typeArguments.first, at, _singular(hint)));
    }
    if (type.isDartCoreMap) {
      final value = type.typeArguments.last;
      if (_loose(value) || !type.typeArguments.first.isDartCoreString) {
        return Hole('a map of ${type.getDisplayString()}', where(at));
      }
      return MapOfS(await byType(value, at, hint));
    }
    if (type.element.name == 'DateTime') return Hole('a DateTime, which jsonEncode throws on', where(at));
    if (type.element is EnumElement) return Hole('an enum, which jsonEncode throws on', where(at));
    if (isModel(type)) return Hole('a ${type.element.name}, not its toMap()', where(at));
    return Hole('a ${type.element.name}', where(at));
  }

  // a nullable generic (`List<String>?`) keeps its type arguments
  Future<S> _withArguments(S s, InterfaceType type, AstNode at, String hint) async {
    if (type.typeArguments.isEmpty) return s;
    return byType(type.element.instantiate(typeArguments: type.typeArguments, nullabilitySuffix: .none), at, hint);
  }

  bool _loose(DartType type) => type is DynamicType || type.isDartCoreObject || type.isDartCoreMap;

  /// A type a map literal could hide behind: read its source, not its type.
  bool _shapeless(DartType? type) =>
      type == null ||
      _loose(type) ||
      (type is InterfaceType && (type.isDartCoreList || type.isDartCoreIterable) && _loose(type.typeArguments.first));

  Future<S> property(Expression e, Expression target, SimpleIdentifier name, String hint) async {
    final targetType = target.staticType;
    // `category.value`, `unit.name`: an enum by its wire word
    if (targetType is InterfaceType && targetType.element is EnumElement && e.staticType?.isDartCoreString == true) {
      _import(targetType.element);
      final s = EnumS(targetType.element, name.name);
      return targetType.nullabilitySuffix == NullabilitySuffix.question ? nullable(s) : s;
    }
    if (name.name == 'indexed') {
      final items = switch (await expr(target, hint)) {
        ListS(:final items) => items,
        final other => other,
      };
      return ListS(Tuple([const Prim('.integer'), items]));
    }
    return follow(e, name.element, hint);
  }

  Future<S> identifier(SimpleIdentifier e, String hint, {Obj? into}) async {
    final element = e.element;
    if (!_shapeless(e.staticType)) return follow(e, element, hint);
    if (element is LocalVariableElement) {
      if (await _local(e, element, hint, into: into) case final s?) return s;
    }
    return follow(e, element, hint);
  }

  /// A local that holds a map: its initializer, or what the pattern that
  /// declares it takes apart (`for (final (order, each) in list.indexed)`).
  Future<S?> _local(AstNode at, LocalVariableElement element, String hint, {Obj? into}) async {
    final body = at.thisOrAncestorOfType<FunctionBody>();
    Expression? initializer;
    DeclaredVariablePattern? pattern;
    body?.accept(
      _Visit(
        onVariable: (variable) {
          if (variable.declaredFragment?.element == element) initializer = variable.initializer;
        },
        onPattern: (node) {
          if (node.declaredFragment?.element == element) pattern = node;
        },
      ),
    );
    if (initializer case final initializer?) {
      if (_filledLater(body!, element) case final at?) {
        return Hole('`${element.name}` gets keys after it is built, which only a literal shows', where(at));
      }
      return expr(initializer, hint, into: into);
    }
    final declared = pattern;
    if (declared == null) return null;
    final parts = declared.thisOrAncestorOfType<ForEachPartsWithPattern>();
    final field = declared.parent;
    if (parts == null || field is! PatternField || field.parent is! RecordPattern) return null;
    final position = (field.parent as RecordPattern).fields.indexOf(field);
    return switch (await expr(parts.iterable, hint)) {
      ListS(items: Tuple(:final fields)) when position < fields.length && field.name == null => fields[position],
      _ => null,
    };
  }

  /// Where [body] adds to the map [element] holds after building it
  /// (`map['id'] = …`, `map.addAll(…)`, a cascade), if it does.
  AstNode? _filledLater(FunctionBody body, LocalVariableElement element) {
    bool isIt(Expression? e) => e is SimpleIdentifier && e.element == element;
    AstNode? found;
    body.accept(
      _Visit(
        onAssignment: (node) {
          if (node.leftHandSide case IndexExpression(:final target) when isIt(target)) found ??= node;
        },
        onInvocation: (node) {
          const adds = {'addAll', 'addEntries', 'putIfAbsent', 'update', 'updateAll', 'remove', 'removeWhere', 'clear'};
          if (adds.contains(node.methodName.name) && isIt(node.realTarget)) found ??= node;
        },
      ),
    );
    return found;
  }

  /// A getter or method whose value a map literal could hide behind: read
  /// its body. Everything else goes by its type.
  Future<S> follow(Expression e, Element? element, String hint) async {
    final type = e.staticType;
    if (_shapeless(type) && element is ExecutableElement && !_following.contains(element)) {
      if (_followed[element] case final s?) return s;
      final declaration = await declarationOf(element);
      final body = switch (declaration) {
        MethodDeclaration(:final body) => body,
        FunctionDeclaration(:final functionExpression) => functionExpression.body,
        _ => null,
      };
      if (body != null && body is! EmptyFunctionBody) {
        _following.add(element);
        try {
          final named = _hintFor(element, hint);
          var s = await returned(body, named);
          if (type?.nullabilitySuffix == NullabilitySuffix.question) s = nullable(s);
          if (s is ListS && element.enclosingElement is ExtensionElement) _lists[named] = s;
          return _followed[element] = s;
        } finally {
          _following.remove(element);
        }
      }
    }
    if (_shapeless(type)) {
      return Hole('${element?.name ?? e.toSource()} holds a ${type?.getDisplayString()} built elsewhere', where(e));
    }
    return byType(type, e, hint);
  }

  /// `WorkoutImage.toRow` → `WorkoutImageRow`, `toWarnings` (an extension's)
  /// → `Warnings`.
  String _hintFor(Element element, String hint) {
    final name = element.name ?? '';
    if (name == 'toMap') return hint;
    final base = name.startsWith('to') && name.length > 2 ? name.substring(2) : _pascal(name);
    return switch (element.enclosingElement) {
      final InterfaceElement owner => '${owner.name}$base',
      _ => base,
    };
  }

  Future<S> invocation(MethodInvocation e, String hint, {Obj? into}) async {
    final name = e.methodName.name;
    final target = e.realTarget;
    final nullableResult = e.staticType?.nullabilitySuffix == NullabilitySuffix.question;
    S maybe(S s) => nullableResult ? nullable(s) : s;
    final targetType = target?.staticType;
    if (name == 'toMap' && targetType is InterfaceType && isModel(targetType)) {
      return maybe(Ref(await model(targetType, e)));
    }
    if (name == 'toIso8601String') return maybe(const Prim('.isoString'));
    if (name == 'toString') return maybe(const Prim('.string'));
    if ((name == 'toList' || name == 'toSet') && target is MethodInvocation && target.methodName.name == 'map') {
      final function = target.argumentList.arguments.first.argumentExpression;
      if (function is FunctionExpression) return ListS(await returned(function.body, _singular(hint)));
      return ListS(Hole('a map over a tear-off', where(function)));
    }
    // heart_models' tolerant lists: the items this build read, with those it
    // couldn't put back where they were. The readable ones are the shape; an
    // unread one fails the check, as a key nobody declares would
    if (name == 'splice' && e.methodName.element?.library?.uri.toString().startsWith('package:heart_models/') == true) {
      return expr(e.argumentList.arguments.first.argumentExpression, hint);
    }
    return follow(e, e.methodName.element, hint);
  }

  Future<S> collectionElement(CollectionElement element, String hint) async {
    return switch (element) {
      Expression() => await expr(element, hint),
      ForElement(:final body) => await collectionElement(body, hint),
      IfElement(:final thenElement, :final elseElement) => union([
        await collectionElement(thenElement, hint),
        if (elseElement != null) await collectionElement(elseElement, hint),
      ], element),
      SpreadElement(:final expression) => switch (await expr(expression, hint)) {
        ListS(:final items) => items,
        final other => holeIn(other) ?? Hole('a spread of a non-list into a list', where(element)),
      },
      NullAwareElement(:final value) => nonNull(await expr(value, hint)),
      _ => Hole('a ${element.runtimeType}', where(element)),
    };
  }

  // ---------------------------------------------------------- map literals

  Future<Obj> mapLiteral(SetOrMapLiteral literal, String hint, {Obj? into}) async {
    if (_literals[literal] case final obj?) return obj;
    final obj = _literals[literal] = into ?? Obj(hint);
    for (final element in literal.elements) {
      await _entry(obj, element, optional: false);
    }
    return obj;
  }

  /// `if (x != null) 'k': x`: the key is there only with a value.
  bool _guards(Expression condition, CollectionElement then) {
    return condition is BinaryExpression &&
        condition.operator.lexeme == '!=' &&
        condition.rightOperand is NullLiteral &&
        then is MapLiteralEntry &&
        then.value.toSource() == condition.leftOperand.toSource();
  }

  Future<void> _entry(Obj obj, CollectionElement element, {required bool optional, bool present = false}) async {
    switch (element) {
      case MapLiteralEntry(:final key, :final value, :final valueQuestion):
        if (key is! StringLiteral) return _spreadHole(obj, 'a computed key `${key.toSource()}`', element);
        final name = key.stringValue!;
        var s = await expr(value, '${obj.hint}${_pascal(name)}');
        if (valueQuestion != null || present) {
          s = nonNull(s);
        } else if (value.staticType?.nullabilitySuffix == NullabilitySuffix.question) {
          s = nullable(s);
        }
        _field(obj, name, s, required: !optional && valueQuestion == null, description: _docOf(value));
      case IfElement(:final expression, :final thenElement, :final elseElement):
        await _entry(obj, thenElement, optional: true, present: _guards(expression, thenElement));
        if (elseElement != null) await _entry(obj, elseElement, optional: true);
      case SpreadElement(:final expression, :final isNullAware):
        switch (await expr(expression, obj.hint)) {
          case Ref(obj: final spread):
            _copy(spread, into: obj, optional: optional || isNullAware);
          case final other:
            _spreadHole(obj, 'a spread of ${holeIn(other)?.reason ?? 'a map with no known keys'}', element);
        }
      case ForElement(:final forLoopParts, :final body):
        if (await _enumKeys(obj, forLoopParts, body)) return;
        _spreadHole(obj, 'keys computed in a for loop', element);
      default:
        _spreadHole(obj, 'a ${element.runtimeType}', element);
    }
  }

  /// `for (final MapEntry(:key, :value) in ranges.entries) key.value: …`:
  /// keys that are an enum's wire words, each optional.
  Future<bool> _enumKeys(Obj obj, ForLoopParts parts, CollectionElement body) async {
    if (parts is! ForEachParts || body is! MapLiteralEntry) return false;
    final (target, accessor) = switch (body.key) {
      PrefixedIdentifier(:final prefix, :final identifier) => (prefix, identifier.name),
      PropertyAccess(:final realTarget, :final propertyName) => (realTarget, propertyName.name),
      _ => (null, null),
    };
    final type = target?.staticType;
    if (type is! InterfaceType || type.element is! EnumElement) return false;
    final words = [
      for (final constant in (type.element as EnumElement).constants)
        accessor == 'name' && constant.computeConstantValue()?.getField('name') == null
            ? constant.name
            : constant.computeConstantValue()?.getField(accessor!)?.toStringValue(),
    ];
    if (words.contains(null)) return false;
    var s = await expr(body.value, obj.hint);
    if (body.valueQuestion != null) s = nonNull(s);
    for (final word in words) {
      _field(obj, word!, s, required: false);
    }
    return true;
  }

  void _copy(Obj spread, {required Obj into, required bool optional}) {
    for (final MapEntry(:key, :value) in spread.fields.entries) {
      into.fields[key] = F(value.shape, required: value.required && !optional, description: value.description);
    }
    into.open ??= spread.open;
  }

  void _field(Obj obj, String name, S s, {required bool required, String? description}) {
    final key = '${obj.hint}.$name';
    final override = this.override(key);
    if (override?.shape == true) s = Over(key);
    obj.fields[name] = F(s, required: required, description: override?.description ?? description);
  }

  void _spreadHole(Obj obj, String reason, AstNode at) {
    final key = '${obj.hint}.*';
    if (override(key)?.open case final why?) {
      obj.open = why;
    } else {
      obj.fields['*'] = F(Hole(reason, where(at)), required: false);
    }
  }

  // ----------------------------------------------------------------- unions

  S union(List<S> shapes, AstNode at) {
    final distinct = <String, S>{for (final s in shapes) _key(s): s}.values.toList();
    if (distinct.length == 1) return distinct.single;
    if (distinct.any((s) => s is NullLit || s is NullS)) {
      final rest = [
        for (final s in distinct)
          if (s is! NullLit) nonNull(s),
      ];
      return rest.isEmpty ? const NullLit() : nullable(union(rest, at));
    }
    if (distinct.whereType<Hole>().firstOrNull case final hole?) return hole;
    // an int where a double could be: JSON has one kind of number
    if (distinct.every((s) => s is Prim && (s.dart == '.integer' || s.dart == '.number'))) return const Prim('.number');
    if (distinct.every((s) => s is Ref && s.obj.model == null)) {
      final objects = [for (final s in distinct) (s as Ref).obj];
      if (<String>{for (final obj in objects) obj.key}.length == 1) return distinct.first;
      final merged = Obj(objects.first.hint);
      for (final obj in objects) {
        for (final MapEntry(:key, :value) in obj.fields.entries) {
          final inAll = objects.every((other) => other.fields[key]?.required ?? false);
          final existing = merged.fields[key];
          merged.fields[key] = F(
            existing == null ? value.shape : union([existing.shape, value.shape], at),
            required: inAll,
            description: existing?.description ?? value.description,
          );
        }
        merged.open ??= obj.open;
      }
      return Ref(merged);
    }
    return Hole('values of different shapes (${distinct.map(_key).join(' | ')})', where(at));
  }

  // ----------------------------------------------------------- descriptions

  /// The first sentence of the doc comment on what a value reads, or on the
  /// member it overrides (an implementation's field is documented on its
  /// interface's getter).
  String? _docOf(Expression value) {
    final element = switch (value) {
      SimpleIdentifier(:final element) => element,
      PrefixedIdentifier(:final identifier) => identifier.element,
      PropertyAccess(:final propertyName) => propertyName.element,
      _ => null,
    };
    if (element == null) return null;
    if (_sentence(_documentation(element)) case final doc?) return doc;
    final name = element.name;
    final owner = element.enclosingElement;
    if (name == null || owner is! InterfaceElement) return null;
    for (final supertype in owner.allSupertypes) {
      final member = supertype.element.getGetter(name) ?? supertype.element.getField(name);
      if (_sentence(member == null ? null : _documentation(member)) case final doc?) return doc;
    }
    return null;
  }

  String? _documentation(Element element) => element.library?.uri.scheme == 'dart'
      ? null
      : switch (element) {
          GetterElement(:final variable) => element.documentationComment ?? variable.documentationComment,
          _ => element.documentationComment,
        };

  String? _sentence(String? comment) {
    if (comment == null) return null;
    final text = comment
        .split('\n')
        .map((line) => line.trim().replaceFirst(RegExp(r'^///\s?'), ''))
        .takeWhile((line) => line.isNotEmpty)
        .join(' ')
        .replaceAll(RegExp(r' \(heart-\w+#\d+\)'), '')
        .replaceAllMapped(RegExp(r'\[(\w+)(?:\.(\w+))?\]'), (m) => '`${m[2] ?? m[1]}`');
    // a sentence ends at a full stop, not at `e.g.`
    final end = RegExp(r'(?<!\be\.g|\bi\.e)\.(\s|$)').firstMatch(text);
    final sentence = (end == null ? text : text.substring(0, end.start)).trim();
    return sentence.isEmpty ? null : '$sentence.';
  }

  // ------------------------------------------------------------------- emit

  String emit(List<Obj> roots) {
    final reachable = <Obj>[];
    final names = <String, Obj>{};
    void visit(Obj obj, [Obj? parent]) {
      if (reachable.contains(obj)) return;
      final base = obj.model?.name ?? obj.hint;
      var name = base;
      // a model written two ways takes the name of what holds the second
      if (names[name] != null && parent?.name != null) name = '${parent!.name}$base';
      for (var n = 2; names[name] != null && names[name] != obj; n++) {
        name = '$base$n';
      }
      obj.name = name;
      names[name] = obj;
      reachable.add(obj);
      if (obj.model case final model?) _import(model);
      for (final field in obj.fields.values) {
        for (final child in _objectsIn(field.shape)) {
          visit(child, obj);
        }
      }
    }

    roots.forEach(visit);
    _lists.values.expand(_objectsIn).forEach(visit);
    // the models an override names (`.nullable(targetRangeShape)`)
    for (final MapEntry(:key, :value) in overrides.entries) {
      if (!used.contains(key)) continue;
      for (final reference in value.references) {
        final named = _models.values.where((obj) => _var(obj.model!.name!) == reference);
        named.forEach(visit);
      }
    }

    for (final obj in reachable) {
      for (final MapEntry(key: name, value: field) in obj.fields.entries) {
        if (holeIn(field.shape) case final hole?) {
          errors.add('${name == '*' ? '${obj.hint}.*' : '${obj.hint}.$name'}: ${hole.reason} (${hole.where})');
        }
      }
    }
    for (final key in overrides.keys) {
      if (!used.contains(key)) errors.add('$key: an override nothing reads any more; remove it');
    }
    if (errors.isNotEmpty) return '';

    emitted = reachable.length;
    final out = StringBuffer()
      ..writeln('// GENERATED by tool/openapi/shapes.dart from the toMap()s of the models')
      ..writeln('// the declared /me routes answer. Do not edit: change the toMap(), or')
      ..writeln('// $overridesPath, and run `dart run tool/openapi/shapes.dart`.')
      ..writeln();
    final imports = {
      ..._imports,
      if (used.any((key) => overrides[key]!.shape)) 'package:heart/models/shape_overrides.dart',
    };
    for (final uri in imports.toList()..sort()) {
      out.writeln("import '$uri';");
    }
    for (final obj in reachable) {
      out
        ..writeln()
        ..writeln(_declaration(obj));
    }
    for (final MapEntry(:key, :value) in _lists.entries) {
      if (value case ListS(items: Ref(:final obj)) when !reachable.contains(obj)) continue;
      out
        ..writeln()
        ..writeln('/// What `to$key()` writes.')
        ..writeln('final Shape<Iterable<Object?>> ${_var(key)} = ${_dart(value)};');
    }
    if (used.any((key) => overrides[key]!.shape)) {
      out
        ..writeln()
        ..writeln('Shape<Object?> _override(String key) => shapeOverrides[key]!.shape!;');
    }
    return out.toString();
  }

  Iterable<Obj> _objectsIn(S s) sync* {
    switch (s) {
      case Ref(:final obj):
        yield obj;
      case ListS(:final items):
        yield* _objectsIn(items);
      case MapOfS(:final values):
        yield* _objectsIn(values);
      case NullS(:final inner):
        yield* _objectsIn(inner);
      default:
    }
  }

  String _declaration(Obj obj) {
    final fields = StringBuffer();
    for (final MapEntry(key: name, value: field) in obj.fields.entries) {
      final shape = _dart(field.shape);
      final constant = field.shape is Prim;
      final arguments = [
        shape,
        if (field.description != null) _string(field.description!),
      ];
      fields.writeln(
        "  '$name': ${constant ? 'const ' : ''}.${field.required ? 'required' : 'optional'}(${arguments.join(', ')}),",
      );
    }
    final named = [
      if (obj.description case final description?) 'description: ${_string(description)}',
      if (obj.open != null) 'open: true',
    ];
    final why = obj.open == null ? '' : '/// Open: ${obj.open}\n';
    final tail = named.isEmpty ? '' : ', ${named.join(', ')},';
    return switch (obj.model) {
      final model? => "${why}final Shape<${model.name}> ${_var(obj.name!)} = .model('${obj.name}', {\n$fields}$tail);",
      null => "${why}final Shape<Object?> ${_var(obj.name!)} = .described('${obj.name}', {\n$fields}$tail);",
    };
  }

  String _dart(S s) => switch (s) {
    Prim(:final dart) => dart,
    EnumS(:final element, :final accessor) =>
      '.enumOf<${element.name}>(${element.name}.values, (value) => value.$accessor)',
    ListS(:final items) => '.list(${_dart(items)})',
    MapOfS(:final values) => '.mapOf(${_dart(values)})',
    NullS(:final inner) => '.nullable(${_dart(inner)})',
    Ref(:final obj) => _var(obj.name!),
    Over(:final key) => "_override('$key')",
    Hole() || Tuple() || NullLit() => throw StateError('not a JSON value: ${_key(s)}'),
  };

  void _import(InterfaceElement element) {
    final uri = element.library.uri.toString();
    _imports.add(uri.startsWith('package:heart_models/') ? 'package:heart_models/heart_models.dart' : uri);
  }
}

String _var(String name) => '${name[0].toLowerCase()}${name.substring(1)}Shape';

String _pascal(String name) => name.isEmpty ? name : '${name[0].toUpperCase()}${name.substring(1)}';

/// `images` → `image`, for the items of a list.
String _singular(String name) => name.endsWith('s') && !name.endsWith('ss') ? name.substring(0, name.length - 1) : name;

String _string(String text) => "'${text.replaceAll(r'\', r'\\').replaceAll("'", r"\'").replaceAll(r'$', r'\$')}'";

class _Visit extends RecursiveAstVisitor<void> {
  final void Function(ReturnStatement)? onReturn;
  final void Function(VariableDeclaration)? onVariable;
  final void Function(DeclaredVariablePattern)? onPattern;
  final void Function(ArgumentList)? onArguments;
  final void Function(SimpleIdentifier)? onIdentifier;
  final void Function(AssignmentExpression)? onAssignment;
  final void Function(MethodInvocation)? onInvocation;

  new({
    this.onReturn,
    this.onVariable,
    this.onPattern,
    this.onArguments,
    this.onIdentifier,
    this.onAssignment,
    this.onInvocation,
  });

  @override
  void visitAssignmentExpression(AssignmentExpression node) {
    onAssignment?.call(node);
    super.visitAssignmentExpression(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    onInvocation?.call(node);
    super.visitMethodInvocation(node);
  }

  @override
  void visitReturnStatement(ReturnStatement node) {
    onReturn?.call(node);
    super.visitReturnStatement(node);
  }

  // a nested closure's returns are not the enclosing body's
  @override
  void visitFunctionExpression(FunctionExpression node) {
    if (onReturn != null && node.parent is! FunctionDeclaration) return;
    super.visitFunctionExpression(node);
  }

  @override
  void visitFunctionDeclarationStatement(FunctionDeclarationStatement node) {
    if (onReturn != null) return;
    super.visitFunctionDeclarationStatement(node);
  }

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    onVariable?.call(node);
    super.visitVariableDeclaration(node);
  }

  @override
  void visitDeclaredVariablePattern(DeclaredVariablePattern node) {
    onPattern?.call(node);
    super.visitDeclaredVariablePattern(node);
  }

  @override
  void visitArgumentList(ArgumentList node) {
    onArguments?.call(node);
    super.visitArgumentList(node);
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    onIdentifier?.call(node);
    super.visitSimpleIdentifier(node);
  }
}
