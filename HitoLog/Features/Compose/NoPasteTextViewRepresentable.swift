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

struct NoPasteTextViewRepresentable: UIViewRepresentable {
    @Binding var text: String
    var onTextChanged: (String, String) -> Void
    var accessory: EditorAccessory = .none

    func makeUIView(context: Context) -> NoPasteTextView {
        let textView = NoPasteTextView()
        textView.delegate = context.coordinator
        textView.text = text
        context.coordinator.previousText = text
        textView.inputAccessoryView = Self.makeToolbar(for: textView, accessory: accessory)
        return textView
    }

    private static func makeToolbar(for textView: NoPasteTextView, accessory: EditorAccessory) -> UIToolbar? {
        guard accessory != .none else { return nil }

        let bar = UIToolbar()
        bar.tintColor = UIColor(AppColor.accent)

        func item(_ systemName: String, _ action: Selector, label: String) -> UIBarButtonItem {
            let button = UIBarButtonItem(
                image: UIImage(systemName: systemName),
                style: .plain,
                target: textView,
                action: action
            )
            button.accessibilityLabel = label
            return button
        }

        let spacer = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        let done = UIBarButtonItem(barButtonSystemItem: .done, target: textView, action: #selector(NoPasteTextView.mdDismissKeyboard))

        if accessory == .formatting {
            bar.items = [
                item("textformat.size", #selector(NoPasteTextView.mdToggleHeading), label: "見出し"),
                item("bold", #selector(NoPasteTextView.mdBold), label: "太字"),
                item("text.quote", #selector(NoPasteTextView.mdToggleQuote), label: "引用"),
                item("list.bullet", #selector(NoPasteTextView.mdToggleBullet), label: "箇条書き"),
                item("link", #selector(NoPasteTextView.mdInsertLink), label: "リンク"),
                spacer,
                done
            ]
        } else {
            bar.items = [spacer, done]
        }
        bar.sizeToFit()
        return bar
    }

    func updateUIView(_ uiView: NoPasteTextView, context: Context) {
        if uiView.text != text {
            uiView.text = text
            context.coordinator.previousText = text
        }
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
    }
}

