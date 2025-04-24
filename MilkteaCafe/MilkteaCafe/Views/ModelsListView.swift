import SwiftUI

struct ModelsListView: View {
    @StateObject private var manager = ModelManager.shared

    var body: some View {
        NavigationView {
            List {
                ForEach(manager.modelInfos) { info in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(info.descriptor.displayName)
                                .font(.headline)
                            if manager.selectedModelId == info.id {
                                Image(systemName: "checkmark")
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            manager.selectedModelId = info.id
                        }
                        HStack {
                            Text(ByteCountFormatter.string(
                                fromByteCount: info.descriptor.defaultDownloadSize,
                                countStyle: .file
                            ))
                            Spacer().frame(width: 16)
                            Text(info.descriptor.memoryRequirement)
                        }
                        .font(.subheadline)
                        HStack {
                            // Download state
                            switch info.downloadState {
                            case .notDownloaded:
                                Button("Download") {
                                    manager.download(info.descriptor)
                                }
                            case .downloading:
                                ProgressView()
                            case .downloaded:
                                Text("Downloaded")
                            case .error(let err):
                                Text("Error: \(err)")
                                    .foregroundColor(.red)
                            }
                            Spacer()
                            // Load state
                            switch info.loadState {
                            case .unloaded:
                                EmptyView()
                            case .loading:
                                ProgressView()
                            case .loaded:
                                Text("Loaded")
                                    .foregroundColor(.green)
                            case .error(let err):
                                Text("Load Error: \(err)")
                                    .foregroundColor(.red)
                            }
                        }
                        .buttonStyle(BorderlessButtonStyle())
                        HStack(spacing: 16) {
                            if info.downloadState == .downloaded {
                                Button("Delete") {
                                    manager.delete(info.descriptor)
                                }
                            }
                            if info.downloadState == .downloaded {
                                if info.loadState == .loaded {
                                    Button("Unload") {
                                        manager.unload(info.descriptor)
                                    }
                                } else {
                                    Button("Load") {
                                        manager.load(info.descriptor)
                                        manager.selectedModelId = info.id
                                    }
                                }
                            }
                        }
                        .buttonStyle(BorderlessButtonStyle())
                    }
                    .padding(.vertical, 8)
                }
            }
            .navigationTitle("Models")
        }
    }
}

struct ModelsListView_Previews: PreviewProvider {
    static var previews: some View {
        ModelsListView()
    }
} 