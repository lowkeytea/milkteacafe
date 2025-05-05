import SwiftUI

struct WakeUpView: View {
    @ObservedObject var modelManager = ModelManager.shared
    @State private var showPrompt = false
    @State private var isGlowing = false
    @State private var downloadComplete = false
    @State private var dotCount = 1
    private let gemmaModel = ModelManager.shared.gemmaModel
    private let timer = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()
    private let progressTimer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.95).edgesIgnoringSafeArea(.all)
            
            VStack {
                if !showPrompt && !downloadComplete {
                    // Initial "Wake up!" button
                    Button(action: {
                        showPrompt = true
                    }) {
                        Text("Wake up!")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 15)
                                    .fill(Color.blue)
                                    .shadow(color: isGlowing ? Color.blue.opacity(0.7) : Color.clear, radius: isGlowing ? 15 : 0)
                            )
                    }
                    .padding(.horizontal, 30)
                    .padding(.vertical, 15)
                    .scaleEffect(isGlowing ? 1.05 : 1.0)
                    .animation(.easeInOut(duration: 1.5), value: isGlowing)
                    .onReceive(timer) { _ in
                        isGlowing.toggle()
                    }
                } else if showPrompt && !downloadComplete {
                    if modelManager.isDownloaded(gemmaModel) {
                        // If model is already downloaded, we're just loading it
                        ProgressView()
                            .scaleEffect(1.5)
                            .padding(.bottom, 20)
                        
                        Text("Preparing goodness...")
                            .font(.headline)
                            .foregroundColor(.white)
                            .onAppear {
                                loadModel()
                            }
                    } else {
                        // Download progress from model manager
                        let progress = modelManager.downloadProgress(for: gemmaModel)
                        
                        if progress > 0 {
                            // Download in progress with real progress
                            VStack {
                                Text("Please wait, goodness incoming\(dotsString())")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .padding(.bottom, 30)
                                    .onReceive(progressTimer) { _ in
                                        dotCount = (dotCount % 3) + 1
                                    }
                                
                                // Use the actual progress from ModelManager
                                // Ensure progress is clamped to valid range
                                let clampedProgress = min(max(progress, 0.0), 1.0)
                                
                                ProgressView(value: clampedProgress)
                                    .progressViewStyle(LinearProgressViewStyle(tint: Color.blue))
                                    .frame(width: 250)
                                    .padding(.bottom, 10)
                                
                                // Calculate bytes based on actual progress
                                let downloadedBytes = Int64(clampedProgress * Double(gemmaModel.defaultDownloadSize))
                                Text("\(formatBytes(downloadedBytes)) / \(formatBytes(gemmaModel.defaultDownloadSize))")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                        } else {
                            // Initial download prompt
                            VStack {
                                Text("M1lkt3a requires downloads to function. This is approximately 1.8GB of data.")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 30)
                                    .padding(.bottom, 30)
                                
                                Button(action: {
                                    startDownload()
                                }) {
                                    Text("Ok")
                                        .font(.system(size: 24, weight: .black, design: .rounded))
                                        .foregroundColor(.black)
                                        .padding(.horizontal, 40)
                                        .padding(.vertical, 12)
                                        .background(
                                            ZStack {
                                                RoundedRectangle(cornerRadius: 20)
                                                    .fill(Color.white)
                                                RoundedRectangle(cornerRadius: 20)
                                                    .stroke(Color.blue, lineWidth: 3)
                                            }
                                        )
                                        .shadow(color: Color.blue.opacity(0.5), radius: 8)
                                }
                            }
                            .padding(.horizontal, 30)
                        }
                    }
                }
            }
        }
        // Add a listener for download completion
        .onChange(of: modelManager.modelInfos) { _ in
            if modelManager.isDownloaded(gemmaModel) {
                // If download state changed to downloaded, start loading model
                loadModel()
            }
        }
    }
    
    private func dotsString() -> String {
        return String(repeating: ".", count: dotCount)
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
    
    private func startDownload() {
        // Start the actual download using ModelManager
        modelManager.download(gemmaModel)
    }
    
    private func loadModel() {
        Task {
            // Check if file actually exists before loading
            let path = modelManager.localURL(for: gemmaModel).path
            if FileManager.default.fileExists(atPath: path) {
                await modelManager.loadContextAsChat(gemmaModel)
                DispatchQueue.main.async {
                    downloadComplete = true
                }
            } else {
                // If the file doesn't exist but state says it's downloaded,
                // we have a state inconsistency, so start the download again
                if modelManager.isDownloaded(gemmaModel) {
                    LoggerService.shared.warning("Model marked as downloaded but file not found, restarting download")
                    modelManager.download(gemmaModel)
                }
            }
        }
    }
}

struct WakeUpView_Previews: PreviewProvider {
    static var previews: some View {
        WakeUpView()
    }
}