import UIKit

final class NoPasteTextView: UITextView {
    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(UIResponderStandardEditActions.paste(_:)) {
            return false
        }
        return super.canPerformAction(action, withSender: sender)
    }

    override func paste(_ sender: Any?) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func configure() {
        backgroundColor = .clear
        font = UIFont.preferredFont(forTextStyle: .body)
        adjustsFontForContentSizeCategory = true
        textContainerInset = UIEdgeInsets(top: 8, left: 6, bottom: 8, right: 6)
        textDragInteraction?.isEnabled = false
        pasteConfiguration = nil
    }

    // MARK: - Markdown 挿入（フォーマットツールバー用）
    //
    // 操作はすべてユーザーのタップ起点で、挿入は最小マーカーのみ（自動プレースホルダ文字なし）。
    // ペースト経路を通らず Human Check の bulk-input 検知にも影響しない。
    // 変更後は delegate へ通知し、Binding とタイピング計測へ反映する。

    @objc func mdToggleHeading() { applyLinePrefix("## ") }
    @objc func mdToggleQuote() { applyLinePrefix("> ") }
    @objc func mdToggleBullet() { applyLinePrefix("- ") }
    @objc func mdBold() { wrapSelection("**") }
    @objc func mdInsertLink() { insertLink() }
    @objc func mdDismissKeyboard() { resignFirstResponder() }

    /// 現在行の行頭にマーカーを挿入（既に付いていれば外す）。
    private func applyLinePrefix(_ marker: String) {
        let source = (text ?? "") as NSString
        let caret = min(selectedRange.location, source.length)
        let lineRange = source.lineRange(for: NSRange(location: caret, length: 0))
        let line = source.substring(with: lineRange)
        let markerLength = (marker as NSString).length

        if line.hasPrefix(marker) {
            let removal = NSRange(location: lineRange.location, length: markerLength)
            text = source.replacingCharacters(in: removal, with: "")
            setCaret(max(lineRange.location, caret - markerLength))
        } else {
            let insertion = NSRange(location: lineRange.location, length: 0)
            text = source.replacingCharacters(in: insertion, with: marker)
            setCaret(caret + markerLength)
        }
        notifyChange()
    }

    /// 選択範囲をマーカーで囲む。無選択時はマーカーのみ挿入し、カーソルを中央に置く。
    private func wrapSelection(_ marker: String) {
        let source = (text ?? "") as NSString
        let range = selectedRange
        let markerLength = (marker as NSString).length

        if range.length > 0 {
            let selected = source.substring(with: range)
            text = source.replacingCharacters(in: range, with: marker + selected + marker)
            setCaret(range.location + markerLength + range.length + markerLength)
        } else {
            text = source.replacingCharacters(in: range, with: marker + marker)
            setCaret(range.location + markerLength)
        }
        notifyChange()
    }

    /// `[ラベル](url)` を挿入し、`url` 部分を選択状態にする（上書き入力しやすくする）。
    private func insertLink() {
        let source = (text ?? "") as NSString
        let range = selectedRange
        let label = range.length > 0 ? source.substring(with: range) : ""
        let snippet = "[\(label)](url)"
        text = source.replacingCharacters(in: range, with: snippet)

        let urlLocation = range.location + ("[\(label)](" as NSString).length
        selectedRange = NSRange(location: urlLocation, length: ("url" as NSString).length)
        notifyChange()
    }

    private func setCaret(_ location: Int) {
        let clamped = max(0, min(location, (text as NSString?)?.length ?? 0))
        selectedRange = NSRange(location: clamped, length: 0)
    }

    private func notifyChange() {
        delegate?.textViewDidChange?(self)
    }
}

