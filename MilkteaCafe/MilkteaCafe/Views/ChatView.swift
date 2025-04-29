import SwiftUI
import MilkteaLlamaKokoro

@MainActor
struct ChatView: View {
    @ObservedObject var viewModel = ChatViewModel()

    // State controlling stop button rotation
    @State private var isRotating = false

    var body: some View {
        VStack {
            // Toggle for automatic TTS playback
            HStack {
                Toggle(isOn: $viewModel.ttsEnabled) {
                    Label("Auto TTS", systemImage: viewModel.ttsEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                }
                .toggleStyle(SwitchToggleStyle(tint: .blue))
                Spacer()
            }
            .padding(.horizontal)
            
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(viewModel.viewableMessages) { msg in
                            HStack {
                                if msg.role == .assistant {
                                    Text(msg.content)
                                        .padding()
                                        .background(Color.gray.opacity(0.2))
                                        .cornerRadius(8)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                } else {
                                    Text(msg.content)
                                        .padding()
                                        .background(Color.blue)
                                        .cornerRadius(8)
                                        .foregroundColor(.white)
                                        .frame(maxWidth: .infinity, alignment: .trailing)
                                }
                            }
                            .id(msg.id)
                        }
                    }
                    .padding()
                }
                .onChange(of: viewModel.viewableMessages.count) { _ in
                    if let last = viewModel.viewableMessages.last {
                        withAnimation {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }

            Divider()

            // We move the input bar below into safeAreaInset to stay above the keyboard and its accessory
        }
        // Floating input bar above keyboard
        .safeAreaInset(edge: .bottom) {
            HStack(alignment: .center) {
                TextField("Enter message...", text: $viewModel.inputText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .frame(minHeight: 30)
                    .onSubmit {
                        Task {
                            if viewModel.isGenerating || viewModel.isPlaying || KokoroEngine.sharedInstance.playbackState == .playing {
                                await viewModel.cancelGeneration()
                            } else {
                                await viewModel.send()
                            }
                        }
                    }
                    .submitLabel(.send)

                if viewModel.isGenerating || viewModel.isPlaying {
                    Button(action: { Task { await viewModel.cancelGeneration() } }) {
                        Image(systemName: "stop.fill")
                            .rotationEffect(.degrees(isRotating ? 360 : 0))
                            .animation(isRotating ? Animation.linear(duration: 1).repeatForever(autoreverses: false) : .default, value: isRotating)
                    }
                    .onAppear { isRotating = true }
                    .onDisappear { isRotating = false }
                } else {
                    Button(action: { Task { await viewModel.send() } }) {
                        Image(systemName: "paperplane.fill")
                    }
                    .disabled(viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding()
            .background(Color(UIColor.secondarySystemBackground))
        }
        // navigationTitle removed to be handled by container view
    }
}

struct ChatView_Previews: PreviewProvider {
    static var previews: some View {
        ChatView()
    }
} 
