import AppKit
import PDFKit

/// PDF → Word, plain text or Markdown.
///
/// A PDF stores positioned lines, not paragraphs, so the text is rebuilt first: wrapped lines are
/// joined back into paragraphs (also across page breaks), and lines sharing a row (table cells)
/// are joined with tabs. Fonts, bold, italics and sizes carry over into Word and drive Markdown's
/// headings and emphasis. Layout (columns, real tables, images) doesn't survive, and scanned
/// PDFs have no text to extract.
enum PDFText {
    static func convert(_ source: URL, to format: ConvertFormat, output: URL) throws {
        guard let doc = PDFDocument(url: source) else { throw ConvertError.unreadable(source) }
        let text = reflowedText(of: doc)
        guard !text.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ConvertError.noText(source)
        }

        let data: Data
        switch format {
        case .docx:
            let spacing = NSMutableParagraphStyle()
            spacing.paragraphSpacing = 6
            text.addAttribute(.paragraphStyle, value: spacing, range: NSRange(location: 0, length: text.length))
            data = try text.data(
                from: NSRange(location: 0, length: text.length),
                documentAttributes: [.documentType: NSAttributedString.DocumentType.officeOpenXML]
            )
        case .md:
            data = Data(MarkdownWriter.markdown(from: text).utf8)
        case .txt:
            data = Data(text.string.utf8)
        default:
            throw ConvertError.unsupported(source, format)
        }
        do { try data.write(to: output) } catch { throw ConvertError.writeFailed(output) }
    }

    // MARK: Reflow

    private struct Line {
        let text: NSAttributedString
        let rect: CGRect
        let page: Int
        /// Right end of the longest line on this line's page: where wrapped lines end.
        var rightEdge: CGFloat = 0
    }

    /// The document's text with one paragraph per line ("\n") and table cells separated by tabs.
    private static func reflowedText(of doc: PDFDocument) -> NSMutableAttributedString {
        var lines: [Line] = []
        for index in 0 ..< doc.pageCount {
            guard let page = doc.page(at: index) else { continue }
            var pageLines = textLines(on: page, index: index)
            let rightEdge = pageLines.map(\.rect.maxX).max() ?? 0
            for i in pageLines.indices { pageLines[i].rightEdge = rightEdge }
            lines += pageLines
        }

        let result = NSMutableAttributedString()
        var inRow = false
        for (index, line) in lines.enumerated() {
            result.append(line.text)
            guard index + 1 < lines.count else { break }
            let next = lines[index + 1]
            let separator: String
            if next.page == line.page, next.rect.minX > line.rect.maxX, overlapsVertically(line.rect, next.rect) {
                separator = "\t" // next cell on the same row
                inRow = true
            } else if !inRow, continues(line, into: next) {
                separator = line.text.string.hasSuffix(" ") ? "" : " "
            } else {
                separator = "\n" // table rows always end their paragraph
                inRow = false
            }
            result.append(NSAttributedString(string: separator))
        }
        result.append(NSAttributedString(string: "\n"))
        return result
    }

    private static func textLines(on page: PDFPage, index: Int) -> [Line] {
        let selections = page.selection(for: page.bounds(for: .cropBox))?.selectionsByLine() ?? []
        var lines: [Line] = selections.compactMap { selection in
            guard let string = selection.attributedString,
                  !string.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { return nil }
            let trimmed = NSMutableAttributedString(attributedString: string)
            while let last = trimmed.string.last, last.isNewline {
                trimmed.deleteCharacters(in: NSRange(location: trimmed.length - 1, length: 1))
            }
            return Line(text: trimmed, rect: selection.bounds(for: page), page: index)
        }
        // Page numbers ("3", "Page 3", "3 of 12") at the top or bottom of the page.
        if let last = lines.last, isPageNumber(last) { lines.removeLast() }
        if let first = lines.first, isPageNumber(first) { lines.removeFirst() }
        return lines
    }

    private static func isPageNumber(_ line: Line) -> Bool {
        line.text.string.trimmingCharacters(in: .whitespaces).range(
            of: #"^(page\s+)?\d{1,4}(\s*(of|/)\s*\d{1,4})?$"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }

    private static func overlapsVertically(_ a: CGRect, _ b: CGRect) -> Bool {
        min(a.maxY, b.maxY) - max(a.minY, b.minY) > min(a.height, b.height) / 2
    }

    /// Whether `next` is the same paragraph wrapped onto a new line: same text size, `line` runs
    /// to the right margin, `next` doesn't start a list item, and it sits just below (or at the
    /// top of the following page).
    private static func continues(_ line: Line, into next: Line) -> Bool {
        let closeBelow: Bool
        if next.page == line.page {
            let gap = line.rect.minY - next.rect.maxY
            closeBelow = gap >= -1 && gap < line.rect.height * 0.6
        } else {
            closeBelow = next.page == line.page + 1
        }
        // Table-of-contents entries ("Overview ........ 3") reach the margin but stand alone.
        let isContentsEntry = line.text.string.range(of: #"\.{4,}\s*\d+\s*$"#, options: .regularExpression) != nil
        return closeBelow && !isContentsEntry
            && abs(line.rect.height - next.rect.height) < 2
            && line.rect.maxX > line.rightEdge - 40
            && !MarkdownWriter.startsListItem(next.text.string)
    }
}

// MARK: - Markdown

/// Turns reflowed PDF text into Markdown: bigger-than-body paragraphs become headings, bold and
/// italic runs get `**`/`*`, bullets become `- ` items, and runs of tab-separated rows become tables.
enum MarkdownWriter {
    static let bullets: Set<Character> = ["•", "◦", "▪", "●", "○", "■", "–", "-", "*"]

    static func startsListItem(_ string: String) -> Bool {
        let start = string.trimmingCharacters(in: .whitespaces)
        return start.first.map(bullets.contains) == true
            || start.range(of: #"^\d{1,2}[.)]\s"#, options: .regularExpression) != nil
    }

    private enum Block {
        case heading(Int, String)
        case paragraph(String)
        case item(String)
        case row([String])
    }

    static func markdown(from text: NSAttributedString) -> String {
        let paragraphs = split(text)
        let body = bodySize(of: text)
        // The distinct sizes clearly bigger than body text, largest first: #, ##, ###.
        let headingSizes = Array(Set(paragraphs.map { round(maxSize(of: $0)) }.filter { $0 >= body * 1.15 }))
            .sorted(by: >)

        let blocks: [Block] = paragraphs.compactMap { paragraph in
            let plain = paragraph.string.trimmingCharacters(in: .whitespaces)
            guard !plain.isEmpty else { return nil }
            if plain.contains("\t") {
                return .row(plain.components(separatedBy: "\t").map { escape($0.trimmingCharacters(in: .whitespaces)) })
            }
            if let level = headingSizes.firstIndex(of: round(maxSize(of: paragraph))), plain.count <= 120 {
                return .heading(min(level + 1, 3), escape(plain))
            }
            if startsListItem(plain) {
                // "• Item" → "- Item"; numbered items keep their numbers.
                guard let marker = paragraph.string.range(of: #"^\s*[•◦▪●○■–\-*]\s*"#, options: .regularExpression) else {
                    return .item(inline(paragraph))
                }
                let rest = paragraph.attributedSubstring(from: NSRange(marker.upperBound..., in: paragraph.string))
                return .item("- " + inline(rest))
            }
            return .paragraph(inline(paragraph))
        }
        return render(blocks)
    }

    private static func render(_ blocks: [Block]) -> String {
        var out: [String] = []
        var index = 0
        while index < blocks.count {
            switch blocks[index] {
            case let .heading(level, text):
                out.append(String(repeating: "#", count: level) + " " + text)
            case let .paragraph(text):
                out.append(text)
            case .item:
                var items: [String] = []
                while index < blocks.count, case let .item(text) = blocks[index] {
                    items.append(text)
                    index += 1
                }
                out.append(items.joined(separator: "\n"))
                continue
            case .row:
                var rows: [[String]] = []
                while index < blocks.count, case let .row(cells) = blocks[index] {
                    rows.append(cells)
                    index += 1
                }
                out.append(table(rows))
                continue
            }
            index += 1
        }
        return out.joined(separator: "\n\n") + "\n"
    }

    /// The first row becomes the header; a lone row is just its cells side by side.
    private static func table(_ rows: [[String]]) -> String {
        guard rows.count > 1 else { return rows[0].joined(separator: " · ") }
        let columns = rows.map(\.count).max() ?? 0
        let lines = rows.map { cells in
            "| " + (cells + Array(repeating: "", count: columns - cells.count)).joined(separator: " | ") + " |"
        }
        let rule = "|" + Array(repeating: " --- |", count: columns).joined()
        return ([lines[0], rule] + lines.dropFirst()).joined(separator: "\n")
    }

    // MARK: Inline

    /// The paragraph with `**bold**` and `*italic*` runs.
    private static func inline(_ paragraph: NSAttributedString) -> String {
        var runs: [(text: String, bold: Bool, italic: Bool)] = []
        paragraph.enumerateAttribute(.font, in: NSRange(location: 0, length: paragraph.length)) { value, range, _ in
            let traits = (value as? NSFont)?.fontDescriptor.symbolicTraits ?? []
            let text = (paragraph.string as NSString).substring(with: range)
            let bold = traits.contains(.bold), italic = traits.contains(.italic)
            if let last = runs.last, last.bold == bold, last.italic == italic {
                runs[runs.count - 1].text += text
            } else {
                runs.append((text, bold, italic))
            }
        }

        return runs.map { run -> String in
            let marker = (run.bold ? "**" : "") + (run.italic ? "*" : "")
            let core = run.text.trimmingCharacters(in: .whitespaces)
            guard !marker.isEmpty, !core.isEmpty else { return escape(run.text) }
            // Keep the spaces outside the markers, or Markdown won't treat them as emphasis.
            let leading = String(run.text.prefix { $0 == " " }), trailing = String(run.text.reversed().prefix { $0 == " " })
            return leading + marker + escape(core) + String(marker.reversed()) + trailing
        }.joined().trimmingCharacters(in: .whitespaces)
    }

    private static func escape(_ text: String) -> String {
        var out = text
        for char in ["\\", "*", "_", "`"] {
            out = out.replacingOccurrences(of: char, with: "\\" + char)
        }
        if out.first == "#" { out = "\\" + out }
        return out
    }

    // MARK: Helpers

    private static func split(_ text: NSAttributedString) -> [NSAttributedString] {
        var paragraphs: [NSAttributedString] = []
        (text.string as NSString).enumerateSubstrings(
            in: NSRange(location: 0, length: text.length), options: .byParagraphs
        ) { _, range, _, _ in
            paragraphs.append(text.attributedSubstring(from: range))
        }
        return paragraphs
    }

    /// The font size covering the most characters.
    private static func bodySize(of text: NSAttributedString) -> CGFloat {
        var counts: [CGFloat: Int] = [:]
        text.enumerateAttribute(.font, in: NSRange(location: 0, length: text.length)) { value, range, _ in
            if let font = value as? NSFont { counts[round(font.pointSize), default: 0] += range.length }
        }
        return counts.max { $0.value < $1.value }?.key ?? 12
    }

    private static func maxSize(of paragraph: NSAttributedString) -> CGFloat {
        var size: CGFloat = 0
        paragraph.enumerateAttribute(.font, in: NSRange(location: 0, length: paragraph.length)) { value, _, _ in
            size = max(size, (value as? NSFont)?.pointSize ?? 0)
        }
        return size
    }
}
