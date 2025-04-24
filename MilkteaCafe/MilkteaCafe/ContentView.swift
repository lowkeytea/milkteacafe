import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            ModelsListView()
                .tabItem {
                    Label("Models", systemImage: "square.stack")
                }
            ChatView()
                .tabItem {
                    Label("Chat", systemImage: "message")
                }
        }
    }
}

#Preview {
    ContentView()
}
