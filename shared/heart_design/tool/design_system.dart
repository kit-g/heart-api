/// Writes the Heart Design System artifact's files from `tokens.json`: its
/// `tokens.json` in the artifact's own format, beside the hand-written pages
/// in `artifact/` (the README, the logos' notes, the cover). Run from the
/// package root:
///
///     dart run tool/design_system.dart OUT_DIR [REF]
///
/// then publish `OUT_DIR/project/` to the artifact. The logos are uploads
/// the artifact's index names, not files here.
library;

import 'dart:convert';
import 'dart:io';

import 'generator.dart';

void main(List<String> arguments) {
  if (arguments.isEmpty) {
    stderr.writeln('usage: dart run tool/design_system.dart OUT_DIR [REF]');
    exit(64);
  }
  final out = Directory('${arguments.first}/project');
  final design = Design.parse(File('tokens.json').readAsStringSync());
  final ref = arguments.elementAtOrNull(1) ?? 'main';
  _write('${out.path}/tokens.json', '${const JsonEncoder.withIndent('  ').convert(design.toArtifact(ref))}\n');
  for (final file in Directory('artifact').listSync(recursive: true).whereType<File>()) {
    _write('${out.path}/${file.path.substring('artifact/'.length)}', file.readAsStringSync());
  }
}

void _write(String path, String contents) {
  File(path)
    ..createSync(recursive: true)
    ..writeAsStringSync(contents);
  stdout.writeln('wrote $path');
}

/// Where each token is used, as the package's `Palette` documents it.
const _usage = {
  'ground': 'The page itself: scaffolds, app bars, the space between things. White in every light palette.',
  'surface': 'Cards, sheets, dialogs, in front of the ground. Never greyer than the ground; border separates it.',
  'fill': 'Inputs, chips, quiet buttons: the one tone allowed below the ground.',
  'ink': 'Primary text and icons, on ground, surface and fill.',
  'muted': 'Secondary text (metadata, captions, unselected controls) on ground and surface; at least 4.5:1 on ground.',
  'faint': 'Pending and disabled things; quieter than muted. Not for text that must be read.',
  'border': 'Hairlines and control outlines.',
  'accent': 'The brand color as a fill: primary actions, completion marks. Never a text color on the ground.',
  'onAccent': 'Text and icons on an accent fill.',
  'accentInk': 'The accent as text, lines and chart marks on ground and surface; at least 4.5:1 on ground.',
  'destructive': 'Danger: deleting, discarding, errors. Kept clear of the accent hue in every preset.',
};

extension on Design {
  Map<String, Object?> toArtifact(String ref) {
    String key(String face) => face.toLowerCase().replaceAll(' ', '-');
    final themes = [
      for (final preset in defaultFirst)
        for (final dark in [false, true]) (id: '${preset.name}-${dark ? 'dark' : 'light'}', preset: preset, dark: dark),
    ];
    return {
      'name': 'Heart',
      'version': 1,
      'color': {
        'note':
            'Four presets, each a light and a dark palette of the same eleven tokens; a person picks one in the '
            'app. Ink is the house style. on-destructive is derived: surface in light, onAccent in dark.',
        'themes': [
          for (final theme in themes)
            {'id': theme.id, 'name': '${titleCase(theme.preset.name)} · ${theme.dark ? 'Dark' : 'Light'}'},
        ],
        'tokens': [
          for (final token in tokenNames)
            {
              'name': kebab(token),
              'value': {
                for (final theme in themes) theme.id: (theme.dark ? theme.preset.dark : theme.preset.light)[token],
              },
              'usage': _usage[token],
            },
          {
            'name': 'on-destructive',
            'value': {
              for (final theme in themes)
                theme.id: theme.dark ? theme.preset.dark['onAccent'] : theme.preset.light['surface'],
            },
            'usage': 'Text and icons on a destructive fill.',
          },
        ],
      },
      'type': {
        'fonts': <Object>[],
        'families': {for (final MapEntry(key: face) in faces.entries) key(face): fontStack(face)},
        'groups': [
          for (final preset in defaultFirst)
            {
              'name': titleCase(preset.name),
              'family': key(preset.text),
              'styles': [
                {
                  'name': '${preset.name}-headline',
                  'family': key(preset.display),
                  'fontSize': '${preset.headlineSize}px',
                  'fontWeight': preset.headlineWeight,
                  'usage': 'The page title, in the display face, sized for it.',
                },
                {
                  'name': '${preset.name}-card-title',
                  'family': key(preset.title),
                  'fontSize': '17px',
                  'fontWeight': 600,
                  'usage': 'A card title; at 700 in accent-ink, a hero stat.',
                },
                {
                  'name': '${preset.name}-card-body',
                  'fontSize': '13px',
                  'lineHeight': 1.4,
                  'fontWeight': 400,
                  'usage': 'Card rows and notes.',
                },
                {
                  'name': '${preset.name}-card-label',
                  'fontSize': '10px',
                  'letterSpacing': '1.5px',
                  'fontWeight': 400,
                  'usage': 'Uppercase labels under a hero stat, in muted.',
                },
              ],
            },
        ],
      },
      'radius': {
        'tokens': [
          {'name': 'radius-control', 'value': '${controlRadius}px', 'usage': 'Buttons, inputs, chips. No pills.'},
          {'name': 'radius-card', 'value': '${cardRadius}px', 'usage': 'Cards, sheets, dialogs.'},
        ],
      },
      'meta': {
        'source': 'github',
        'repo': 'kit-g/heart-api',
        'ref': ref,
        'package': 'shared/heart_design',
        'paths': {
          'tokens': ['shared/heart_design/tokens.json'],
          'docs': ['shared/heart_design/artifact/README.md'],
        },
      },
    };
  }
}
