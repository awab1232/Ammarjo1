/// Currency derived from WooCommerce → **WooCommerce → Settings → General**.
class StoreCurrency {
  final String code;
  final String symbol;
  final int decimalPlaces;

  const StoreCurrency({
    required this.code,
    required this.symbol,
    required this.decimalPlaces,
  });

  /// Build from REST `GET /wc/v3/settings/general` (`woocommerce_currency`, `woocommerce_price_num_decimals`).
  factory StoreCurrency.fromWooSettings({
    required String? currencyCode,
    required int? priceNumDecimals,
  }) {
    final code = (currencyCode?.trim().isNotEmpty ?? false)
        ? currencyCode!.trim().toUpperCase()
        : 'JOD';
    final decimals = priceNumDecimals ?? _defaultDecimalsFor(code);
    return StoreCurrency(
      code: code,
      symbol: symbolForCode(code),
      decimalPlaces: decimals.clamp(0, 6),
    );
  }

  static int _defaultDecimalsFor(String code) {
    switch (code.toUpperCase()) {
      case 'JOD':
      case 'KWD':
      case 'BHD':
      case 'IQD':
      case 'LYD':
      case 'OMR':
      case 'TND':
        return 3;
      default:
        return 2;
    }
  }

  /// Arabic-friendly symbols; falls back to ISO code if unknown.
  static String symbolForCode(String code) {
    switch (code.toUpperCase()) {
      case 'JOD':
        return 'د.أ';
      case 'SAR':
        return 'ر.س';
      case 'AED':
        return 'د.إ';
      case 'USD':
        return 'USD';
      case 'EUR':
        return '€';
      default:
        return code.toUpperCase();
    }
  }

  /// [raw] is the numeric string WooCommerce returns in `price` / `regular_price`, or a min–max range for variable products.
  String formatAmount(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return '—';
    if (trimmed.contains('–')) {
      final parts = trimmed.split('–');
      if (parts.length == 2) {
        return '${parts[0].trim()}–${parts[1].trim()} $symbol';
      }
    }
    return '$trimmed $symbol';
  }

  String formatDouble(double value) {
    return '${value.toStringAsFixed(decimalPlaces)} $symbol';
  }
}
