import Foundation

/// How much of the recorded history actually survives Claude Code's transcript
/// cleanup.
///
/// This exists because "All time" was a false label. AI Notch can only see
/// transcripts Claude Code has not yet deleted (`cleanupPeriodDays`, 30 by
/// default) plus whatever it has recorded itself since being installed. On a
/// machine that has been in use longer than that, the widest range is a
/// fraction of the real lifetime total and must say so.
struct HistoryCoverage: Equatable {
    /// The oldest day any record exists for.
    let earliest: Date
    /// The day the cleanup horizon currently falls on.
    let cutoff: Date
    /// Share of all recorded tokens that predate that horizon.
    let shareBeforeCutoff: Double
    /// True when the totals are short because history was deleted, rather than
    /// because the account is simply new.
    let isTruncated: Bool

    /// Detects a retention *cliff*, not merely old data.
    ///
    /// The naive check — "is the oldest record about 30 days old?" — gets this
    /// backwards on a real machine: a handful of stray sessions survive far
    /// past the horizon and make the history look deep when almost everything
    /// between them and the horizon was deleted. So the test is whether a long
    /// span before the cutoff carries a negligible share of the tokens.
    static func evaluate(
        daily: [DailyUsage],
        now: Date = Date(),
        cleanupPeriodDays: Int = 30,
        calendar: Calendar = .current
    ) -> HistoryCoverage? {
        guard let earliest = daily.map(\.day).min() else { return nil }
        let cutoff = calendar.startOfDay(
            for: calendar.date(byAdding: .day, value: -cleanupPeriodDays, to: now) ?? now
        )

        var before: Int64 = 0
        var after: Int64 = 0
        for entry in daily {
            if entry.day < cutoff {
                before += entry.tokens.total
            } else {
                after += entry.tokens.total
            }
        }
        let total = before + after
        guard total > 0 else { return nil }

        let share = Double(before) / Double(total)
        let spanBeforeCutoff = calendar.dateComponents([.day], from: earliest, to: cutoff).day ?? 0

        let isTruncated: Bool
        if spanBeforeCutoff <= 3 {
            // Nothing meaningfully predates the horizon at all.
            isTruncated = true
        } else if spanBeforeCutoff >= 14, share < 0.05 {
            // Weeks of calendar time before the horizon carrying almost no
            // tokens: the transcripts were deleted, not never written.
            isTruncated = true
        } else {
            isTruncated = false
        }

        return HistoryCoverage(
            earliest: earliest,
            cutoff: cutoff,
            shareBeforeCutoff: share,
            isTruncated: isTruncated
        )
    }
}
