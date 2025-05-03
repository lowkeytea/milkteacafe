import SwiftUI

struct ChatContainerView: View {
    @ObservedObject var viewModel: ChatViewModel

    var body: some View {
        ChatView(viewModel: viewModel)
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