import Foundation

extension String {
    /// Splits a string into sentences, combining any sentences that are too short (<3 characters)
    /// with the following sentence.
    ///
    /// This helps improve classification by avoiding overly small sentence fragments
    /// that might not have enough context.
    ///
    /// - Returns: An array of sentences
    func splitIntoSentences() -> [String] {
        // Regex matches a position **after** a sentence‑ending punctuation mark
        // (., ?, !) that may be followed by a closing quote/parenthesis/bracket,
        // **and** is immediately followed by either whitespace or end‑of‑string.
        // Using a *fixed‑width* look‑behind avoids the variable‑length `\s+`
        // that caused an “Invalid regular expression” error.
        let pattern = #"(?<=[.!?][\"\'\)\]]?)(?=\s+|$)"#
        
        // Split the string using the regex pattern
        var rawSentences: [String] = []
        do {
            let regex = try NSRegularExpression(pattern: pattern)
            let ranges = regex.matches(
                in: self,
                range: NSRange(self.startIndex..., in: self)
            ).map { $0.range }
            
            var lastEnd = self.startIndex
            for range in ranges {
                if let end = Range(range, in: self)?.upperBound {
                    let sentence = String(self[lastEnd..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !sentence.isEmpty {
                        rawSentences.append(sentence)
                    }
                    lastEnd = end
                }
            }
            
            // Add any remaining text as the last sentence
            let finalPart = String(self[lastEnd...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !finalPart.isEmpty {
                rawSentences.append(finalPart)
            }
        } catch {
            // Fallback to simple approach if regex fails
            LoggerService.shared.warning("Regex for sentence splitting failed: \(error.localizedDescription)")
            return [self]
        }
        
        // If no sentences were found or there's only one sentence, return the original string
        if rawSentences.isEmpty {
            return [self]
        }
        
        // Process sentences to combine any that are too short
        var processedSentences: [String] = []
        var currentSentence = ""
        
        for sentence in rawSentences {
            // If the current accumulated sentence is empty, start with this sentence
            if currentSentence.isEmpty {
                currentSentence = sentence
                continue
            }
            
            // If current sentence is too short, combine it with the next one
            if currentSentence.count < 3 {
                currentSentence += " " + sentence
            } else {
                // Current sentence is long enough, add it to result
                processedSentences.append(currentSentence)
                currentSentence = sentence
            }
        }
        
        // Add the last accumulated sentence if there is one
        if !currentSentence.isEmpty {
            processedSentences.append(currentSentence)
        }
        
        return processedSentences.isEmpty ? [self] : processedSentences
    }
}
