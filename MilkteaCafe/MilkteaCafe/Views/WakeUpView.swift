import SwiftUI

struct WakeUpView: View {
    @ObservedObject var modelManager = ModelManager.shared
    @State private var showPrompt = false
    @State private var isGlowing = false
    @State private var downloadComplete = false
    @State private var downloadProgress: Double = 0
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
                    } else if downloadProgress > 0 {
                        // Download in progress
                        VStack {
                            Text("Please wait, goodness incoming\(dotsString())")
                                .font(.headline)
                                .foregroundColor(.white)
                                .padding(.bottom, 30)
                                .onReceive(progressTimer) { _ in
                                    dotCount = (dotCount % 3) + 1
                                }
                            
                            ProgressView(value: downloadProgress)
                                .progressViewStyle(LinearProgressViewStyle(tint: Color.blue))
                                .frame(width: 250)
                                .padding(.bottom, 10)
                            
                            Text("\(formatBytes(Int64(downloadProgress * Double(gemmaModel.defaultDownloadSize)))) / \(formatBytes(gemmaModel.defaultDownloadSize))")
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
        // Start a Timer to simulate download progress
        Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { timer in
            // This is a simulation - in reality we would hook this up to the download progress
            if self.downloadProgress < 1.0 {
                // In production, this would be replaced with actual download progress from ModelManager
                self.downloadProgress += 0.02
            } else {
                timer.invalidate()
                DispatchQueue.main.async {
                    self.loadModel()
                }
            }
        }
        
        // Start the actual download
        modelManager.download(gemmaModel)
    }
    
    private func loadModel() {
        Task {
            await modelManager.loadContextAsChat(gemmaModel)
            DispatchQueue.main.async {
                downloadComplete = true
            }
        }
    }
}

struct WakeUpView_Previews: PreviewProvider {
    static var previews: some View {
        WakeUpView()
    }
}
