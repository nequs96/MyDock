import Foundation

enum FinancialCurrencyFormatter {
    static func majorUnits(from minorUnits: Decimal, currency: String) -> Decimal {
        let scale: Decimal = switch exponent(for: currency) { case 0: 1; case 3: 1000; default: 100 }
        var amount = minorUnits
        var divisor = scale
        var result = Decimal.zero
        _ = NSDecimalDivide(&result, &amount, &divisor, .bankers)
        return result
    }

    static func text(from minorUnits: Decimal, currency: String) -> String {
        majorUnits(from: minorUnits, currency: currency).formatted(.currency(code: currency))
    }

    /// Digits in a provider's minor unit, per Stripe's currency list: zero-decimal currencies (UGX included)
    /// and the three-decimal Gulf and North African currencies; everything else uses cents.
    static func exponent(for currency: String) -> Int {
        switch currency.uppercased() {
        case "BIF", "CLP", "DJF", "GNF", "JPY", "KMF", "KRW", "MGA", "PYG", "RWF", "UGX", "VND", "VUV", "XAF", "XOF", "XPF": 0
        case "BHD", "IQD", "JOD", "KWD", "LYD", "OMR", "TND": 3
        default: 2
        }
    }
}
