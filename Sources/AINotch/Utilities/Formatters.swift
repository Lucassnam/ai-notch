import Foundation

enum AIFormat {
    static func tokens(_ value: Int64) -> String {
        switch abs(value) {
        case 1_000_000_000...:
            return String(format: "%.1fB", Double(value) / 1_000_000_000)
        case 1_000_000...:
            return String(format: "%.1fM", Double(value) / 1_000_000)
        case 1_000...:
            return String(format: "%.1fK", Double(value) / 1_000)
        default:
            return "\(value)"
        }
    }

    /// `compact` is for places where the glyphs have to fit a fixed slot — the
    /// two values beside the notch, and chart axis labels.
    ///
    /// It caps the result at six characters so a 44pt slot never has to shrink
    /// the text below the 11pt floor the type scale sets: cents up to $99.99,
    /// whole dollars from $100 (`$181`), and thousands from $1,000 (`$1.2K`).
    /// Cents are the first thing to go because at three figures they are the
    /// least significant thing on screen, and truncating a number or rendering
    /// it at 10pt are both worse.
    static func currency(_ value: Double, compact: Bool = false) -> String {
        if compact {
            let magnitude = abs(value)
            // Thresholds are set on the *rounded* result, not the raw value:
            // $99,999 is under a million but renders as "$100.0K", which is
            // seven characters.
            if magnitude >= 999_500 {
                let millions = value / 1_000_000
                return String(format: abs(millions) >= 10 ? "$%.0fM" : "$%.1fM", millions)
            }
            if magnitude >= 1_000 {
                let thousands = value / 1_000
                return String(format: abs(thousands) >= 10 ? "$%.0fK" : "$%.1fK", thousands)
            }
            if magnitude >= 100 {
                return String(format: "$%.0f", value)
            }
        }
        if value < 0.01 && value > 0 {
            return "<$0.01"
        }
        // Grouped from $1,000: "$3207.90" reads as a typo at 26pt. The locale
        // is pinned so the separators cannot change under a test or a user.
        if abs(value) >= 1_000 {
            let digits = value.formatted(
                .number
                    .precision(.fractionLength(2))
                    .grouping(.automatic)
                    .locale(Locale(identifier: "en_US"))
            )
            return "$\(digits)"
        }
        return String(format: "$%.2f", value)
    }

    static func relative(_ date: Date, now: Date = Date()) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: now)
    }

    static func reset(_ date: Date?, now: Date = Date()) -> String {
        guard let date else { return "Reset unavailable" }
        if date <= now { return "Reset due" }
        let interval = date.timeIntervalSince(now)
        let hours = Int(interval / 3_600)
        let minutes = Int(interval.truncatingRemainder(dividingBy: 3_600) / 60)
        if hours >= 24 { return "Resets in \(hours / 24)d \(hours % 24)h" }
        if hours > 0 { return "Resets in \(hours)h \(minutes)m" }
        return "Resets in \(max(1, minutes))m"
    }

    /// Turns a raw model identifier into a display name.
    ///
    /// Vendors encode the version with the same hyphen they use as a word
    /// separator, so a blanket hyphen-to-space replacement renders
    /// `claude-opus-4-8` as "Opus 4 8". Numeric runs are rejoined with a dot
    /// and trailing release datestamps are dropped.
    static func modelName(_ raw: String) -> String {
        var segments = raw
            .replacingOccurrences(of: "claude-", with: "")
            .split(separator: "-")
            .map(String.init)

        // `claude-haiku-4-5-20251001` — an 8-digit tail is a release date.
        if let last = segments.last, last.count == 8, last.allSatisfy(\.isNumber) {
            segments.removeLast()
        }

        var parts: [String] = []
        for segment in segments {
            let isVersion = segment.allSatisfy { $0.isNumber || $0 == "." }
            if isVersion, !parts.isEmpty, let previous = parts.last,
               previous.last.map({ $0.isNumber }) == true {
                // Consecutive numeric segments are one version: 4 + 8 -> 4.8
                parts[parts.count - 1] = "\(previous).\(segment)"
            } else if segment.lowercased() == "gpt" {
                parts.append("GPT")
            } else if isVersion {
                parts.append(segment)
            } else {
                parts.append(segment.capitalized)
            }
        }

        return parts.joined(separator: " ")
    }
}
