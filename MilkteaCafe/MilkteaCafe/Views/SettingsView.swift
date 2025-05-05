import SwiftUI

#if DEBUG
import Foundation
#endif

struct SettingsView: View {
    @ObservedObject var viewModel: ChatViewModel

    var body: some View {
        NavigationView {
            Form {
                Button(action: {
                    Task {
                        await viewModel.clearMessages()
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "trash.fill")
                            .font(.system(size: 24))
                        
                        Text("Clear History")
                            .font(.title3)
                    }
                }
                Section(header: Text("Chat System Prompt")) {
                    NavigationLink("Edit") {
                        PromptEditorView(
                            title: "Chat System Prompt",
                            text: $viewModel.chatSystemPrompt
                        )
                    }
                }
                Section(header: Text("Voice")) {
                    Picker(selection: $viewModel.selectedVoiceName, label: Text("Voice")) {
                        ForEach(viewModel.availableVoices, id: \String.self) { voice in
                            Text(voice).tag(voice)
                        }
                    }
                }
                
                #if DEBUG
                // Debug tools section - only visible in debug builds
                Section(header: Text("Developer Tools")) {
                    Button(action: {
                        // Run the function classifier tests
                        LoggerService.shared.info("Starting function classifier tests...")
                        FunctionClassifierDebugger.runTests()
                        LoggerService.shared.info("Function classifier tests completed. Check console for results.")
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "wrench.fill")
                                .font(.system(size: 20))
                            
                            Text("Test Function Classifier")
                                .font(.headline)
                        }
                    }
                }
                #endif
            }
            .navigationTitle("Settings")
        }
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView(viewModel: ChatViewModel())
    }
} 
