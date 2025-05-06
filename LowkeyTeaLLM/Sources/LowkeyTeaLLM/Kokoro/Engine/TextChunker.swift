import Foundation

/// Intelligently breaks text into smaller, natural segments suitable for TTS processing.
public struct TextChunker {
    // Minimum desired characters per chunk.
    public let minChunkLength: Int
    // Maximum allowed characters per chunk.
    public let maxChunkLength: Int
    private let logger: KokoroLogger

    // Natural and secondary break characters
    private static let naturalBreaks: Set<Character> = [".", "!", "?", ";"]
    private static let secondaryBreaks: Set<Character> = [",", ":", "-", ")", "]", "}", "\"", "'", "\n"]
    private static let whitespace: Set<Character> = [" ", "\t", "\n", "\r"]
    private static let specialSequences: [String] = ["...","—", "–"]
    
    // Pre‑compiled regular expressions reused across chunking and cleaning.
    private static let ellipsisCollapseRegex = try! NSRegularExpression(pattern: "(?<!\\.)\\.\\.(?!\\.)")
    private static let periodsCollapseRegex  = try! NSRegularExpression(pattern: "\\.+")
    private static let urlRegex              = try! NSRegularExpression(pattern: "https?://[^\\s]+", options: .caseInsensitive)
    private static let whitespaceRegex       = try! NSRegularExpression(pattern: "\\s+", options: [])
    private static let acronymPatterns: [(regex: NSRegularExpression, replacement: String)] = {
        let acronyms = ["US", "UN", "EU", "UK", "UAE", "NASA", "FBI", "CIA"]
        return acronyms.map { code in
            let pattern = "\\b\(code)\\b"
            let dotted  = code.map(String.init).joined(separator: ".") + "."
            return (try! NSRegularExpression(pattern: pattern, options: .caseInsensitive), dotted)
        }
    }()
    
    private static let apostropheVariants: Set<Character> = ["\u{2018}", "\u{2019}", "\u{02BC}", "\u{FF07}", "`", "\u{00B4}", "\u{2032}", "\u{2035}"]
    private let symbolReplacements: [String: String] = [
        "...": ". ", "-": " ", "–": " ", "—": " ", "―": " ", "*": " ", "#": " ", "•": " ", "·": " ",
        "/": " ", "\\": " ", "\"": " ", "“": "\"", "”": "\"", "„": "\"", "‟": "\"", "(": " ", ")": " ",
        "[": " ", "]": " ", "{": " ", "}": " ", "’": "'", "‘": "'", "ʼ": "'", "‛": "'", "′": "'",
        "‹": "'", "›": "'", "″": "\"", "‶": "\"", "…": ", ", " ": " ", "\u{202F}": " ", "\u{200B}": " ",
        "&": " and ", "©": "", "®": "", "™": "", "m1lkt3a": "Milk tea",
    ]
    
    /// Creates a TextChunker with constraints and an optional logger.
    public init(minChunkLength: Int = 50, maxChunkLength: Int = 250, logger: KokoroLogger = KokoroLogger.create(for: TextChunker.self)) {
        self.minChunkLength = minChunkLength
        self.maxChunkLength = maxChunkLength
        self.logger = logger
    }

    /// Splits the input text into chunks respecting min/max length and natural break points.
    public func chunk(_ text: String) -> [String] {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }
        var result: [String] = []
        let chars = Array(text)
        let length = chars.count
        var startIndex = 0
        var chunkIndex = 0
        let maxIncreaseFactor = 2.0
        let increasePerChunk = 0.25

        while startIndex < length {
            let factor = 1 + min(Double(chunkIndex) * increasePerChunk, maxIncreaseFactor - 1)
            let dynamicMin = Int(Double(minChunkLength) * factor)
            let end = findChunkEnd(chars,
                                   startIndex: startIndex,
                                   dynamicMinLen: dynamicMin)

            // Extract and clean the chunk substring
            var chunkText = String(chars[startIndex..<end]).trimmingCharacters(in: .whitespacesAndNewlines)

            // Add a period if the chunk ends with an alphabetical character
            if let lastChar = chunkText.last, lastChar.isLetter {
                chunkText.append(".")
            }

            if !chunkText.isEmpty {
                // Collapse repeated periods
                let nsRange = NSRange(chunkText.startIndex..<chunkText.endIndex, in: chunkText)
                chunkText = TextChunker.ellipsisCollapseRegex.stringByReplacingMatches(in: chunkText,
                                                                                       options: [],
                                                                                       range: nsRange,
                                                                                       withTemplate: ".")
                chunkText = TextChunker.periodsCollapseRegex.stringByReplacingMatches(in: chunkText,
                                                                                      options: [],
                                                                                      range: nsRange,
                                                                                      withTemplate: ".")
                chunkText = cleanTextForTTS(chunkText)
                chunkText = normalizeApostrophe(chunkText)
                
                let isLast = end >= length
                // Check if this is a short final chunk that needs merging
                if isLast && chunkText.count < minChunkLength && !result.isEmpty {
                    #if DEBUG
                    logger.d("Merging short final chunk: '\(chunkText)' with previous chunk")
                    #endif
                    var merged = result.removeLast()
                    // Add a space between chunks if needed
                    if !merged.hasSuffix(" ") && !chunkText.hasPrefix(" ") {
                        merged += " "
                    }
                    merged += chunkText
                    let cleanedMerged = merged.trimmingCharacters(in: .whitespacesAndNewlines)
                    
                    // Log the merged chunk so we can see it in the logs
                    let preview = String(cleanedMerged.prefix(30))
                    let suffix = cleanedMerged.count > 30 ? "..." : ""
                    #if DEBUG
                    logger.d("Created merged chunk: '\(preview)\(suffix)'")
                    #endif
                    result.append(cleanedMerged)
                } else {
                    let preview = String(chunkText.prefix(30))
                    let suffix = chunkText.count > 30 ? "..." : ""
                    #if DEBUG
                    logger.d("Created chunk: '\(preview)\(suffix)'")
                    #endif
                    result.append(chunkText)
                }
            }

            startIndex = end
            chunkIndex += 1
        }
        
        // Log the total number of chunks for debugging
        #if DEBUG
        logger.d("Generated \(result.count) chunks")
        #endif
        // Extra check: make sure we don't have empty chunks
        result = result.filter { !$0.isEmpty }
        
        return result
    }

    // MARK: - Helpers

    // cleanTextForTTS remains unchanged
    func cleanTextForTTS(_ text: String) -> String {
        var cleaned = TextChunker.urlRegex.stringByReplacingMatches(in: text,
                                                                    options: [],
                                                                    range: NSRange(text.startIndex..<text.endIndex, in: text),
                                                                    withTemplate: " ")

        for (symbol, replacement) in symbolReplacements {
            cleaned = cleaned.replacingOccurrences(of: symbol, with: replacement, options: .caseInsensitive)
        }

        for (regex, dotted) in TextChunker.acronymPatterns {
            cleaned = regex.stringByReplacingMatches(in: cleaned,
                                                     options: [],
                                                     range: NSRange(cleaned.startIndex..<cleaned.endIndex, in: cleaned),
                                                     withTemplate: dotted)
        }

        cleaned = TextChunker.whitespaceRegex.stringByReplacingMatches(in: cleaned,
                                                                       options: [],
                                                                       range: NSRange(cleaned.startIndex..<cleaned.endIndex, in: cleaned),
                                                                       withTemplate: " ")

        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty { cleaned = "." }
        return cleaned
    }
    
    private func findChunkEnd(_ chars: [Character],
                              startIndex: Int,
                              dynamicMinLen: Int) -> Int {
        let textLength = chars.count

        // If remaining text is small relative to desired chunk length, take it all
        let remaining = textLength - startIndex
        let smallThreshold = Int(Double(dynamicMinLen) * 1.5)
        if remaining <= smallThreshold {
            return textLength
        }

        let minEnd = min(startIndex + dynamicMinLen, textLength)
        let maxEnd = min(startIndex + maxChunkLength, textLength)

        // Natural breaks
        var i = minEnd
        while i < maxEnd {
            let seqLen = checkForSpecialSequence(chars, position: i)
            if seqLen > 0 {
                i += seqLen
                continue
            }
            let ch = chars[i]
            if TextChunker.naturalBreaks.contains(ch) {
                return findPositionAfterTrailingWhitespace(chars, startPos: i + 1, maxPos: maxEnd)
            }
            i += 1
        }

        // Secondary breaks
        i = minEnd
        while i < maxEnd {
            let seqLen = checkForSpecialSequence(chars, position: i)
            if seqLen > 0 {
                i += seqLen
                continue
            }
            let ch = chars[i]
            if TextChunker.secondaryBreaks.contains(ch) {
                return findPositionAfterTrailingWhitespace(chars, startPos: i + 1, maxPos: maxEnd)
            }
            i += 1
        }

        // Whitespace fallback
        if maxEnd > minEnd {
            for j in (minEnd..<maxEnd).reversed() {
                if TextChunker.whitespace.contains(chars[j]) {
                    return j + 1
                }
            }
        }

        // Fallback to maxEnd if no break found
        return maxEnd
    }

    private func findPositionAfterTrailingWhitespace(_ chars: [Character], startPos: Int, maxPos: Int) -> Int {
        var pos = startPos
        while pos < maxPos && TextChunker.whitespace.contains(chars[pos]) {
            pos += 1
        }
        return pos
    }

    private func checkForSpecialSequence(_ chars: [Character], position: Int) -> Int {
        for seq in TextChunker.specialSequences {
            let seqChars = Array(seq)
            if position + seqChars.count <= chars.count {
                var matched = true
                for k in 0..<seqChars.count {
                    if chars[position + k] != seqChars[k] {
                        matched = false
                        break
                    }
                }
                if matched {
                    return seqChars.count
                }
            }
        }
        return 0
    }

    private func normalizeApostrophe(_ text: String) -> String {
        return String(text.map { ch in
            TextChunker.apostropheVariants.contains(ch) ? "'" : ch
        })
    }
}
