import Foundation
import Dispatch

/// A generic FIFO job processor using Swift Concurrency (actor) that executes tasks one at a time in order of submission.
public actor FifoJobProcessor<Item: Sendable, Result: Sendable> {
    // MARK: - Types
    private let jobToRun: @Sendable (Item) async throws -> Result
    private let onResult: @Sendable (Item, Result) -> Void
    private let onError: (@Sendable (Item, Error) -> Void)?

    // MARK: - State
    private var queue: [Item] = []
    private var isProcessing: Bool = false
    private var isPaused: Bool = false
    // Task executing the current item, for cancellation support
    private var currentTask: Task<Void, Never>? = nil

    // MARK: - Initialization
    public init(
        jobToRun: @escaping @Sendable (Item) async throws -> Result,
        onResult: @escaping @Sendable (Item, Result) -> Void,
        onError: (@Sendable (Item, Error) -> Void)? = nil
    ) {
        self.jobToRun = jobToRun
        self.onResult = onResult
        self.onError = onError
    }

    // MARK: - Public API
    /// Submits a new item to the processing queue.
    public func submit(_ item: Item) {
        queue.append(item)
        if !isProcessing && !isPaused {
            processNext()
        }
    }

    /// Clears all pending items in the queue. Also cancels the job already in flight.
    public func clearQueue() {
        queue.removeAll()
        currentTask?.cancel()
        currentTask = nil
        isProcessing = false
    }

    /// Returns the current number of pending items waiting to be processed.
    public func getQueueSize() -> Int {
        return queue.count
    }

    /// Pauses processing after the current item completes.
    public func pause() {
        isPaused = true
    }
    
    /// Resumes processing of queued items.
    public func resume() {
        guard isPaused else { return }
        isPaused = false
        if !isProcessing {
            processNext()
        }
    }

    // MARK: - Internal Processing
    /// Triggers processing of the next item in the queue, if any.
    private func processNext() {
        if isPaused {
            isProcessing = false
            return
        }
        guard !queue.isEmpty else {
            isProcessing = false
            return
        }
        isProcessing = true
        let item = queue.removeFirst()

        // Run the job in a tracked Task so it can be cancelled
        currentTask = Task {
            do {
                try Task.checkCancellation()
                let result = try await jobToRun(item)
                await MainActor.run { onResult(item, result) }
            } catch {
                if error is CancellationError {
                    #if DEBUG
                    print("✂️ FifoJobProcessor: job cancelled for item: \(item)")
                    #endif
                } else {
                    #if DEBUG
                    print("⚠️ FifoJobProcessor: job error \(error) for item: \(item)")
                    #endif
                    if let onError = onError {
                        await MainActor.run { onError(item, error) }
                    }
                }
            }
            self.currentTask = nil
            self.processNext()
        }
    }
}
