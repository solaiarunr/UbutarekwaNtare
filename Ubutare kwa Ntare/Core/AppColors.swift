import UIKit

enum AppColors {
    static let primary = UIColor(red: 244 / 255, green: 163 / 255, blue: 0, alpha: 1)
    static let orange = UIColor(red: 242 / 255, green: 153 / 255, blue: 74 / 255, alpha: 1)
    static let red = UIColor(red: 235 / 255, green: 87 / 255, blue: 87 / 255, alpha: 1)
    static let gray = UIColor(red: 130 / 255, green: 130 / 255, blue: 130 / 255, alpha: 1)
    static let lightGray = UIColor(red: 245 / 255, green: 245 / 255, blue: 245 / 255, alpha: 1)
}

extension UIColor {
    convenience init?(hex: String) {
        var cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if cleaned.hasPrefix("#") { cleaned.removeFirst() }
        guard cleaned.count == 6, let value = UInt64(cleaned, radix: 16) else { return nil }
        self.init(
            red: CGFloat((value & 0xFF0000) >> 16) / 255,
            green: CGFloat((value & 0x00FF00) >> 8) / 255,
            blue: CGFloat(value & 0x0000FF) / 255,
            alpha: 1
        )
    }
}
