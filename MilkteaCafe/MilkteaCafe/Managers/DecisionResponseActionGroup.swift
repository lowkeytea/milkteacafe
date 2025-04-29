import Foundation

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
    
    // Probability controls
    private var currentProbability: Double
    private let initialProbability: Double
    private let probabilityIncrement: Double
    
    init(viewModel: ChatViewModel,
         initialProbability: Double = 5.0,
         probabilityIncrement: Double = 5.0,
         startProbability: Double? = nil) {
        // Store the view model and probability settings
        self.viewModel = viewModel
        self.initialProbability = initialProbability
        self.probabilityIncrement = probabilityIncrement
        // Seed the current probability: if startProbability is provided, use it, otherwise use the initial base probability
        self.currentProbability = startProbability ?? initialProbability
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
    
    func execute(with initialMessage: Message) async {
        // Roll for chance
        let roll = Double.random(in: 0..<100)
        if roll < currentProbability {
            // Trigger decision
            currentProbability = initialProbability
            await runDecisionAction(initialMessage: initialMessage)
        } else {
            // Increase chance for next roll
            currentProbability = min(currentProbability + probabilityIncrement, 100)
        }
    }
    
    // MARK: - Decision Action
    private func runDecisionAction(initialMessage: Message) async {
        guard let viewModel = viewModel else { return }
        
        // Fetch summary messages (most recent first)
        let summaries = await MainActor.run {
            MessageStore.shared.getRecentMessages(category: .summary, limit: 100)
        }
        // Take every 5th summary and ensure latest is included
        let filtered = summaries.enumerated().compactMap { idx, msg in idx % 5 == 0 ? msg : nil }
        var picks = filtered
        if let latest = summaries.first,
           !picks.contains(where: { $0.id == latest.id }) {
            picks.insert(latest, at: 0)
        }
        // Build history text
        let historyText = picks.map { $0.content }.joined(separator: "\n")
        // Time since last message
        let timeSinceLast: TimeInterval
        if let latest = summaries.first {
            timeSinceLast = Date().timeIntervalSince(latest.timestamp)
        } else {
            timeSinceLast = 0
        }
        let decisionPrompt: String
        if summaries.isEmpty {
            decisionPrompt = "This is the first time you are speaking with the user.  Greet the user in a friendly way, as someone would to a stranger for the first time."
        } else {
            // Decision prompt
            decisionPrompt = """
Consider the history thus far. Come up with 5 potential statements that you would like to make in line with what the user or assistant has expressed interest in.  List them in a numbered order. These potential ideas can be questions, statements, or even a familiar action the user may be interested in.  Lastly, consider the amount of time the user has not prompted you, which is \(Int(timeSinceLast)) seconds. Make sure the decision list you come up with is designed to pull the user back in.  You can have options such as 'Hey you, are you ignoring me?' to ideas that relate to the topics the user has spoken about. Make sure it is conversational, and attention grabbing. You can and should mention how much time has gone by, if it's been a long time.

History Summaries:
\(historyText)
"""
        }
        
        let decisionAction = await AnyAction(
            systemPrompt: viewModel.chatSystemPrompt,
            messages: [],
            message: Message(role: .user, content: decisionPrompt),
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
        let responsePrompt: String
        if (timeSinceLast == 0) {
            responsePrompt = "This is the first time you are speaking with the user.  Greet the user in a friendly way, as someone would to a stranger for the first time."
        } else {
            responsePrompt = """
    The user has not responded to you in \(Int(timeSinceLast)) seconds. The following are a list of ideas you have on continuing the conversation.  Pick only one of the ideas and prompt the user with it, getting their attention.  Keep your prompt short, since this is you reaching out to the user.  The ideas to use are:
    
    \(ideas)
    
    The user does not see these ideas. Don't give them a clue that there are options to pick from, just run with the option you pick.
    """
        }
        
        let responseAction = await AnyAction(
            systemPrompt: viewModel.chatSystemPrompt,
            messages: [],
            message: Message(role: .user, content: responsePrompt),
            clearKVCache: false,
            modelType: .chat,
            tokenFilter: viewModel.ttsEnabled ? SentenceFilter() : PassThroughFilter(),
            progressHandler: { [weak self] token in
                self?.notifyProgress(actionId: ActionId.response, token: token)
            },
            runCode: { response in (false, response) },
            postAction: { result in
                let reply = (result as? String) ?? ""
                self.results[ActionId.response] = reply
                let assistantMsg = Message(role: .assistant, category: .chat, content: reply)
                let userMsg = Message(role: .user, category: .chat, content: "The user has not responded in \(Int(timeSinceLast)) seconds.")
                MessageStore.shared.addMessage(userMsg)
                MessageStore.shared.addMessage(assistantMsg)
                Task { @MainActor in
                    viewModel.viewableMessages.append(ViewableMessage(from: userMsg))
                    viewModel.viewableMessages.append(ViewableMessage(from: assistantMsg))
                }
            }
        )
        await ActionRunner.shared.run(responseAction)
    }
}
