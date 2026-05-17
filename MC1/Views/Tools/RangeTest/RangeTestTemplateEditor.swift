import Foundation
import SwiftUI
import UIKit

// MARK: - Editor handle

/// Bridges SwiftUI pill buttons to UITextView cursor-position insertion.
final class TemplateEditorHandle {
    var insertAction: ((String) -> Void)?

    func insert(_ token: String) {
        insertAction?(token)
    }
}

// MARK: - UITextView wrapper with inline token highlighting

struct HighlightingTokenTextEditor: UIViewRepresentable {
    @Binding var text: String
    @Binding var editorHeight: CGFloat
    let handle: TemplateEditorHandle

    private static let knownTokens = Set(RangeTestBeacon.availableTemplateTokens)
    private static let tokenRegex = try? NSRegularExpression(pattern: #"<[a-zA-Z]+>"#)

    func makeCoordinator() -> Coordinator { Coordinator(text: $text, editorHeight: $editorHeight) }

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.delegate = context.coordinator
        tv.font = UIFont.monospacedSystemFont(ofSize: 15, weight: .regular)
        tv.backgroundColor = .clear
        tv.autocorrectionType = .no
        tv.autocapitalizationType = .none
        tv.isScrollEnabled = false
        tv.returnKeyType = .done
        tv.enablesReturnKeyAutomatically = false
        tv.contentInset = .zero
        tv.textContainerInset = UIEdgeInsets(top: 8, left: 4, bottom: 8, right: 4)
        tv.textContainer.lineFragmentPadding = 0
        tv.textContainer.lineBreakMode = .byWordWrapping
        tv.textContainer.widthTracksTextView = true
        // Allow horizontal shrinking so SwiftUI can constrain the width
        tv.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return tv
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.text != text {
            let sel = uiView.selectedRange
            Self.applyHighlighting(to: uiView, text: text)
            let len = (text as NSString).length
            uiView.selectedRange = NSRange(location: min(sel.location, len), length: 0)
        }

        // Recalculate height whenever the view updates
        DispatchQueue.main.async {
            Self.updateHeight(uiView, binding: $editorHeight)
        }

        handle.insertAction = { [weak uiView] token in
            guard let tv = uiView else { return }
            let range = tv.selectedRange
            let newText = (tv.text as NSString).replacingCharacters(in: range, with: token)
            let newCursor = range.location + (token as NSString).length
            Self.applyHighlighting(to: tv, text: newText)
            tv.selectedRange = NSRange(location: newCursor, length: 0)
            context.coordinator.text = newText
            DispatchQueue.main.async {
                Self.updateHeight(tv, binding: $editorHeight)
            }
        }
    }

    static func updateHeight(_ textView: UITextView, binding: Binding<CGFloat>) {
        let fitted = textView.sizeThatFits(
            CGSize(width: textView.bounds.width, height: .greatestFiniteMagnitude)
        ).height
        let clamped = max(90, fitted)
        if abs(binding.wrappedValue - clamped) > 1 {
            binding.wrappedValue = clamped
        }
    }

    static func applyHighlighting(to textView: UITextView, text: String) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedSystemFont(ofSize: 15, weight: .regular),
            .foregroundColor: UIColor.label
        ]
        let attributed = NSMutableAttributedString(string: text, attributes: attrs)

        if let regex = tokenRegex {
            let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
            for match in regex.matches(in: text, options: [], range: nsRange) {
                let token = (text as NSString).substring(with: match.range)
                let color: UIColor = knownTokens.contains(token)
                    ? (UIColor(named: "AccentColor") ?? .systemBlue)
                    : .systemRed
                attributed.addAttribute(.foregroundColor, value: color, range: match.range)
            }
        }

        textView.attributedText = attributed
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        @Binding var text: String
        @Binding var editorHeight: CGFloat

        init(text: Binding<String>, editorHeight: Binding<CGFloat>) {
            _text = text
            _editorHeight = editorHeight
        }

        func textViewDidChange(_ textView: UITextView) {
            let newText = textView.text ?? ""
            text = newText
            let sel = textView.selectedRange
            HighlightingTokenTextEditor.applyHighlighting(to: textView, text: newText)
            textView.selectedRange = sel
            HighlightingTokenTextEditor.updateHeight(textView, binding: $editorHeight)
        }

        func textView(
            _ textView: UITextView,
            shouldChangeTextIn range: NSRange,
            replacementText replacement: String
        ) -> Bool {
            if replacement == "\n" {
                textView.resignFirstResponder()
                return false
            }
            return true
        }
    }
}

// MARK: - Template Editor

struct RangeTestTemplateEditor: View {
    @Binding var template: String
    @State private var handle = TemplateEditorHandle()
    @State private var editorHeight: CGFloat = 90

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(.quaternary, lineWidth: 1)

                HighlightingTokenTextEditor(text: $template, editorHeight: $editorHeight, handle: handle)
            }
            .frame(minHeight: editorHeight)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(RangeTestBeacon.availableTemplateTokens, id: \.self) { token in
                        Button(token) {
                            handle.insert(token)
                        }
                        .buttonStyle(.bordered)
                        .font(.system(.caption, design: .monospaced))
                    }
                }
            }
        }
    }
}
