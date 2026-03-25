#! /usr/bin/env swift
// cartovanta textdeck -- Creates CartoVanta decks from text lists
// Copyright (C) 2026  Sophia Elizabeth Shapira
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.
import Foundation
#if canImport(AppKit)
import AppKit
#endif

struct CLIError: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}

enum ParsedToken {
    case text(String)
    case newline
    case barrier
}

struct StyledParagraph {
    let text: String
    let fontName: String
    let baseFontSize: Double
}

struct CardRecord: Encodable {
    let id: String
    let name: String
    let frontImage: String
    let meta: [String: String]
}

struct CardSize: Encodable {
    let width: Int
    let height: Int
}

struct DeckFile: Encodable {
    let format: String
    let deckId: String
    let deckName: String
    let version: String
    let backImage: String
    let cardSize: CardSize
    let meta: [String: String]
    let cards: [CardRecord]
}

struct OuterMetaFile: Encodable {
    let format: String
    let deckName: String
    let meta: [String: String]
}

struct LineStyleOverride {
    var fontName: String?
    var absoluteSize: Double?
    var percentSize: Double?
}

struct Options {
    let backImagePath: String
    let inputFilePath: String
    let outputDirectoryPath: String
    var explicitSize: (Int, Int)?
    var explicitHeight: Int?
    var defaultFontName: String = "Helvetica"
    var generalFontSize: Double?
    var lineOverrides: [Int: LineStyleOverride] = [:]
    var verticalMargin: Int?
    var horizontalMargin: Int?
    var deckId: String?
    var deckName: String?
    var version: String = Options.defaultVersionString()

    static func defaultVersionString() -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(secondsFromGMT: 0)
        df.dateFormat = "yyyy-MM-dd-1"
        return df.string(from: Date())
    }
}

let helpText = #"""
Usage:
  deckgen.swift [back-image] [input-file] [output-directory] [options]

Required positional arguments:
  [back-image]        Path to the shared back-of-card image.
  [input-file]        Path to the text file containing card names.
  [output-directory]  Path to a directory that must not already exist.

Options:
  --size [width] [height]      Override card dimensions instead of inferring them from the back image.
  --height [pixels]            Override only the deck.json card height while preserving the base aspect ratio.
  --font [font-name]           Set the default font for all cards. Default: Helvetica.
  --lfont [line#] [font-name]  Set the font for an explicit \\n-separated line number, starting at 1.
  --fsize [font-size]          Set the general font size in points/pixels.
  --lfsize [line#] [font-size] Set an absolute font size for an explicit \\n-separated line number.
  --lfsizep [line#] [percent]  Set a line size as a percentage of the general font size.
  --vmargin [pixels]           Set the top and bottom margin.
  --hmargin [pixels]           Set the left and right margin.
  --deck-id [id]               Override the deckId. Default: derived from output directory name.
  --deck-name [name]           Override the deckName. Default: derived from output directory name.
  --version [value]            Override the deck version string. Default: current UTC date plus '-1'.
  --help                       Print this help text.

Input-file syntax:
  * Blank or whitespace-only lines are ignored.
  * A line whose first nonblank character is an unescaped # is ignored as a comment.
  * Backslash escapes are recognized inside content:
      \\   literal backslash
      backslash followed by #   literal hash
      \\n   forced paragraph break with extra spacing
      \\k   trimming barrier; not rendered, but blocks trimming across its position
  * Trimming removes leading/trailing whitespace in each explicit \\n-separated paragraph,
    except where blocked by \\k.
  * A line whose sole printable content is \\k creates a card with an intentionally empty name.

Output structure:
  [output-directory]/
    deck.json
    meta.json
    notes.txt
    imagia/
      back.[original-extension]
      card-N.png (or zero-padded when needed)
"""#

let cartoVantaFormatIdentifier = "cartovanta-v0.1"

enum AllowedImageType: String {
    case png
    case jpeg
    case webp

    var preferredExtension: String {
        switch self {
        case .png: return "png"
        case .jpeg: return "jpg"
        case .webp: return "webp"
        }
    }
}

func detectImageType(data: Data) -> AllowedImageType? {
    if data.count >= 8 && data.prefix(8) == Data([137,80,78,71,13,10,26,10]) {
        return .png
    }
    if data.count >= 12,
       let riff = String(data: data.prefix(4), encoding: .ascii), riff == "RIFF",
       let webp = String(data: data[8..<12], encoding: .ascii), webp == "WEBP" {
        return .webp
    }
    if data.count >= 4 && data[0] == 0xFF && data[1] == 0xD8 {
        return .jpeg
    }
    return nil
}

func fail(_ message: String) -> Never {
    fputs("Error: \(message)\n", stderr)
    exit(1)
}

func parseInt(_ value: String, option: String) throws -> Int {
    guard let i = Int(value) else {
        throw CLIError(message: "\(option) expects an integer, got '\(value)'.")
    }
    return i
}

func parseDouble(_ value: String, option: String) throws -> Double {
    guard let d = Double(value) else {
        throw CLIError(message: "\(option) expects a number, got '\(value)'.")
    }
    return d
}

func parseArguments(_ args: [String]) throws -> Options? {
    if args.contains("--help") {
        print(helpText)
        return nil
    }
    if args.count < 3 {
        throw CLIError(message: "Expected [back-image] [input-file] [output-directory]. Use --help for usage.")
    }
    var options = Options(backImagePath: args[0], inputFilePath: args[1], outputDirectoryPath: args[2])
    var i = 3
    while i < args.count {
        let arg = args[i]
        func require(_ n: Int) throws -> [String] {
            guard i + n < args.count else {
                throw CLIError(message: "Option '\(arg)' is missing argument(s).")
            }
            return Array(args[(i + 1)...(i + n)])
        }
        switch arg {
        case "--size":
            let vals = try require(2)
            let w = try parseInt(vals[0], option: arg)
            let h = try parseInt(vals[1], option: arg)
            guard w > 0, h > 0 else { throw CLIError(message: "--size values must be positive.") }
            options.explicitSize = (w, h)
            i += 3
        case "--height":
            let vals = try require(1)
            let h = try parseInt(vals[0], option: arg)
            guard h > 0 else { throw CLIError(message: "--height must be positive.") }
            options.explicitHeight = h
            i += 2
        case "--font":
            let vals = try require(1)
            options.defaultFontName = vals[0]
            i += 2
        case "--lfont":
            let vals = try require(2)
            let line = try parseInt(vals[0], option: arg)
            guard line >= 1 else { throw CLIError(message: "--lfont line number must be at least 1.") }
            var override = options.lineOverrides[line] ?? LineStyleOverride()
            override.fontName = vals[1]
            options.lineOverrides[line] = override
            i += 3
        case "--fsize":
            let vals = try require(1)
            let size = try parseDouble(vals[0], option: arg)
            guard size > 0 else { throw CLIError(message: "--fsize must be positive.") }
            options.generalFontSize = size
            i += 2
        case "--lfsize":
            let vals = try require(2)
            let line = try parseInt(vals[0], option: arg)
            let size = try parseDouble(vals[1], option: arg)
            guard line >= 1 else { throw CLIError(message: "--lfsize line number must be at least 1.") }
            guard size > 0 else { throw CLIError(message: "--lfsize size must be positive.") }
            var override = options.lineOverrides[line] ?? LineStyleOverride()
            if override.percentSize != nil {
                throw CLIError(message: "Line \(line) cannot use both --lfsize and --lfsizep.")
            }
            override.absoluteSize = size
            options.lineOverrides[line] = override
            i += 3
        case "--lfsizep":
            let vals = try require(2)
            let line = try parseInt(vals[0], option: arg)
            let percent = try parseDouble(vals[1], option: arg)
            guard line >= 1 else { throw CLIError(message: "--lfsizep line number must be at least 1.") }
            guard percent > 0 else { throw CLIError(message: "--lfsizep percentage must be positive.") }
            var override = options.lineOverrides[line] ?? LineStyleOverride()
            if override.absoluteSize != nil {
                throw CLIError(message: "Line \(line) cannot use both --lfsize and --lfsizep.")
            }
            override.percentSize = percent
            options.lineOverrides[line] = override
            i += 3
        case "--vmargin":
            let vals = try require(1)
            let v = try parseInt(vals[0], option: arg)
            guard v >= 0 else { throw CLIError(message: "--vmargin cannot be negative.") }
            options.verticalMargin = v
            i += 2
        case "--hmargin":
            let vals = try require(1)
            let h = try parseInt(vals[0], option: arg)
            guard h >= 0 else { throw CLIError(message: "--hmargin cannot be negative.") }
            options.horizontalMargin = h
            i += 2
        case "--deck-id":
            let vals = try require(1)
            options.deckId = vals[0]
            i += 2
        case "--deck-name":
            let vals = try require(1)
            options.deckName = vals[0]
            i += 2
        case "--version":
            let vals = try require(1)
            options.version = vals[0]
            i += 2
        default:
            throw CLIError(message: "Unknown option '\(arg)'. Use --help for usage.")
        }
    }
    return options
}

func firstNonWhitespaceIndex(in chars: [Character]) -> Int? {
    for (idx, ch) in chars.enumerated() {
        if !ch.isWhitespaceLike { return idx }
    }
    return nil
}

extension Character {
    var isWhitespaceLike: Bool {
        unicodeScalars.allSatisfy { CharacterSet.whitespacesAndNewlines.contains($0) }
    }
}

struct ParsedLine {
    let cardName: String
}

func parseNamesFile(at path: String) throws -> [ParsedLine] {
    let content = try String(contentsOfFile: path, encoding: .utf8)
    var results: [ParsedLine] = []
    content.enumerateLines { rawLine, _ in
        do {
            if let parsed = try parseInputLine(rawLine) {
                results.append(parsed)
            }
        } catch {
            fail(error.localizedDescription)
        }
    }
    return results
}

func parseInputLine(_ rawLine: String) throws -> ParsedLine? {
    let chars = Array(rawLine)
    guard let first = firstNonWhitespaceIndex(in: chars) else {
        return nil
    }
    if chars[first] == "#" { return nil }

    let tokens = try tokenize(line: rawLine)
    let hadBarrier = tokens.contains { if case .barrier = $0 { return true } else { return false } }
    let paragraphs = splitIntoParagraphs(tokens)
    var processed: [String] = []
    var hadAnyMaterial = false
    for para in paragraphs {
        let trimmed = trimParagraphTokens(para)
        let text = paragraphString(trimmed)
        if !text.isEmpty { hadAnyMaterial = true }
        processed.append(text)
    }

    if !hadAnyMaterial {
        if hadBarrier {
            return ParsedLine(cardName: processed.joined(separator: "\n"))
        }
        return nil
    }
    return ParsedLine(cardName: processed.joined(separator: "\n"))
}

func tokenize(line: String) throws -> [ParsedToken] {
    let chars = Array(line)
    var tokens: [ParsedToken] = []
    var i = 0
    while i < chars.count {
        let ch = chars[i]
        if ch == "\\" {
            guard i + 1 < chars.count else {
                throw CLIError(message: "Dangling backslash escape in input line: \(line)")
            }
            let next = chars[i + 1]
            switch next {
            case "\\": tokens.append(.text("\\"))
            case "#": tokens.append(.text("#"))
            case "n": tokens.append(.newline)
            case "k": tokens.append(.barrier)
            default:
                throw CLIError(message: "Unknown escape \\(next) in input line: \(line)")
            }
            i += 2
        } else {
            tokens.append(.text(String(ch)))
            i += 1
        }
    }
    return tokens
}

func splitIntoParagraphs(_ tokens: [ParsedToken]) -> [[ParsedToken]] {
    var result: [[ParsedToken]] = [[]]
    for token in tokens {
        switch token {
        case .newline:
            result.append([])
        default:
            result[result.count - 1].append(token)
        }
    }
    return result
}

func trimParagraphTokens(_ tokens: [ParsedToken]) -> [ParsedToken] {
    var start = 0
    var end = tokens.count - 1

    while start < tokens.count {
        switch tokens[start] {
        case .barrier:
            break
        case .text(let s) where s.allSatisfy({ $0.isWhitespaceLike }):
            start += 1
            continue
        default:
            break
        }
        break
    }

    if end >= start {
        while end >= start {
            switch tokens[end] {
            case .barrier:
                break
            case .text(let s) where s.allSatisfy({ $0.isWhitespaceLike }):
                end -= 1
                continue
            default:
                break
            }
            break
        }
    }

    if start > end { return [] }
    return Array(tokens[start...end])
}

func paragraphString(_ tokens: [ParsedToken]) -> String {
    var out = ""
    for token in tokens {
        switch token {
        case .text(let s): out += s
        case .barrier, .newline: break
        }
    }
    return out
}

func sanitizeDeckId(_ source: String) -> String {
    let lowered = source.lowercased()
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-"))
    var pieces: [String] = []
    var current = ""
    for scalar in lowered.unicodeScalars {
        if allowed.contains(scalar) {
            current.unicodeScalars.append(scalar)
        } else {
            if !current.isEmpty {
                pieces.append(current)
                current = ""
            }
        }
    }
    if !current.isEmpty { pieces.append(current) }
    let joined = pieces.joined(separator: "-")
    return joined.isEmpty ? "deck" : joined
}

func deriveDeckName(from outputDirectoryPath: String) -> String {
    URL(fileURLWithPath: outputDirectoryPath).lastPathComponent
}

func inferImageSize(from path: String) throws -> (Int, Int) {
    let url = URL(fileURLWithPath: path)
    let data = try Data(contentsOf: url)
    guard let imageType = detectImageType(data: data) else {
        throw CLIError(message: "Could not infer image dimensions from '\(path)'. Supported image types: PNG, JPEG, WebP.")
    }
    switch imageType {
    case .png:
        let width = Int(data[16...19].reduce(0) { ($0 << 8) | Int($1) })
        let height = Int(data[20...23].reduce(0) { ($0 << 8) | Int($1) })
        return (width, height)
    case .jpeg:
        var index = 2
        while index + 9 < data.count {
            if data[index] != 0xFF { index += 1; continue }
            let marker = data[index + 1]
            let length = Int(UInt16(data[index + 2]) << 8 | UInt16(data[index + 3]))
            if [0xC0,0xC1,0xC2,0xC3,0xC5,0xC6,0xC7,0xC9,0xCA,0xCB,0xCD,0xCE,0xCF].contains(marker) {
                let height = Int(UInt16(data[index + 5]) << 8 | UInt16(data[index + 6]))
                let width = Int(UInt16(data[index + 7]) << 8 | UInt16(data[index + 8]))
                return (width, height)
            }
            if length < 2 { break }
            index += 2 + length
        }
        throw CLIError(message: "Could not infer JPEG dimensions from '\(path)'.")
    case .webp:
        throw CLIError(message: "WebP back images are allowed by the spec, but this script cannot infer WebP dimensions. Use --size [width] [height] when supplying a WebP back image.")
    }
}

func ensureFontExists(_ fontName: String) throws {
#if canImport(AppKit)
    guard NSFont(name: fontName, size: 12) != nil else {
        throw CLIError(message: "Font '\(fontName)' was not found.")
    }
#else
    _ = fontName
#endif
}

func buildStyledParagraphs(for cardName: String, options: Options, cardHeight: Int) -> [StyledParagraph] {
    let generalSize = options.generalFontSize ?? (Double(cardHeight) * 0.12)
    let explicitParagraphs = cardName.components(separatedBy: "\n")
    return explicitParagraphs.enumerated().map { idx, paragraph in
        let lineNo = idx + 1
        let override = options.lineOverrides[lineNo]
        let fontName = override?.fontName ?? options.defaultFontName
        let baseSize: Double
        if let abs = override?.absoluteSize {
            baseSize = abs
        } else if let percent = override?.percentSize {
            baseSize = generalSize * (percent / 100.0)
        } else {
            baseSize = generalSize
        }
        return StyledParagraph(text: paragraph, fontName: fontName, baseFontSize: baseSize)
    }
}

#if canImport(AppKit)
func makeParagraphStyle(alignment: NSTextAlignment = .center, lineBreakMode: NSLineBreakMode = .byWordWrapping) -> NSMutableParagraphStyle {
    let style = NSMutableParagraphStyle()
    style.alignment = alignment
    style.lineBreakMode = lineBreakMode
    return style
}

func wrapParagraph(_ paragraph: StyledParagraph, fontSize: Double, maxWidth: CGFloat) -> [NSAttributedString] {
    let font = NSFont(name: paragraph.fontName, size: CGFloat(fontSize))!
    let paragraphStyle = makeParagraphStyle()
    let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .paragraphStyle: paragraphStyle,
        .foregroundColor: NSColor.black
    ]
    if paragraph.text.isEmpty {
        return [NSAttributedString(string: "", attributes: attrs)]
    }
    let words = paragraph.text.split(whereSeparator: { $0.isWhitespace })
    if words.isEmpty {
        return [NSAttributedString(string: "", attributes: attrs)]
    }
    var lines: [String] = []
    var current = ""
    for wordSub in words {
        let word = String(wordSub)
        let candidate = current.isEmpty ? word : current + " " + word
        let width = (candidate as NSString).size(withAttributes: [.font: font]).width
        if width <= maxWidth || current.isEmpty {
            current = candidate
        } else {
            lines.append(current)
            current = word
        }
    }
    if !current.isEmpty { lines.append(current) }
    return lines.map { NSAttributedString(string: $0, attributes: attrs) }
}

struct LayoutResult {
    let scale: Double
    let paragraphs: [[NSAttributedString]]
    let lineHeightByParagraph: [CGFloat]
    let totalHeight: CGFloat
}

func layoutParagraphs(_ styled: [StyledParagraph], maxWidth: CGFloat, maxHeight: CGFloat) -> LayoutResult {
    let regularGapFactor = 0.15
    let paragraphGapFactor = 0.45
    var scale = 1.0
    while scale > 0.05 {
        var wrapped: [[NSAttributedString]] = []
        var lineHeights: [CGFloat] = []
        var totalHeight: CGFloat = 0
        for (index, para) in styled.enumerated() {
            let size = para.baseFontSize * scale
            let lines = wrapParagraph(para, fontSize: size, maxWidth: maxWidth)
            let font = NSFont(name: para.fontName, size: CGFloat(size))!
            let lineHeight = font.ascender - font.descender + font.leading
            wrapped.append(lines)
            lineHeights.append(lineHeight)
            let linesHeight = CGFloat(lines.count) * lineHeight
            let internalGaps = CGFloat(max(lines.count - 1, 0)) * (lineHeight * regularGapFactor)
            totalHeight += linesHeight + internalGaps
            if index < styled.count - 1 {
                totalHeight += lineHeight * paragraphGapFactor
            }
        }

        var widestFits = true
        for (pIndex, paraLines) in wrapped.enumerated() {
            for line in paraLines {
                if line.size().width > maxWidth + 0.5 {
                    widestFits = false
                    break
                }
            }
            if !widestFits { break }
            if lineHeights[pIndex] > maxHeight + 0.5 {
                widestFits = false
                break
            }
        }
        if widestFits && totalHeight <= maxHeight + 0.5 {
            return LayoutResult(scale: scale, paragraphs: wrapped, lineHeightByParagraph: lineHeights, totalHeight: totalHeight)
        }
        scale *= 0.95
    }
    return LayoutResult(scale: scale, paragraphs: [], lineHeightByParagraph: [], totalHeight: .greatestFiniteMagnitude)
}

func renderCardFace(to path: String, cardName: String, width: Int, height: Int, options: Options) throws {
    let styled = buildStyledParagraphs(for: cardName, options: options, cardHeight: height)
    for para in styled {
        try ensureFontExists(para.fontName)
    }

    let hMargin = CGFloat(options.horizontalMargin ?? Int(round(Double(width) * 0.10)))
    let vMargin = CGFloat(options.verticalMargin ?? Int(round(Double(height) * 0.12)))
    let textRect = NSRect(x: hMargin, y: vMargin, width: CGFloat(width) - 2 * hMargin, height: CGFloat(height) - 2 * vMargin)
    guard textRect.width > 0, textRect.height > 0 else {
        throw CLIError(message: "Margins leave no drawable text box.")
    }

    let layout = layoutParagraphs(styled, maxWidth: textRect.width, maxHeight: textRect.height)
    if layout.paragraphs.isEmpty {
        throw CLIError(message: "Unable to fit text inside card bounds for card name '\(cardName)'.")
    }

    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: width,
        pixelsHigh: height,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        throw CLIError(message: "Failed to create bitmap context for '\(path)'.")
    }

    NSGraphicsContext.saveGraphicsState()
    guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        NSGraphicsContext.restoreGraphicsState()
        throw CLIError(message: "Failed to create graphics context for '\(path)'.")
    }
    NSGraphicsContext.current = context
    defer {
        NSGraphicsContext.restoreGraphicsState()
    }

    NSColor.white.setFill()
    NSBezierPath(rect: NSRect(x: 0, y: 0, width: width, height: height)).fill()

    let regularGapFactor = CGFloat(0.15)
    let paragraphGapFactor = CGFloat(0.45)
    var cursorY = textRect.origin.y + ((textRect.height - layout.totalHeight) / 2.0)

    for reversedParagraphIndex in layout.paragraphs.indices.reversed() {
        let paraLines = layout.paragraphs[reversedParagraphIndex]
        let lineHeight = layout.lineHeightByParagraph[reversedParagraphIndex]
        for reversedLineIndex in paraLines.indices.reversed() {
            let line = paraLines[reversedLineIndex]
            let lineSize = line.size()
            let x = textRect.origin.x + ((textRect.width - lineSize.width) / 2.0)
            let y = cursorY
            line.draw(at: NSPoint(x: x, y: y))
            cursorY += lineHeight
            if reversedLineIndex > paraLines.startIndex {
                cursorY += lineHeight * regularGapFactor
            }
        }
        if reversedParagraphIndex > layout.paragraphs.startIndex {
            cursorY += lineHeight * paragraphGapFactor
        }
    }

    context.flushGraphics()

    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        throw CLIError(message: "Failed to encode PNG for '\(path)'.")
    }
    try png.write(to: URL(fileURLWithPath: path))
}
#else
func runProcess(_ executable: String, _ arguments: [String]) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    let stderr = Pipe()
    process.standardError = stderr
    try process.run()
    process.waitUntilExit()
    if process.terminationStatus != 0 {
        let data = stderr.fileHandleForReading.readDataToEndOfFile()
        let message = String(data: data, encoding: .utf8) ?? ""
        throw CLIError(message: message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "External rendering command failed." : message.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

func findMagick() -> String? {
    let candidates = ["/usr/bin/magick", "/usr/local/bin/magick", "/bin/magick"]
    for c in candidates where FileManager.default.isExecutableFile(atPath: c) { return c }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["bash", "-lc", "command -v magick || command -v convert"]
    let out = Pipe()
    process.standardOutput = out
    try? process.run()
    process.waitUntilExit()
    let data = out.fileHandleForReading.readDataToEndOfFile()
    let value = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    return (value?.isEmpty == false) ? value : nil
}

func renderCardFace(to path: String, cardName: String, width: Int, height: Int, options: Options) throws {
    guard let magick = findMagick() else {
        throw CLIError(message: "Image rendering requires macOS AppKit, or ImageMagick on non-macOS systems.")
    }
    let hMargin = options.horizontalMargin ?? Int(round(Double(width) * 0.10))
    let vMargin = options.verticalMargin ?? Int(round(Double(height) * 0.12))
    let textWidth = width - (2 * hMargin)
    let textHeight = height - (2 * vMargin)
    guard textWidth > 0, textHeight > 0 else {
        throw CLIError(message: "Margins leave no drawable text box.")
    }

    if cardName.isEmpty {
        try runProcess(magick, ["-size", "\(width)x\(height)", "xc:white", path])
        return
    }

    let baseSize = options.generalFontSize ?? (Double(height) * 0.12)
    let renderedText = cardName.replacingOccurrences(of: "\n", with: "\n\n")
    let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
    let textURL = tempDir.appendingPathComponent(UUID().uuidString + ".txt")
    try renderedText.write(to: textURL, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: textURL) }
    try runProcess(magick, [
        "-size", "\(width)x\(height)",
        "xc:white",
        "-font", options.defaultFontName,
        "-fill", "black",
        "-gravity", "center",
        "-interline-spacing", "6",
        "-pointsize", String(Int(round(baseSize))),
        "-annotate", "0", "@\(textURL.path)",
        path
    ])
}
#endif

func createOutputStructure(options: Options, cards: [ParsedLine]) throws {
    let fm = FileManager.default
    let outputURL = URL(fileURLWithPath: options.outputDirectoryPath)
    if fm.fileExists(atPath: outputURL.path) {
        throw CLIError(message: "Output directory already exists: \(outputURL.path)")
    }
    let parent = outputURL.deletingLastPathComponent()
    var isDir: ObjCBool = false
    guard fm.fileExists(atPath: parent.path, isDirectory: &isDir), isDir.boolValue else {
        throw CLIError(message: "Parent directory does not exist: \(parent.path)")
    }

    let inferredSize = try inferImageSize(from: options.backImagePath)
    let finalSize = options.explicitSize ?? inferredSize
    let width = finalSize.0
    let height = finalSize.1
    let manifestHeight = options.explicitHeight ?? height
    let manifestWidth = Int((Double(width) * Double(manifestHeight) / Double(height)).rounded())
    guard manifestWidth > 0 else { throw CLIError(message: "--height results in an invalid deck.json width.") }

    let hMargin = options.horizontalMargin ?? Int(round(Double(width) * 0.10))
    let vMargin = options.verticalMargin ?? Int(round(Double(height) * 0.12))
    guard hMargin >= 0, vMargin >= 0 else {
        throw CLIError(message: "Margins cannot be negative.")
    }
    guard width - (2 * hMargin) > 0, height - (2 * vMargin) > 0 else {
        throw CLIError(message: "Margins leave no usable text box.")
    }

    try ensureFontExists(options.defaultFontName)
    for (line, override) in options.lineOverrides.sorted(by: { $0.key < $1.key }) {
        if let name = override.fontName {
            try ensureFontExists(name)
        }
        if override.absoluteSize != nil && override.percentSize != nil {
            throw CLIError(message: "Line \(line) cannot use both --lfsize and --lfsizep.")
        }
    }

    try fm.createDirectory(at: outputURL, withIntermediateDirectories: false)
    let imagiaURL = outputURL.appendingPathComponent("imagia", isDirectory: true)
    try fm.createDirectory(at: imagiaURL, withIntermediateDirectories: false)

    let backImageData = try Data(contentsOf: URL(fileURLWithPath: options.backImagePath))
    guard let backImageType = detectImageType(data: backImageData) else {
        throw CLIError(message: "Back image must be a PNG, JPEG, or WebP file.")
    }
    let sourceBackExt = URL(fileURLWithPath: options.backImagePath).pathExtension.lowercased()
    switch backImageType {
    case .png:
        guard sourceBackExt == "png" else {
            throw CLIError(message: "Back image extension must be .png for a PNG file.")
        }
    case .jpeg:
        guard sourceBackExt == "jpg" || sourceBackExt == "jpeg" else {
            throw CLIError(message: "Back image extension must be .jpg or .jpeg for a JPEG file.")
        }
    case .webp:
        guard sourceBackExt == "webp" else {
            throw CLIError(message: "Back image extension must be .webp for a WebP file.")
        }
    }
    let backFilename = sourceBackExt.isEmpty ? "back.\(backImageType.preferredExtension)" : "back.\(sourceBackExt)"
    let copiedBackURL = imagiaURL.appendingPathComponent(backFilename)
    try fm.copyItem(at: URL(fileURLWithPath: options.backImagePath), to: copiedBackURL)

    let digits = String(max(cards.count, 1)).count
    var jsonCards: [CardRecord] = []
    for (idx, parsed) in cards.enumerated() {
        let number = idx + 1
        let numberString = String(format: "%0*d", digits, number)
        let frontFilename = "card-\(numberString).png"
        let frontURL = imagiaURL.appendingPathComponent(frontFilename)
        try renderCardFace(to: frontURL.path, cardName: parsed.cardName, width: width, height: height, options: options)
        jsonCards.append(CardRecord(id: "card-\(numberString)", name: parsed.cardName, frontImage: "imagia/\(frontFilename)", meta: [:]))
    }

    let outputDirName = deriveDeckName(from: outputURL.path)
    let deckName = options.deckName ?? outputDirName
    let deckId = options.deckId ?? sanitizeDeckId(outputDirName)
    let deck = DeckFile(format: cartoVantaFormatIdentifier, deckId: deckId, deckName: deckName, version: options.version, backImage: "imagia/\(backFilename)", cardSize: CardSize(width: manifestWidth, height: manifestHeight), meta: [:], cards: jsonCards)
    let outerMeta = OuterMetaFile(format: cartoVantaFormatIdentifier, deckName: deckName, meta: [:])

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
    let jsonData = try encoder.encode(deck)
    try jsonData.write(to: outputURL.appendingPathComponent("deck.json"))
    let outerMetaData = try encoder.encode(outerMeta)
    try outerMetaData.write(to: outputURL.appendingPathComponent("meta.json"))

    let sourceText: String = options.explicitSize == nil ? "inferred from back image" : "overridden by --size"
    let notes = """
Original generated card dimensions: \(width) x \(height) pixels
Dimension source: \(sourceText)
Total card count: \(cards.count)
Back image source: \(options.backImagePath)
Input file source: \(options.inputFilePath)
Generated front image format: PNG
CartoVanta format identifier: \(cartoVantaFormatIdentifier)
Default font: \(options.defaultFontName)

"""
    try notes.write(to: outputURL.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)
}

do {
    let rawArgs = Array(CommandLine.arguments.dropFirst())
    if let options = try parseArguments(rawArgs) {
        let cards = try parseNamesFile(at: options.inputFilePath)
        try createOutputStructure(options: options, cards: cards)
    }
} catch let error as CLIError {
    fail(error.message)
} catch {
    fail(error.localizedDescription)
}
