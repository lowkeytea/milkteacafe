import Foundation

/// Protocol to filter raw tokens into units (e.g. tokens or sentences)
protocol TokenFilter {
    mutating func process(token: String) -> [String]
    mutating func flush() -> [String]
}

/// A filter that yields each token immediately
struct PassThroughFilter: TokenFilter {
    mutating func process(token: String) -> [String] { [token] }
    mutating func flush() -> [String] { [] }
}

/// A simple sentence filter that yields buffered text when a sentence end is detected
struct SentenceFilter: TokenFilter {
    private var buffer: String = ""
    private let endingChars = CharacterSet(charactersIn: ".!?" )
    private let minLength: Int
    init(minLength: Int = 20) { self.minLength = minLength }
    mutating func process(token: String) -> [String] {
        buffer += token
        // If buffer is long enough and ends with a sentence-ending character
        if buffer.count >= minLength,
           let last = buffer.trimmingCharacters(in: .whitespacesAndNewlines).last,
           endingChars.contains(last.unicodeScalars.first!) {
            let sentence = buffer
            buffer = ""
            return [sentence]
        }
        return []
    }
    mutating func flush() -> [String] {
        guard !buffer.isEmpty else { return [] }
        let leftover = buffer
        buffer = ""
        return [leftover]
    }
}

/// A filter that buffers all tokens and emits the full response only at the end
struct FullResponseFilter: TokenFilter {
    private var buffer: String = ""
    mutating func process(token: String) -> [String] {
        buffer += token
        return []
    }
    mutating func flush() -> [String] {
        defer { buffer = "" }
        return [buffer]
    }
}

/// Actor responsible for formatting prompts and streaming tokens from a LlamaContext
actor ResponseGenerator {
    static let shared = ResponseGenerator()

    /// Generate a filtered async stream of text units from a LlamaContext
    /// - Parameters:
    ///   - context: the LlamaContext instance for text generation
    ///   - history: previous chat messages
    ///   - systemPrompt: the system prompt to use
    ///   - newUserMessage: the new user ChatMessage to append
    ///   - filter: a TokenFilter to control unit emissions
    /// - Returns: an AsyncStream of String units (tokens or sentences)
    func generate(
        llama context: LlamaContext,
        history: [Message],
        systemPrompt: String,
        newUserMessage: Message,
        filter: TokenFilter = PassThroughFilter()
    ) -> AsyncStream<String> {
        let formatter = GemmaPromptFormatter()
        return AsyncStream<String> { continuation in
            // Start generation task
            let task = Task.detached(priority: .userInitiated) {
                // Build formatted prompt messages
                var promptMessages: [Message] = history.map { chat in
                    Message(role: chat.role == .user ? .user : .assistant,
                            content: chat.content)
                }
                let newMsg = Message(role: .user, content: newUserMessage.content)
                promptMessages.append(newMsg)

                // Initialize or append to context
                if await context.n_cur == 0 {
                    // Prepend system instruction for the very first turn
                    
                    promptMessages.insert(
                        Message(role: .system, content: systemPrompt),
                        at: 0
                    )
                    // Format the full prompt for initialization
                    let fullPrompt = formatter.format(
                        messages: promptMessages,
                        systemPrompt: nil
                    )
                    LoggerService.shared.info(
                        "ResponseGenerator for \(context.id) fullPrompt: '\(fullPrompt)' (length \(fullPrompt.count))"
                    )
                    await context.setCancelled(false)
                    let success = await context.completionInit(fullPrompt)
                    guard success else {
                        continuation.finish()
                        return
                    }
                } else {
                    // Format only the new user turn
                    let formattedUser = formatter.format(
                        messages: [newMsg],
                        systemPrompt: nil
                    )
                    LoggerService.shared.info(
                        "ResponseGenerator formattedUserMessage: '\(formattedUser)' (length \(formattedUser.count))"
                    )
                    await context.appendUserMessage(userMessage: formattedUser)
                }

                // Stream tokens through the filter
                var f = filter
                var currentToken = 0
                while !Task.isCancelled,
                      let token = await context.completionLoop(
                        maxTokens: LlamaConfig.shared.maxTokens,
                        currentToken: &currentToken
                    ) {
                    for unit in f.process(token: token) {
                        continuation.yield(unit)
                    }
                }

                // Flush any remaining buffer units
                for unit in f.flush() {
                    #if DEBUG
                    LoggerService.shared.debug("ResponseGenerator flush unit: '\(unit)' (\(unit.count) chars)")
                    #endif
                    continuation.yield(unit)
                }
                await self.postGenerationCleanup(context)
                continuation.finish()
            }
            // Handle cancellation/termination
            continuation.onTermination = { @Sendable _ in
                // Cancel the generation task
                task.cancel()
            }
        }
    }
    
    func postGenerationCleanup(_ model: LlamaContext) async {
        LoggerService.shared.debug("Checking if reset needed...")
        
        do {
            if await (LlamaBridge.shared.checkResetPending()) {
                LoggerService.shared.info("Resetting cache and history")
                await model.clearContext()
            }
        }
    }
}
