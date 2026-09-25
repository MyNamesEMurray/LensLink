import SwiftUI

extension Text {
    init(markdown: String) {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace)
        self.init((try? AttributedString(markdown: markdown, options: options))
                  ?? AttributedString(markdown))
    }
}
