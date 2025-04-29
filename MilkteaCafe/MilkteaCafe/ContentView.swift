import SwiftUI

struct ContentView: View {
    @StateObject private var chatVM = ChatViewModel()

    var body: some View {
        TabView {
            ModelsListView()
                .tabItem {
                    Label("Models", systemImage: "square.stack")
                }
            SettingsView(viewModel: chatVM)
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
            ChatContainerView(viewModel: chatVM)
                .tabItem {
                    Label("Chat", systemImage: "message")
                }
        }
    }
}

#Preview {
    ContentView()
}
