import SwiftUI
import UIKit

/// エディタのキーボード上アクセサリの種類。
/// - none: なし
/// - dismiss: 「完了」だけ（キーボードを閉じる用。投稿など Markdown 非対応のエディタ向け）
/// - formatting: Markdown 書式ボタン＋「完了」（記事エディタ向け）
enum EditorAccessory {
    case none
    case dismiss
    case formatting
}

/// テキストビューへプログラム的に文字列を挿入するためのハンドル。
/// SwiftUI 側が保持し、メディア選択完了後にカーソル位置へ Markdown を差し込むのに使う。
final class TextInsertionController {
    fileprivate weak var textView: NoPasteTextView?

    func insert(_ snippet: String) {
        textView?.insertMediaSnippet(snippet)
    }
}

struct NoPasteTextViewRepresentable: UIViewRepresentable {
    @Binding var text: String
    var onTextChanged: (String, String) -> Void
    var accessory: EditorAccessory = .none
    var onRequestMediaInsert: (() -> Void)?
    var insertionController: TextInsertionController?

    func makeUIView(context: Context) -> NoPasteTextView {
        let textView = NoPasteTextView()
        textView.delegate = context.coordinator
        textView.text = text
        context.coordinator.previousText = text
        textView.onRequestMediaInsert = onRequestMediaInsert
        insertionController?.textView = textView
        textView.inputAccessoryView = Self.makeAccessory(for: textView, accessory: accessory)
        return textView
    }

    private static func makeAccessory(for textView: NoPasteTextView, accessory: EditorAccessory) -> UIView? {
        switch accessory {
        case .none:
            return nil
        case .dismiss:
            let bar = UIToolbar()
            bar.tintColor = UIColor(AppColor.accent)
            bar.items = [
                UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil),
                UIBarButtonItem(barButtonSystemItem: .done, target: textView, action: #selector(NoPasteTextView.mdDismissKeyboard))
            ]
            bar.sizeToFit()
            return bar
        case .formatting:
            return FormattingAccessoryView(textView: textView, showsMedia: textView.onRequestMediaInsert != nil)
        }
    }

    func updateUIView(_ uiView: NoPasteTextView, context: Context) {
        if uiView.text != text {
            uiView.text = text
            context.coordinator.previousText = text
        }
        uiView.onRequestMediaInsert = onRequestMediaInsert
        insertionController?.textView = uiView
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        private var parent: NoPasteTextViewRepresentable
        var previousText = ""

        init(_ parent: NoPasteTextViewRepresentable) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            let newText = textView.text ?? ""
            let oldText = previousText
            previousText = newText
            parent.text = newText
            parent.onTextChanged(oldText, newText)
        }

        /// 改行時にリスト項目を自動継続する。空のリスト項目で改行した場合はマーカーを外してリストを終了する。
        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            guard text == "\n" else { return true }

            let source = (textView.text ?? "") as NSString
            let lineRange = source.lineRange(for: NSRange(location: range.location, length: 0))
            var line = source.substring(with: lineRange)
            if line.hasSuffix("\n") { line.removeLast() }

            guard let item = Self.listItem(of: line) else { return true }

            if item.isEmpty {
                // 空項目で改行 → マーカーを削除してリストを終了する。
                let markerRange = NSRange(location: lineRange.location, length: (item.marker as NSString).length)
                textView.text = source.replacingCharacters(in: markerRange, with: "")
                textView.selectedRange = NSRange(location: lineRange.location, length: 0)
            } else {
                // 内容がある → 改行して次のマーカーを自動挿入する。
                let insertion = "\n" + Self.nextMarker(after: item.marker)
                textView.text = source.replacingCharacters(in: range, with: insertion)
                textView.selectedRange = NSRange(location: range.location + (insertion as NSString).length, length: 0)
            }

            textViewDidChange(textView)
            return false
        }

        /// 行頭のリストマーカー（`- ` / `* ` / `N. `）と、その行が空項目かどうかを返す。
        private static func listItem(of line: String) -> (marker: String, isEmpty: Bool)? {
            for bullet in ["- ", "* "] where line.hasPrefix(bullet) {
                let content = String(line.dropFirst(bullet.count))
                return (bullet, content.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            if let dotRange = line.range(of: ". ") {
                let numberPart = line[line.startIndex..<dotRange.lowerBound]
                if !numberPart.isEmpty, numberPart.allSatisfy(\.isNumber) {
                    let marker = String(line[line.startIndex..<dotRange.upperBound])
                    let content = String(line[dotRange.upperBound...])
                    return (marker, content.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }

            return nil
        }

        /// 番号付きリストは番号を +1 した次のマーカーを、箇条書きは同じマーカーを返す。
        private static func nextMarker(after marker: String) -> String {
            if marker.hasSuffix(". "), let number = Int(marker.dropLast(2)) {
                return "\(number + 1). "
            }
            return marker
        }
    }
}

/// Markdown 書式ボタンを横スクロールで並べるキーボードアクセサリ。
///
/// ボタン数が増えても画面幅をはみ出さないよう、書式ボタン群はスクロールビューに収め、
/// 「完了」だけを右端に固定する。各ボタンは `NoPasteTextView` のセレクタを直接呼ぶ。
private final class FormattingAccessoryView: UIView {
    private struct FormatButton {
        let symbol: String
        let action: Selector
        let label: String
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: 48)
    }

    init(textView: NoPasteTextView, showsMedia: Bool) {
        var buttons: [FormatButton] = [
            FormatButton(symbol: "textformat.size", action: #selector(NoPasteTextView.mdToggleHeading), label: "見出し"),
            FormatButton(symbol: "bold", action: #selector(NoPasteTextView.mdBold), label: "太字"),
            FormatButton(symbol: "italic", action: #selector(NoPasteTextView.mdItalic), label: "斜体"),
            FormatButton(symbol: "chevron.left.forwardslash.chevron.right", action: #selector(NoPasteTextView.mdCode), label: "コード"),
            FormatButton(symbol: "text.quote", action: #selector(NoPasteTextView.mdToggleQuote), label: "引用"),
            FormatButton(symbol: "list.bullet", action: #selector(NoPasteTextView.mdToggleBullet), label: "箇条書き"),
            FormatButton(symbol: "list.number", action: #selector(NoPasteTextView.mdToggleOrdered), label: "番号付きリスト"),
            FormatButton(symbol: "link", action: #selector(NoPasteTextView.mdInsertLink), label: "リンク"),
            FormatButton(symbol: "minus", action: #selector(NoPasteTextView.mdInsertRule), label: "区切り線")
        ]
        if showsMedia {
            buttons.append(FormatButton(symbol: "photo.badge.plus", action: #selector(NoPasteTextView.mdInsertMedia), label: "写真・動画"))
        }

        super.init(frame: CGRect(x: 0, y: 0, width: 0, height: 48))
        autoresizingMask = .flexibleWidth
        backgroundColor = UIColor.secondarySystemBackground

        let accent = UIColor(AppColor.accent)

        let topBorder = UIView()
        topBorder.backgroundColor = UIColor.separator
        topBorder.translatesAutoresizingMaskIntoConstraints = false
        addSubview(topBorder)

        let doneButton = UIButton(type: .system)
        doneButton.setTitle("完了", for: .normal)
        doneButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        doneButton.tintColor = accent
        doneButton.setTitleColor(accent, for: .normal)
        doneButton.addTarget(textView, action: #selector(NoPasteTextView.mdDismissKeyboard), for: .touchUpInside)
        doneButton.setContentHuggingPriority(.required, for: .horizontal)
        doneButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        doneButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(doneButton)

        let separator = UIView()
        separator.backgroundColor = UIColor.separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(separator)

        let scrollView = UIScrollView()
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.alwaysBounceHorizontal = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)

        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 4
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)

        for definition in buttons {
            let button = UIButton(type: .system)
            button.setImage(UIImage(systemName: definition.symbol), for: .normal)
            button.tintColor = accent
            button.accessibilityLabel = definition.label
            button.addTarget(textView, action: definition.action, for: .touchUpInside)
            button.translatesAutoresizingMaskIntoConstraints = false
            button.widthAnchor.constraint(equalToConstant: 44).isActive = true
            stack.addArrangedSubview(button)
        }

        let content = scrollView.contentLayoutGuide
        let frameGuide = scrollView.frameLayoutGuide

        NSLayoutConstraint.activate([
            topBorder.topAnchor.constraint(equalTo: topAnchor),
            topBorder.leadingAnchor.constraint(equalTo: leadingAnchor),
            topBorder.trailingAnchor.constraint(equalTo: trailingAnchor),
            topBorder.heightAnchor.constraint(equalToConstant: 0.5),

            doneButton.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -16),
            doneButton.centerYAnchor.constraint(equalTo: centerYAnchor),

            separator.trailingAnchor.constraint(equalTo: doneButton.leadingAnchor, constant: -8),
            separator.widthAnchor.constraint(equalToConstant: 0.5),
            separator.heightAnchor.constraint(equalToConstant: 26),
            separator.centerYAnchor.constraint(equalTo: centerYAnchor),

            scrollView.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor),
            scrollView.topAnchor.constraint(equalTo: topBorder.bottomAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            scrollView.trailingAnchor.constraint(equalTo: separator.leadingAnchor, constant: -8),

            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            stack.heightAnchor.constraint(equalTo: frameGuide.heightAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

