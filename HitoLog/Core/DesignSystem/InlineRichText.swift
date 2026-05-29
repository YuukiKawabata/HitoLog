import SwiftUI

/// プレーン／Markdown 解釈済みのテキストに、軽量な装飾を後付けするユーティリティ。
///
/// - URL は自動リンク化（`Text` が描画時にタップ可能にする）し、アクセント色で強調
/// - `#タグ` / `＃タグ`（`TopicExtractor` と同じ許容文字）をアクセント色で強調
///
/// `MarkdownInline` / `MarkdownBodyView` のインライン解釈結果にも適用され、
/// 記事・投稿で同じ装飾ルールを共有する。
enum InlineRichText {
    private static let hashtagRegex = try? NSRegularExpression(
        pattern: "[#＃][\\p{L}\\p{N}_ー－-]{2,}"
    )
    private static let linkDetector = try? NSDataDetector(
        types: NSTextCheckingResult.CheckingType.link.rawValue
    )

    /// プレーンテキストを装飾付き AttributedString に変換する（コメントなど Markdown 非対応箇所用）。
    static func attributedBody(_ text: String) -> AttributedString {
        var attributed = AttributedString(text)
        applyEnrichments(to: &attributed)
        return attributed
    }

    /// 既存の AttributedString に URL自動リンク化＋`#タグ`色付けを適用する。
    /// フォント・基本色は変更しないため、呼び出し側のスタイルを継承する。
    static func applyEnrichments(to attributed: inout AttributedString) {
        let plain = String(attributed.characters)
        guard !plain.isEmpty else { return }
        let fullRange = NSRange(location: 0, length: (plain as NSString).length)

        if let hashtagRegex {
            for match in hashtagRegex.matches(in: plain, range: fullRange) {
                guard let range = attributedRange(for: match.range, in: attributed, plain: plain) else { continue }
                attributed[range].foregroundColor = AppColor.accent
            }
        }

        if let linkDetector {
            for match in linkDetector.matches(in: plain, range: fullRange) {
                guard let url = match.url,
                      let range = attributedRange(for: match.range, in: attributed, plain: plain) else { continue }
                attributed[range].link = url
                attributed[range].foregroundColor = AppColor.accent
            }
        }
    }

    /// NSRange（レンダリング後プレーン文字列基準）を AttributedString のレンジへ変換する。
    private static func attributedRange(
        for nsRange: NSRange,
        in attributed: AttributedString,
        plain: String
    ) -> Range<AttributedString.Index>? {
        guard let stringRange = Range(nsRange, in: plain) else { return nil }
        let lowerOffset = plain.distance(from: plain.startIndex, to: stringRange.lowerBound)
        let length = plain.distance(from: stringRange.lowerBound, to: stringRange.upperBound)
        let characters = attributed.characters
        guard let lower = characters.index(characters.startIndex, offsetBy: lowerOffset, limitedBy: characters.endIndex),
              let upper = characters.index(lower, offsetBy: length, limitedBy: characters.endIndex) else {
            return nil
        }
        return lower..<upper
    }
}
