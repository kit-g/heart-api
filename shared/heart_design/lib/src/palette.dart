/// One brightness of a preset: every color the UI is allowed to use.
///
/// Colors are ARGB integers (`0xFFRRGGBB`), what a Flutter `Color` takes, so
/// this package stays plain Dart. Nothing is derived at runtime: each preset's
/// two palettes are tuned by hand in `tokens.json`.
///
/// Light palettes are white-grounded: the page is white, surfaces stay white
/// with [border] doing the separating, and [fill] is the only tone below the
/// ground. [muted] clears WCAG AA (4.5:1) on the ground in both brightnesses.
final class Palette {
  /// The page itself: scaffolds, app bars, the space between things.
  final int ground;

  /// Elevated planes in front of the ground: cards, sheets, dialogs. In light
  /// this is white, never greyer than the ground.
  final int surface;

  /// Inset controls that must read as "a place to put something": inputs,
  /// chips, quiet buttons. The one tone allowed below the ground.
  final int fill;

  /// Primary text and icons.
  final int ink;

  /// Secondary text: metadata, captions, unselected controls.
  final int muted;

  /// Pending and disabled things; quieter than [muted].
  final int faint;

  /// Hairlines and control outlines.
  final int border;

  /// The brand color, worn as a fill: primary actions, completion marks.
  final int accent;

  /// Text and icons on an [accent] fill.
  final int onAccent;

  /// The accent as a text color on [ground]: the same hue kept legible, which
  /// on a light ground means darker than [accent], never the fill itself.
  final int accentInk;

  final int destructive;

  const new({
    required this.ground,
    required this.surface,
    required this.fill,
    required this.ink,
    required this.muted,
    required this.faint,
    required this.border,
    required this.accent,
    required this.onAccent,
    required this.accentInk,
    required this.destructive,
  });
}
