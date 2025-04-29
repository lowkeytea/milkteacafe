import SwiftUI
import Combine

/// A toggle style that displays a checkbox for iOS.
struct CheckboxToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            Image(systemName: configuration.isOn ? "checkmark.square" : "square")
                .resizable()
                .frame(width: 20, height: 20)
                .onTapGesture { configuration.isOn.toggle() }
            configuration.label
        }
    }
}

struct ModelsListView: View {
    @StateObject private var manager = ModelManager.shared
    @State private var defaultLoadCancellable: AnyCancellable?
    @State private var loadActionDescriptor: ModelDescriptor?  // Descriptor to load
    @State private var showLoadDialog = false                // Whether the load dialog is visible

    @AppStorage("defaultChatModelId") private var defaultChatModelId: String?
    @AppStorage("defaultThinkingModelId") private var defaultThinkingModelId: String?
    @AppStorage("autoloadDefaultModels") private var autoloadDefaultModels: Bool = false

    @State private var showDefaultWarning = false

    private var defaultSelectionAvailable: Bool {
        guard let chatId = defaultChatModelId,
              let thinkingId = defaultThinkingModelId else { return false }
        return manager.modelInfos.contains { $0.id == chatId && $0.downloadState == .downloaded }
            && manager.modelInfos.contains { $0.id == thinkingId && $0.downloadState == .downloaded }
    }

    private func loadDefaultSelection() {
        guard defaultSelectionAvailable,
              let chatId = defaultChatModelId,
              let thinkingId = defaultThinkingModelId,
              let chatInfo = manager.modelInfos.first(where: { $0.id == chatId }),
              let thinkingInfo = manager.modelInfos.first(where: { $0.id == thinkingId }) else {
            showDefaultWarning = true
            return
        }
        // Load the chat model first
        manager.loadAsChat(chatInfo.descriptor)
        // Once the chat model finishes loading, load the thinking model
        defaultLoadCancellable = manager.$modelInfos
            .receive(on: RunLoop.main)
            .filter { infos in
                infos.contains(where: { $0.id == chatId && $0.loadState == .loaded })
            }
            .sink { _ in
                manager.loadAsThinking(thinkingInfo.descriptor)
                // Cancel the subscription
                self.defaultLoadCancellable?.cancel()
                self.defaultLoadCancellable = nil
            }
    }

    var body: some View {
        NavigationView {
            VStack {
                HStack(spacing: 16) {
                    Button("Save Selection") {
                        defaultChatModelId = manager.selectedModelId
                        defaultThinkingModelId = manager.selectedThinkingModelId
                    }
                    .disabled(manager.selectedModelId == nil || manager.selectedThinkingModelId == nil)

                    Button("Load Default") {
                        loadDefaultSelection()
                    }
                    .disabled(!defaultSelectionAvailable)

                    Toggle("Autoload", isOn: $autoloadDefaultModels)
                        .toggleStyle(CheckboxToggleStyle())
                }
                .padding()

                List {
                    ForEach(manager.modelInfos) { info in
                        ModelRowView(
                            info: info,
                            manager: manager,
                            loadActionDescriptor: $loadActionDescriptor,
                            showLoadDialog: $showLoadDialog
                        )
                    }
                }
                .navigationTitle("Models")
            }
            .alert("Default models unavailable", isPresented: $showDefaultWarning) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("One or both default models are not downloaded.")
            }
            .onAppear {
                if autoloadDefaultModels && defaultSelectionAvailable {
                    loadDefaultSelection()
                } else if autoloadDefaultModels && !defaultSelectionAvailable {
                    autoloadDefaultModels = false
                }
            }
            .onChange(of: defaultSelectionAvailable) { available in
                if !available {
                    autoloadDefaultModels = false
                }
            }
        }
        .confirmationDialog("Load model as", isPresented: $showLoadDialog, presenting: loadActionDescriptor) { descriptor in
            Button("Chat") {
                manager.loadAsChat(descriptor)
            }
            Button("Thinking") {
                manager.loadAsThinking(descriptor)
            }
            Button("Cancel", role: .cancel) { }
        } message: { descriptor in
            Text("Choose how to load ‘\(descriptor.displayName)’")
        }
    }
}

struct ModelsListView_Previews: PreviewProvider {
    static var previews: some View {
        ModelsListView()
    }
}

/// A standalone row view for each model, extracted to simplify the parent List.
struct ModelRowView: View {
    let info: ModelInfo
    @ObservedObject var manager: ModelManager
    @Binding var loadActionDescriptor: ModelDescriptor?
    @Binding var showLoadDialog: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            subtitle
            stateButtons
            actionButtons
        }
        .padding(.vertical, 8)
    }

    private var header: some View {
        HStack {
            Text(info.descriptor.displayName)
                .font(.headline)
            if manager.selectedModelId == info.id {
                Image(systemName: "checkmark")
            }
            if manager.selectedThinkingModelId == info.id {
                Image(systemName: "brain.head.profile")
                    .foregroundColor(.blue)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            manager.selectedModelId = info.id
        }
    }

    private var subtitle: some View {
        HStack {
            Text(ByteCountFormatter.string(
                fromByteCount: info.descriptor.defaultDownloadSize,
                countStyle: .file)
            )
            Spacer().frame(width: 16)
            Text(info.descriptor.memoryRequirement)
        }
        .font(.subheadline)
    }

    private var stateButtons: some View {
        HStack {
            Group {
                switch info.downloadState {
                case .notDownloaded:
                    Button("Download", action: { manager.download(info.descriptor) })
                case .downloading:
                    ProgressView()
                case .downloaded:
                    Text("Downloaded")
                case .error(let err):
                    Text("Error: \(err)")
                        .foregroundColor(.red)
                }
            }
            Spacer()
            Group {
                switch info.loadState {
                case .unloaded:
                    EmptyView()
                case .loading:
                    ProgressView()
                case .loaded:
                    Text("Loaded").foregroundColor(.green)
                case .error(let err):
                    Text("Load Error: \(err)")
                        .foregroundColor(.red)
                }
            }
        }
        .buttonStyle(BorderlessButtonStyle())
    }

    private var actionButtons: some View {
        HStack(spacing: 16) {
            if info.downloadState == .downloaded {
                Button("Delete") {
                    manager.delete(info.descriptor)
                }
                if manager.selectedModelId != info.id {
                    Button("Load Chat") {
                        manager.loadAsChat(info.descriptor)
                    }
                }
                if manager.selectedThinkingModelId != info.id {
                    Button("Load Thinking") {
                        manager.loadAsThinking(info.descriptor)
                    }
                }
                if manager.selectedModelId == info.id || manager.selectedThinkingModelId == info.id {
                    Button("Unload") {
                        manager.unload(info.descriptor)
                    }
                }
            }
        }
        .buttonStyle(BorderlessButtonStyle())
    }
} 
