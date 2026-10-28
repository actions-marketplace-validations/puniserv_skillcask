import Foundation

/// Dates and numbers as the boards write them. All copy is English and the boards fix the order, so these
/// formatters pin the locale ("30 Oct" on every Mac), but a date reads on the viewer's own calendar day: every
/// function takes the `timeZone` (default the Mac's). Tests pass `.gmt` so they hold in any zone.
public enum Formatters {
    /// `30 Oct`: day then abbreviated month, no year (Main, List-States and Tokens boards).
    public static func dayMonth(_ date: Date, timeZone: TimeZone = .current) -> String {
        date.formatted(style(timeZone).day().month(.abbreviated))
    }

    /// `24 Oct 2026`: the release date in the detail header's update strip (Main board).
    public static func dayMonthYear(_ date: Date, timeZone: TimeZone = .current) -> String {
        date.formatted(style(timeZone).day().month(.abbreviated).year())
    }

    /// `09:14`: hours and minutes on a 24-hour clock (Versions board "released 28 Oct 2026 at 09:14").
    public static func time(_ date: Date, timeZone: TimeZone = .current) -> String {
        date.formatted(style(timeZone).hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
    }

    /// `3 days ago`, `1 day ago` or `today`, counting calendar days in `timeZone` from `date` to `now` (Main
    /// board's "Released 24 Oct 2026, 3 days ago"); a date after `now` reads `today`.
    public static func daysAgo(_ date: Date, now: Date, timeZone: TimeZone = .current) -> String {
        let calendar = calendar(timeZone)
        let days =
            calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now))
            .day ?? 0
        switch days {
        case ..<1: return "today"
        case 1: return "1 day ago"
        default: return "\(days) days ago"
        }
    }

    /// The Gregorian calendar in `timeZone`: the copy is English, so never the Mac's own calendar system.
    static func calendar(_ timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    private static func style(_ timeZone: TimeZone) -> Date.FormatStyle {
        Date.FormatStyle(locale: Locale(identifier: "en_GB"), calendar: calendar(timeZone), timeZone: timeZone)
    }
}
