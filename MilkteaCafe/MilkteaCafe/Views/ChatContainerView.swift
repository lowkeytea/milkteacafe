import SwiftUI

struct ChatContainerView: View {
    @ObservedObject var viewModel: ChatViewModel

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                ThinkingView(viewModel: viewModel)
                    .frame(height: geometry.size.height * 0.33)
                Divider()
                ChatView(viewModel: viewModel)
                    .frame(height: geometry.size.height * 0.67)
            }
        }
        .navigationTitle("Chat")
    }
}

struct ChatContainerView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            ChatContainerView(viewModel: ChatViewModel())
        }
    }
} 