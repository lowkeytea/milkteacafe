import SwiftUI

struct ContentView: View {
    @StateObject private var chatVM = ChatViewModel()
    @ObservedObject private var modelManager = ModelManager.shared
    @State private var showMainApp = false
    
    var body: some View {
        // Check if model is downloaded (not just loaded) to handle cold start properly
        if showMainApp || modelManager.isModelLoaded("google_gemma_3_4b") ||
           modelManager.modelInfos.contains(where: { $0.id == "google_gemma_3_4b" && $0.downloadState == .downloaded }) {
            mainView
        } else {
            WakeUpView()
                .onReceive(modelManager.$modelInfos) { _ in
                    if modelManager.isModelLoaded("google_gemma_3_4b") {
                        withAnimation {
                            showMainApp = true
                        }
                    }
                }
        }
    }
    
    var mainView: some View {
        GeometryReader { geometry in
            let isPhone = geometry.size.width < 600
            
            if isPhone {
                phoneLayout
            } else {
                tabletLayout
            }
        }
    }
    
    var phoneLayout: some View {
        VStack(spacing: 0) {
            // Top tab switcher
            HStack {
                Spacer()
                Button(action: { chatVM.selectedTab = 0 }) {
                    Label("Chat", systemImage: "message")
                        .foregroundColor(chatVM.selectedTab == 0 ? .blue : .gray)
                }
                Spacer()
                Button(action: { chatVM.selectedTab = 1 }) {
                    Label("Settings", systemImage: "gear")
                        .foregroundColor(chatVM.selectedTab == 1 ? .blue : .gray)
                }
                Spacer()
            }
            .padding(.vertical, 10)
            .background(Color(UIColor.secondarySystemBackground))
            
            // Content
            if chatVM.selectedTab == 0 {
                ChatContainerView(viewModel: chatVM)
            } else {
                SettingsView(viewModel: chatVM)
            }
        }
    }
    
    var tabletLayout: some View {
        TabView {
            ChatContainerView(viewModel: chatVM)
                .tabItem {
                    Label("Chat", systemImage: "message")
                }
            SettingsView(viewModel: chatVM)
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
        }
    }
}

#Preview {
    ContentView()
}
