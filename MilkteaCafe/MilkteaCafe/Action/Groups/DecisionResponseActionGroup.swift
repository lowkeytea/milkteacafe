import Foundation
import LowkeyTeaLLM

/// Manages decision-based autonomous responses when the user is idle
/// Uses a multi-stage approach:
/// 1. Analyzes conversation history and context
/// 2. Generates conversation continuation ideas
/// 3. Selects and refines one idea into a natural response
class DecisionResponseActionGroup: ActionGroup {
    // Storage for final results
    private(set) var results: [String: Any] = [:]
    
    // Progress handlers for different action types
    private var progressHandlers: [String: [(String) -> Void]] = [:]
    
    // Reference to view model (weak to avoid cycles)
    private weak var viewModel: ChatViewModel?
    
    // Identifiers for our actions
    enum ActionId {
        static let decision = "decision"
        static let response = "response"
    }
    
    // Response customization options
    struct ResponseOptions {
        // Base probability for decisions
        let initialProbability: Double
        // How much probability increases per check
        let probabilityIncrement: Double
        // Tone options for different idle durations
        let shortIdleTone: String
        let mediumIdleTone: String
        let longIdleTone: String
        
        // Default settings
        static let `default` = ResponseOptions(
            initialProbability: 5.0,
            probabilityIncrement: 5.0,
            shortIdleTone: "casual",
            mediumIdleTone: "friendly",
            longIdleTone: "attention-grabbing"
        )
    }
    
    // Settings for response generation
    private let options: ResponseOptions
    
    // Cached data for context
    private var lastIdleTime: TimeInterval = 0
    private var lastTopics: [String] = []
    
    init(viewModel: ChatViewModel,
         initialProbability: Double = 5.0,
         probabilityIncrement: Double = 5.0,
         startProbability: Double? = nil,
         options: ResponseOptions? = nil) {
        // Store the view model
        self.viewModel = viewModel
        // Use provided options or defaults
        self.options = options ?? .default
    }
    
    // MARK: - ActionGroup conformance
    func subscribeToProgress(for actionId: String, handler: @escaping (String) -> Void) {
        if progressHandlers[actionId] == nil {
            progressHandlers[actionId] = []
        }
        progressHandlers[actionId]?.append(handler)
    }
    
    private func notifyProgress(actionId: String, token: String) {
        progressHandlers[actionId]?.forEach { $0(token) }
    }
    
    func execute(with initialMessage: LlamaMessage) async {

        // Begin the decision process - now always runs since probability is managed externally
        await runDecisionAction(initialMessage: initialMessage)
    }
    
    // MARK: - Decision Action
    private func runDecisionAction(initialMessage: LlamaMessage) async {
        // Get recent messages for context
        let recentMessages = await MainActor.run {
            MessageStore.shared.getRecentMessages(category: .chat, limit: 20)
        }
        
        // Get recent summary messages (most recent first) for broader context
        let summaries = await MainActor.run {
            MessageStore.shared.getRecentMessages(category: .summary, limit: 100)
        }
        
        // Take every 5th summary and ensure latest is included for broad context
        let filtered = summaries.enumerated().compactMap { idx, msg in idx % 5 == 0 ? msg : nil }
        var picks = filtered
        if let latest = summaries.first,
           !picks.contains(where: { $0.id == latest.id }) {
            picks.insert(latest, at: 0)
        }
        
        // Build history text for summaries
        let historyText = picks.map { $0.content }.joined(separator: "\n")
        
        // Determine conversation tone based on idle time
        let conversationTone: String
        let urgencyLevel: String
        
        // Use the idle time from our ChatViewModel if available, otherwise fall back to message timestamps
        let timeSinceLast: TimeInterval
        if lastIdleTime > 0 {
            // Use the already stored idle time from ChatViewModel
            timeSinceLast = lastIdleTime
        } else if let latest = recentMessages.first(where: { $0.role == .user }) {
            // Fall back: calculate from last user message timestamp
            timeSinceLast = Date().timeIntervalSince(latest.timestamp)
        } else {
            timeSinceLast = 0
        }
        
        // Set tone based on idle time brackets
        if timeSinceLast < 30 { // Less than 30 seconds
            conversationTone = options.shortIdleTone
            urgencyLevel = "low"
        } else if timeSinceLast < 120 { // 30 seconds to 2 minutes
            conversationTone = options.mediumIdleTone
            urgencyLevel = "medium"
        } else { // More than 2 minutes
            conversationTone = options.longIdleTone
            urgencyLevel = "high"
        }
        
        // Extract recent topics from conversation
        let recentTopicsText: String
        if !recentMessages.isEmpty {
            // Build recent direct conversation context (last 3-5 exchanges)
            let recentExchanges = recentMessages.prefix(min(10, recentMessages.count))
                .map { "\($0.role == .user ? "User" : "Assistant"): \($0.content)" }
                .joined(separator: "\n")
            recentTopicsText = "\nRecent Conversation:\n\(recentExchanges)"
        } else {
            recentTopicsText = ""
        }
        
        let decisionPrompt: String
        if (MessageStore.shared.getRecentMessages(category: .chat).isEmpty)  {
            // First-time greeting
            decisionPrompt = "This is the first time you are speaking with the user. Greet the user in a friendly way, as someone would to a stranger for the first time. Use a casual, welcoming tone."
        } else {
            // Decision prompt with enhanced context awareness
            decisionPrompt = """
You are generating ideas for continuing a conversation where the user has been idle for \(Int(timeSinceLast)) seconds. 

ANALYSIS TASK:
Analyze the conversation history and generate 5 potential ways to continue the conversation. These should be natural, contextual, and feel like a genuine human follow-up rather than a robotic prompt.

CONTEXT:
- Urgency level: \(urgencyLevel) (user has been idle for \(Int(timeSinceLast)) seconds)
- Tone to use: \(conversationTone)
\(recentTopicsText)

GUIDELINES:
1. For short idle times (less than 30 seconds), focus on direct follow-ups to the recent conversation topics
2. For medium idle times (30 seconds to 2 minutes), try both topic follow-ups and gentle new directions
3. For long idle times (more than 2 minutes), use attention-grabbing approaches and consider mentioning the time gap

Create a numbered list (1-5) of potential conversation continuations that:
- Continue naturally from the conversation context
- Are varied in approach (questions, statements, observations, etc.)
- Feel authentic rather than formulaic
- Match the specified tone and urgency level

Broader context from conversation history summaries for reference:
\(historyText)
"""
        }
        
        let decisionAction = AnyAction(
            systemPrompt: "",
            messages: [],
            message: LlamaMessage(role: .user, content: decisionPrompt),
            clearKVCache: true,
            modelType: .thinking,
            tokenFilter: FullResponseFilter(),
            progressHandler: { [weak self] token in
                self?.notifyProgress(actionId: ActionId.decision, token: token)
            },
            runCode: { response in (false, response) },
            postAction: { [weak self] result in
                guard let self = self else { return }
                let ideas = (result as? String) ?? ""
                self.results[ActionId.decision] = ideas
                // Chain into response
                Task {
                    await self.runResponseAction(timeSinceLast: timeSinceLast)
                }
            }
        )
        await ActionRunner.shared.run(decisionAction)
    }
    
    // MARK: - Response Action
    private func runResponseAction(timeSinceLast: TimeInterval) async {
        guard let viewModel = viewModel else { return }
        let ideas = self.results[ActionId.decision] as? String ?? ""
        
        // Determine conversation attributes based on idle time
        let urgencyText: String
        let lengthGuidance: String
        
        if timeSinceLast < 30 {
            urgencyText = "The user is briefly pausing. Keep your response natural and casual."
            lengthGuidance = "Keep your response brief (1-2 sentences) and conversational."
        } else if timeSinceLast < 120 {
            urgencyText = "The user has been quiet for about \(Int(timeSinceLast)) seconds. They might be thinking or slightly distracted."
            lengthGuidance = "Your response should be friendly and engaging (1-3 sentences)."
        } else if timeSinceLast < 300 { // 5 minutes
            urgencyText = "The user has been inactive for \(Int(timeSinceLast)) seconds (about \(Int(timeSinceLast/60)) minutes). They might be busy or have stepped away."
            lengthGuidance = "Your response should be attention-grabbing but not too long (2-3 sentences)."
        } else {
            urgencyText = "The user has been inactive for a while (\(Int(timeSinceLast/60)) minutes). They might have forgotten about the conversation."
            lengthGuidance = "Your response should be friendly, attention-grabbing, and potentially reference the time gap if appropriate."
        }
        
        let responsePrompt: String
        if (MessageStore.shared.getRecentMessages(category: .chat).isEmpty) {
            responsePrompt = "This is the first time you are speaking with the user. Greet the user in a friendly way, as someone would to a stranger for the first time."
        } else {
            responsePrompt = """
# CONVERSATION CONTINUATION TASK

\(urgencyText)

## Ideas Generated During Analysis
Below are ideas for continuing the conversation:

\(ideas)

## Instructions
1. Select ONE idea that feels most natural for the current conversation state
2. Craft a response based on that idea that feels authentic and spontaneous
3. \(lengthGuidance)
4. Make your response feel like a natural part of an ongoing conversation
5. Do not mention or acknowledge that you're selecting from options
6. Do not use phrases like "I noticed you haven't responded" or explicitly reference the user's inactivity

## Important
The user will not see these instructions or the idea list. They will only see your final response, so make it sound natural.
"""
        }

        let responseAction = await AnyAction(
            systemPrompt: viewModel.chatSystemPrompt,
            messages: [],
            message: LlamaMessage(role: .user, content: responsePrompt),
            clearKVCache: false,
            modelType: .chat,
            tokenFilter: determineOptimalTokenFilter(),
            progressHandler: { [weak self] token in
                self?.notifyProgress(actionId: ActionId.response, token: token)
            },
            runCode: { response in (false, response) },
            postAction: { result in
                let reply = (result as? String) ?? ""
                self.results[ActionId.response] = reply
                
                // Create a more natural system message that doesn't mention idle time specifically
                let systemNote = timeSinceLast > 120 ? 
                    "The conversation continued after a brief pause." : 
                    "The conversation continued naturally."
                
                let assistantMsg = Message(role: .assistant, category: .chat, content: reply)
                let userMsg = Message(role: .user, category: .chat, content: systemNote)
                
                // Store in message history
                MessageStore.shared.addMessage(userMsg)
                MessageStore.shared.addMessage(assistantMsg)
                
                // Update UI
                Task { @MainActor in
                    viewModel.viewableMessages.append(ViewableMessage(from: userMsg))
                    viewModel.viewableMessages.append(ViewableMessage(from: assistantMsg))
                }
            }
        )
        await ActionRunner.shared.run(responseAction)
    }
    
    /// Determines the optimal token filter based on idle time and TTS setting
    @MainActor private func determineOptimalTokenFilter() -> TokenFilter {
        // If TTS is disabled, use passthrough for fastest display
        if viewModel?.ttsEnabled == true {
            return SentenceFilter()
        }
        
        return PassThroughFilter()
    }
}
