import Foundation

/// A utility class for debugging and testing the sentence-level function classification
class FunctionClassifierDebugger {
    /// Test the sentence splitting functionality with sample inputs
    static func testSentenceSplitting() {
        // Sample inputs to test
        let samples = [
            "Change the system prompt to be more friendly.",
            "Tell me a joke. Make me laugh. Oh, and turn on your voice.",
            "You. Are. Awesome. I really appreciate your help.",
            "This is just a normal conversation. Nothing special here.",
            "This is a multi-sentence input. Can you please search the web for the weather today? I want to plan my day.",
            "Regular chat message. Remember my name is Coolio."
        ]
        
        // Log each sample and its sentence splitting
        for (index, sample) in samples.enumerated() {
            let sentences = sample.splitIntoSentences()
            
            print("---- Sample \(index + 1) ----")
            print("Original: \"\(sample)\"")
            print("Split into \(sentences.count) sentences:")
            for (i, sentence) in sentences.enumerated() {
                print("  \(i + 1): \"\(sentence)\"")
            }
            print("")
        }
    }
    
    /// Test the function classifier with sentence-level analysis
    static func testFunctionClassifier() throws {
        let classifier = try BaseFunctionClassifier()
        
        // Sample inputs to test
        let samples = [
            "Change the system prompt to be more friendly.",
            "Tell me a joke. Make me laugh.",
            "You. Are. Awesome. I really appreciate your help.",
            "This is just a normal conversation. Nothing special here.",
            "This is a multi-sentence input. Can you please search the web for the weather today? I want to plan my day.",
            "Regular chat message. Remember my name is Coolio, and use it next time."
        ]
        
        // Classify each sample
        for (index, sample) in samples.enumerated() {
            guard let result = classifier.classify(sample) else {
                print("Failed to classify sample \(index + 1)")
                continue
            }
            
            print("---- Sample \(index + 1) ----")
            print("Input: \"\(sample)\"")
            print("Classification: \(result.classification.rawValue)")
            print("Confidence: \(Int(result.confidence * 100))%")
            print("Analysis method: \(result.analyzedBy)")
            
            // If it was analyzed at sentence level, show each sentence
            if result.analyzedBy == .sentenceLevel {
                let sentences = sample.splitIntoSentences()
                print("Sentences analyzed:")
                for (i, sentence) in sentences.enumerated() {
                    if let sentenceResult = classifier.classifyText(sentence) {
                        print("  \(i + 1): \"\(sentence)\" → \(sentenceResult.classification.rawValue) (\(Int(sentenceResult.confidence * 100))%)")
                    } else {
                        print("  \(i + 1): \"\(sentence)\" → Failed to classify")
                    }
                }
            }
            
            print("")
        }
    }
    
    /// Run both test functions
    static func runTests() {
        print("=== Testing Sentence Splitting ===\n")
        testSentenceSplitting()
        
        print("\n=== Testing Function Classification ===\n")
        do {
            try testFunctionClassifier()
        } catch {
            print("Error testing function classifier: \(error)")
        }
    }
}
