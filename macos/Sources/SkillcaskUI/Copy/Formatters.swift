import Foundation

/// Dates and numbers as the boards write them. All copy is English and the boards fix the order, so these
/// formatters pin the locale and the time zone rather than follow the machine: "30 Oct" on every Mac.
public enum Formatters {
    /// `30 Oct`: day then abbreviated month, no year (Main, List-States and Tokens boards). GMT, so the day never
    /// shifts with the viewer's zone.
    public static func dayMonth(_ date: Date) -> String {
        date.formatted(dayMonthStyle)
    }

    /// `24 Oct 2026`: the release date in the detail header's update strip (Main board). GMT, as `dayMonth`.
    public static func dayMonthYear(_ date: Date) -> String {
        date.formatted(dayMonthYearStyle)
    }

    /// `09:14`: hours and minutes on a 24-hour clock in GMT, as `dayMonth` (Versions board "released 28 Oct 2026
    /// at 09:14").
    public static func time(_ date: Date) -> String {
        date.formatted(timeStyle)
    }

    /// `3 days ago`, `1 day ago` or `today`, counting GMT calendar days from `date` to `now` (Main board's
    /// "Released 24 Oct 2026, 3 days ago"); a date after `now` reads `today`.
    public static func daysAgo(_ date: Date, now: Date) -> String {
        let days =
            gmtCalendar.dateComponents(
                [.day], from: gmtCalendar.startOfDay(for: date), to: gmtCalendar.startOfDay(for: now)
            )
            .day ?? 0
        switch days {
        case ..<1: return "today"
        case 1: return "1 day ago"
        default: return "\(days) days ago"
        }
    }

    private static let gmtCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }()

    private static let dayMonthYearStyle = Date.FormatStyle(locale: Locale(identifier: "en_GB"), timeZone: .gmt)
        .day()
        .month(.abbreviated)
        .year()

    private static let timeStyle = Date.FormatStyle(locale: Locale(identifier: "en_GB"), timeZone: .gmt)
        .hour(.twoDigits(amPM: .omitted))
        .minute(.twoDigits)

    private static let dayMonthStyle = Date.FormatStyle(locale: Locale(identifier: "en_GB"), timeZone: .gmt)
        .day()
        .month(.abbreviated)
}
