import SwiftUI

struct ThinkingView: View {
    @ObservedObject var viewModel: ChatViewModel

    var body: some View {
        VStack(alignment: .leading) {
            Text("Thinking")
                .font(.headline)
                .padding(.horizontal)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    // Tone Analysis
                    if !viewModel.thinkingTone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Pre-Message Intent:")
                                .font(.subheadline).bold()
                            Text(viewModel.thinkingTone)
                        }
                    }
                    // Assistant Summary
                    if !viewModel.thinkingOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Summary:")
                                .font(.subheadline).bold()
                            Text(viewModel.thinkingOutput)
                        }
                    }
                    // Placeholder when nothing to show
                    if viewModel.thinkingTone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                       viewModel.thinkingOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("No analysis available.")
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(UIColor.secondarySystemBackground))
        }
    }
}

struct ThinkingView_Previews: PreviewProvider {
    static var previews: some View {
        ThinkingView(viewModel: ChatViewModel())
            .previewDisplayName("ThinkingView")
    }
} 
