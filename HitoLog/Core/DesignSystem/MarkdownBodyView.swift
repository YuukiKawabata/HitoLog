import SwiftUI

/// 記事本文の Markdown を、ブロック単位で paper×ink デザインに沿って描画するレンダラー。
///
/// 外部依存は使わず、ブロック構造（見出し・引用・リスト・区切り線・段落）は自前で分割し、
/// 各ブロック内のインライン装飾（**太字** / *斜体* / `code` / [text](url)）は
/// iOS17 の `AttributedString(markdown:)` に委譲する。
/// Markdown 記号を含まないプレーンテキストは、そのまま段落として描画される（後方互換）。
struct MarkdownBodyView: View {
    let markdown: String

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            ForEach(Array(MarkdownBlock.parse(markdown).enumerated()), id: \.offset) { _, block in
                MarkdownBlockView(block: block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - ブロックモデル

enum MarkdownBlock {
    case heading(level: Int, text: String)
    case quote(String)
    case bulletList([String])
    case orderedList([String])
    case rule
    case paragraph(String)

    /// Markdown 文字列を行スキャンでブロック配列に変換する。
    static func parse(_ markdown: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var bullets: [String] = []
        var ordered: [String] = []
        var quotes: [String] = []

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            blocks.append(.paragraph(paragraph.joined(separator: "\n")))
            paragraph.removeAll()
        }
        func flushBullets() {
            guard !bullets.isEmpty else { return }
            blocks.append(.bulletList(bullets))
            bullets.removeAll()
        }
        func flushOrdered() {
            guard !ordered.isEmpty else { return }
            blocks.append(.orderedList(ordered))
            ordered.removeAll()
        }
        func flushQuotes() {
            guard !quotes.isEmpty else { return }
            blocks.append(.quote(quotes.joined(separator: "\n")))
            quotes.removeAll()
        }
        func flushAll() {
            flushParagraph()
            flushBullets()
            flushOrdered()
            flushQuotes()
        }

        for rawLine in markdown.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            if line.isEmpty {
                flushAll()
                continue
            }
            if line == "---" || line == "***" || line == "___" {
                flushAll()
                blocks.append(.rule)
                continue
            }
            if let heading = headingMatch(line) {
                flushAll()
                blocks.append(.heading(level: heading.level, text: heading.text))
                continue
            }
            if line.hasPrefix(">") {
                flushParagraph(); flushBullets(); flushOrdered()
                quotes.append(String(line.dropFirst()).trimmingCharacters(in: .whitespaces))
                continue
            }
            if line.hasPrefix("- ") || line.hasPrefix("* ") {
                flushParagraph(); flushOrdered(); flushQuotes()
                bullets.append(String(line.dropFirst(2)))
                continue
            }
            if let item = orderedMatch(line) {
                flushParagraph(); flushBullets(); flushQuotes()
                ordered.append(item)
                continue
            }
            flushBullets(); flushOrdered(); flushQuotes()
            paragraph.append(line)
        }
        flushAll()
        return blocks
    }

    private static func headingMatch(_ line: String) -> (level: Int, text: String)? {
        var level = 0
        var index = line.startIndex
        while index < line.endIndex, line[index] == "#" {
            level += 1
            index = line.index(after: index)
        }
        guard (1...3).contains(level), index < line.endIndex, line[index] == " " else { return nil }
        let text = String(line[index...]).trimmingCharacters(in: .whitespaces)
        return (level, text)
    }

    /// "1. 本文" 形式の番号付きリスト項目を判定する（"3.14" のような小数は除外）。
    private static func orderedMatch(_ line: String) -> String? {
        guard let dotRange = line.range(of: ". ") else { return nil }
        let prefix = line[line.startIndex..<dotRange.lowerBound]
        guard !prefix.isEmpty, prefix.allSatisfy(\.isNumber) else { return nil }
        return String(line[dotRange.upperBound...])
    }
}

// MARK: - ブロック描画

private struct MarkdownBlockView: View {
    let block: MarkdownBlock

    var body: some View {
        switch block {
        case let .heading(level, text):
            Text(MarkdownInline.attributed(text))
                .font(headingFont(level))
                .foregroundStyle(AppColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, level == 1 ? AppSpacing.sm : AppSpacing.xs)

        case let .paragraph(text):
            Text(MarkdownInline.attributed(text))
                .font(AppFont.body)
                .lineSpacing(6)
                .foregroundStyle(AppColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

        case let .quote(text):
            HStack(alignment: .top, spacing: AppSpacing.sm) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(AppColor.accent.opacity(0.55))
                    .frame(width: 3)
                Text(MarkdownInline.attributed(text))
                    .font(AppFont.body.italic())
                    .lineSpacing(6)
                    .foregroundStyle(AppColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .fixedSize(horizontal: false, vertical: true)

        case let .bulletList(items):
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    listRow(marker: "•", text: item)
                }
            }

        case let .orderedList(items):
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    listRow(marker: "\(index + 1).", text: item)
                }
            }

        case .rule:
            InkDivider()
                .padding(.vertical, AppSpacing.xs)
        }
    }

    private func listRow(marker: String, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: AppSpacing.sm) {
            Text(marker)
                .font(AppFont.body)
                .foregroundStyle(AppColor.textSecondary)
            Text(MarkdownInline.attributed(text))
                .font(AppFont.body)
                .lineSpacing(6)
                .foregroundStyle(AppColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: return AppFont.title
        case 2: return AppFont.sectionTitle
        default: return .system(size: 16, weight: .semibold, design: .serif)
        }
    }
}

// MARK: - インライン Markdown

enum MarkdownInline {
    /// 1ブロック分のテキストをインライン Markdown として解釈した AttributedString を返す。
    /// 解釈に失敗した場合はプレーン文字列にフォールバックする。
    static func attributed(_ string: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            allowsExtendedAttributes: true,
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        var attributed = (try? AttributedString(markdown: string, options: options)) ?? AttributedString(string)
        let linkRanges = attributed.runs.compactMap { $0.link == nil ? nil : $0.range }
        for range in linkRanges {
            attributed[range].foregroundColor = AppColor.accent
        }
        // 素のURL自動リンク・#タグ色付けを重ねる（投稿・記事で共通）
        InlineRichText.applyEnrichments(to: &attributed)
        return attributed
    }
}
