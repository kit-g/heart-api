/// The units a card shows its numbers in: the user's, as a tool result names
/// them (`unitSystem`). The tools always measure in kilograms and kilometres.
enum Units {
  metric('kg', 'km'),
  imperial('lb', 'mi');

  new(this.weight, this.distance);

  /// The weight unit's symbol.
  final String weight;

  /// The distance unit's symbol.
  final String distance;

  /// A result's `unitSystem`; anything but `imperial` reads as metric.
  static Units of(Object? unitSystem) => unitSystem == 'imperial' ? imperial : metric;

  /// [kg] in this system's weight unit.
  num fromKg(num kg) => this == imperial ? kg * 2.20462262 : kg;

  /// [km] in this system's distance unit.
  num fromKm(num km) => this == imperial ? km * 0.621371192 : km;
}
