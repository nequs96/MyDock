import Foundation

enum FinancialCurrencyFormatter {
    static func majorUnits(from minorUnits: Decimal, currency: String) -> Decimal {
        let scale = Decimal(exponent(for: currency) == 0 ? 1 : 100)
        var amount = minorUnits
        var divisor = scale
        var result = Decimal.zero
        _ = NSDecimalDivide(&result, &amount, &divisor, .bankers)
        return result
    }

    static func text(from minorUnits: Decimal, currency: String) -> String {
        majorUnits(from: minorUnits, currency: currency).formatted(.currency(code: currency))
    }

    private static func exponent(for currency: String) -> Int {
        switch currency.uppercased() {
        case "BIF", "CLP", "DJF", "GNF", "JPY", "KMF", "KRW", "MGA", "PYG", "RWF", "VND", "VUV", "XAF", "XOF", "XPF": 0
        default: 2
        }
    }
}
