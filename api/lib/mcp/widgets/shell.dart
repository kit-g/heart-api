part of '../widgets.dart';

// What every widget page shares: its opening, then the design system's
// tokens, the cards' shared styles and the card's own, and the card's
// compiled script, which carries its MCP Apps bridge (ext-apps 2026-01-26).

/// The page's opening, up to its own styles.
const _head =
    '<!DOCTYPE html><html lang="en"><head><meta charset="utf-8">'
    '<meta name="viewport" content="width=device-width, initial-scale=1">';

/// The page's styles: the tokens (`package:heart_design`), Ink unless a page
/// sets `data-preset`, and what every card shares (`_cardCss`, from
/// `pages/lib/cards/styles.dart`). The host's `theme` wins over the OS
/// setting when it sends one.
const _baseCss = '$tokensCss$_cardCss';

/// The page's body: an empty root the card's script draws into.
const _root = '<body><main id="root" aria-live="polite"></main>';
