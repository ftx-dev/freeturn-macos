import Foundation

enum ANSIColors {
    private static let sequence = try! NSRegularExpression(pattern: #"\x1B\[[0-?]*[ -/]*[@-~]"#)
    private static let palette: [UInt32] = [
        0x000000, 0xCD0000, 0x00CD00, 0xCDCD00, 0x0000EE, 0xCD00CD, 0x00CDCD, 0xE5E5E5,
        0x7F7F7F, 0xFF0000, 0x00FF00, 0xFFFF00, 0x5C5CFF, 0xFF00FF, 0x00FFFF, 0xFFFFFF,
    ]
    private static let cube: [UInt8] = [0, 95, 135, 175, 215, 255]

    static func decode(_ text: String) -> [LogLine.Segment]? {
        guard text.utf8.contains(0x1B) else { return nil }
        let source = text as NSString
        var segments: [LogLine.Segment] = []
        var foreground: LogLine.RGB?
        var background: LogLine.RGB?
        var offset = 0

        func append(upTo end: Int) {
            guard end > offset else { return }
            let fragment = source.substring(with: NSRange(location: offset, length: end - offset))
            if let last = segments.last, last.foreground == foreground, last.background == background {
                segments[segments.count - 1].text += fragment
            } else {
                segments.append(LogLine.Segment(text: fragment, foreground: foreground, background: background))
            }
        }

        let matches = sequence.matches(in: text, range: NSRange(location: 0, length: source.length))
        guard !matches.isEmpty else { return nil }
        for match in matches {
            append(upTo: match.range.location)
            let end = NSMaxRange(match.range)
            if source.character(at: end - 1) == 0x6D {
                let parameters = source.substring(with: NSRange(location: match.range.location + 2,
                                                               length: match.range.length - 3))
                apply(parameters, foreground: &foreground, background: &background)
            }
            offset = end
        }
        append(upTo: source.length)
        return segments
    }

    private static func apply(_ parameters: String, foreground: inout LogLine.RGB?, background: inout LogLine.RGB?) {
        var codes = parameters.components(separatedBy: ";").makeIterator()
        while let parameter = codes.next() {
            guard let code = parameter.isEmpty ? 0 : Int(parameter) else { continue }
            switch code {
            case 0: foreground = nil; background = nil
            case 30...37: foreground = indexed(code - 30)
            case 40...47: background = indexed(code - 40)
            case 90...97: foreground = indexed(code - 90 + 8)
            case 100...107: background = indexed(code - 100 + 8)
            case 38: if let color = extended(&codes) { foreground = color }
            case 48: if let color = extended(&codes) { background = color }
            case 39: foreground = nil
            case 49: background = nil
            default: break
            }
        }
    }

    private static func extended(_ codes: inout IndexingIterator<[String]>) -> LogLine.RGB? {
        switch codes.next() {
        case "5":
            guard let index = codes.next().flatMap(UInt8.init) else { return nil }
            return indexed(Int(index))
        case "2":
            let red = codes.next().flatMap(UInt8.init)
            let green = codes.next().flatMap(UInt8.init)
            let blue = codes.next().flatMap(UInt8.init)
            guard let red, let green, let blue else { return nil }
            return .init(red: red, green: green, blue: blue)
        default:
            return nil
        }
    }

    private static func indexed(_ index: Int) -> LogLine.RGB {
        switch index {
        case 0..<16:
            let rgb = palette[index]
            return .init(red: UInt8(truncatingIfNeeded: rgb >> 16),
                         green: UInt8(truncatingIfNeeded: rgb >> 8),
                         blue: UInt8(truncatingIfNeeded: rgb))
        case 16..<232:
            let color = index - 16
            return .init(red: cube[color / 36], green: cube[color / 6 % 6], blue: cube[color % 6])
        default:
            let gray = UInt8(8 + (index - 232) * 10)
            return .init(red: gray, green: gray, blue: gray)
        }
    }
}
