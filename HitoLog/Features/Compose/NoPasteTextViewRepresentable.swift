import SwiftUI
import UIKit

struct NoPasteTextViewRepresentable: UIViewRepresentable {
    @Binding var text: String
    var onTextChanged: (String, String) -> Void

    func makeUIView(context: Context) -> NoPasteTextView {
        let textView = NoPasteTextView()
        textView.delegate = context.coordinator
        textView.text = text
        context.coordinator.previousText = text
        return textView
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

