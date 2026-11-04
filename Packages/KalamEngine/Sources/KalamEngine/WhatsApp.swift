import Foundation

public struct ChatMessage: Equatable, Sendable {
    public let sender: String
    public let date: Date?
    public let text: String
}

/// Parses an exported WhatsApp `_chat.txt` (SPEC 9.3), iOS `[dd/mm/yy, hh:mm:ss] Name: text` or
/// Android `dd/mm/yyyy, hh:mm - Name: text`: 2- or 4-digit years, optional seconds, ":" or "." in
/// times, 12-hour times with AM/PM (after a space or U+202F), CRLF or LF. Lines that don't start a
/// message continue the previous one. System lines, media and deleted messages are skipped.
public func parseWhatsApp(_ text: String, now: Date = Date(), calendar: Calendar = Calendar(identifier: .gregorian)) -> [ChatMessage] {
    var messages: [ChatMessage] = []
    var current: (sender: String, date: Date?, lines: [String])?
    func finish() {
        guard let message = current else { return }
        current = nil
        let body = message.lines.joined(separator: "\n").replacingOccurrences(of: editedMarker, with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty, !skipMarkers.contains(where: body.contains) else { return }
        messages.append(ChatMessage(sender: message.sender, date: message.date, text: body))
    }
    for rawLine in text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
        let line = String(String.UnicodeScalarView(rawLine.unicodeScalars.filter { !strippedMarks.contains($0) }))
        guard let match = line.wholeMatch(of: header) else {
            current?.lines.append(line)
            continue
        }
        finish()
        let rest = match.output.8
        guard let colon = rest.range(of: ": ") else { continue }  // a system line, e.g. "X created group"
        let date = chatDate(match.output, now: now, calendar: calendar)
        current = (String(rest[..<colon.lowerBound]), date, [String(rest[colon.upperBound...])])
    }
    finish()
    return messages
}

private let strippedMarks: Set<Unicode.Scalar> = ["\u{200E}", "\u{200F}", "\u{FEFF}"]
private let editedMarker = "<This message was edited>"
private let skipMarkers = [
    "<Media omitted>", "image omitted", "video omitted", "audio omitted", "sticker omitted", "GIF omitted",
    "document omitted", "Contact card omitted", "<attached:", "This message was deleted", "You deleted this message",
    "Messages and calls are end-to-end encrypted",
]

private typealias HeaderOutput = (Substring, Substring, Substring, Substring, Substring, Substring, Substring?, Substring?, Substring)

// Captures: day/month, month/day, year, hour, minute, second?, a|p?, rest.
private let header =
    #/\[?(\d{1,2})[\/.\-](\d{1,2})[\/.\-](\d{2,4}),?\s(\d{1,2})[:.](\d{2})(?:[:.](\d{2}))?(?:[\s\x{202F}]?([AaPp])\.?\s?[Mm]\.?)?(?:\]\s|\s-\s)(.*)/#

/// The message date. dd/mm and mm/dd look alike; the date only feeds t_last, so take dd/mm when it
/// is a valid past date, else mm/dd, else none.
private func chatDate(_ output: HeaderOutput, now: Date, calendar: Calendar) -> Date? {
    guard let first = Int(output.1), let second = Int(output.2), let rawYear = Int(output.3), let rawHour = Int(output.4),
          let minute = Int(output.5) else { return nil }
    var hour = rawHour
    if let meridiem = output.7?.lowercased() { hour = rawHour % 12 + (meridiem == "p" ? 12 : 0) }
    let year = rawYear < 100 ? 2000 + rawYear : rawYear
    for (day, month) in [(first, second), (second, first)] {
        let components = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: output.6.flatMap { Int($0) } ?? 0)
        guard components.isValidDate(in: calendar), let date = calendar.date(from: components),
              date <= now.addingTimeInterval(86_400) else { continue }  // a day of slack for time zones
        return date
    }
    return nil
}
