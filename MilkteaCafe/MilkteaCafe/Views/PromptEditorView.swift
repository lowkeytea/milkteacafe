import SwiftUI

/// A view for editing large prompt strings with cancel/save functionality
struct PromptEditorView: View {
    let title: String
    @Binding var text: String

    @Environment(\.dismiss) private var dismiss
    @State private var draftText: String = ""

    var body: some View {
        VStack {
            TextEditor(text: $draftText)
                .padding()
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            dismiss()
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            text = draftText
                            SystemPromptManager.shared.updateSystemPrompt(text)
                            dismiss()
                        }
                    }
                }
        }
        .onAppear {
            draftText = text
        }
    }
}

struct PromptEditorView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            PromptEditorView(title: "Edit Prompt", text: .constant("Initial prompt body..."))
        }
    }
} 
