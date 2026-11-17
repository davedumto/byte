import Foundation

// Typed commands that move Byte ("go to the plant", "jump"), matched before a question reaches the model
// (decision 2026-11-16, 1A: a fixed list, no model). Foundation only, so it is unit-tested on the Mac.
// Only a whole message matches, so questions like "how do I jump to a git tag?" still go to the brain.

/// Places Byte can walk to (keys of PLACES in byte-world/main.js).
enum Place: String, CaseIterable {
    case desk, beanBag, plant, window, bookshelf, mailbox, rug

    /// How Byte names the place in its reply.
    var spokenName: String {
        switch self {
        case .beanBag: return "bean bag"
        default: return rawValue
        }
    }

    /// Words people use for each place. "bed" is the bean bag: Byte sleeps there.
    static let synonyms: [String: Place] = [
        "desk": .desk, "table": .desk, "computer": .desk, "code desk": .desk, "work desk": .desk,
        "workstation": .desk, "screen": .desk, "monitor": .desk,
        "bean bag": .beanBag, "beanbag": .beanBag, "bag": .beanBag, "bed": .beanBag, "couch": .beanBag, "sofa": .beanBag,
        "plant": .plant, "flower": .plant, "flowers": .plant, "tree": .plant, "pot": .plant,
        "plant pot": .plant, "flower pot": .plant, "pot plant": .plant,
        "window": .window, "moon": .window,
        "bookshelf": .bookshelf, "book shelf": .bookshelf, "bookcase": .bookshelf, "shelf": .bookshelf, "books": .bookshelf,
        "mailbox": .mailbox, "mail box": .mailbox, "mail": .mailbox, "letterbox": .mailbox, "postbox": .mailbox, "post box": .mailbox,
        "rug": .rug, "carpet": .rug, "mat": .rug, "middle": .rug, "center": .rug, "centre": .rug
    ]
}

/// Something Byte does instead of answering.
enum WorldAction: Equatable {
    case goTo(Place)
    case jump
    case celebrate
    case sleep         // mood sleepy: walks to the bean bag and lies down
    case wakeUp        // mood happy
    case mood(Mood)    // "focus mode", "be bored", "night owl mode", "cheer up" (decision 2026-11-17, 1B)
}

enum CommandMatch: Equatable {
    case action(WorldAction)
    case unknownPlace(String)   // "go to the kitchen": answered with the list of places, model not called
}

enum CommandMatcher {
    /// Longest place name treated as a place request ("go to the big red kitchen" is still a place, 4+ words is not).
    static let maxPlaceWords = 3

    static func match(_ text: String) -> CommandMatch? {
        let s = strip(normalize(text))
        guard !s.isEmpty else { return nil }
        if let action = phrases[s] { return .action(action) }
        guard let rest = afterMovementVerb(s) else { return nil }
        if let place = Place.synonyms[rest] { return .action(.goTo(place)) }
        let words = rest.split(separator: " ")
        guard !words.isEmpty, words.count <= maxPlaceWords else { return nil }
        return .unknownPlace(rest)
    }

    static func reply(_ match: CommandMatch) -> String {
        switch match {
        case .action(.goTo(let place)): return "On my way to the \(place.spokenName)!"
        case .action(.jump): return "Boing!"
        case .action(.celebrate): return "Party time!"
        case .action(.sleep): return "Okay, nap time."
        case .action(.wakeUp): return "I'm up, I'm up!"
        case .action(.mood(let mood)): return moodReply(mood)
        case .unknownPlace(let name):
            let list = Place.allCases.map { $0.spokenName }
            return "There's no \(name) in my room. I can go to the " +
                list.dropLast().joined(separator: ", ") + " or " + list.last! + "."
        }
    }

    private static func moodReply(_ mood: Mood) -> String {
        switch mood {
        case .focused: return "Focus mode on."
        case .bored: return "Ugh, so bored."
        case .night: return "Night owl mode!"
        case .happy: return "Yay, happy again!"
        case .sleepy: return "Okay, nap time."
        case .celebrating: return "Party time!"
        }
    }

    // MARK: - Matching details

    /// Whole-message phrases (after `strip`). "go to bed" means sleep; "go to the bed" walks to the bean bag.
    private static let phrases: [String: WorldAction] = {
        var p: [String: WorldAction] = [:]
        for s in ["jump", "jump up", "jump around", "hop", "do a jump", "do a little jump"] { p[s] = .jump }
        for s in ["celebrate", "party", "dance", "do a dance", "do a celebration", "do a little dance",
                  "party time", "celebration time", "lets celebrate", "lets party"] { p[s] = .celebrate }
        for s in ["sleep", "go to sleep", "go to bed", "go sleep", "nap", "take a nap", "have a nap", "go nap",
                  "go take a nap", "go have a nap", "bedtime", "time for bed", "time to sleep"] { p[s] = .sleep }
        for s in ["wake up", "get up", "wake", "rise and shine", "wakey wakey"] { p[s] = .wakeUp }
        for s in ["focus", "be focused", "get focused", "focus mode", "lets focus", "lets get focused", "work mode",
                  "get to work", "lets work", "time to work", "lock in"] { p[s] = .mood(.focused) }
        for s in ["be bored", "look bored", "act bored", "bored mode", "get bored"] { p[s] = .mood(.bored) }
        for s in ["night owl", "night owl mode", "be a night owl", "go night owl", "owl mode", "night mode"] { p[s] = .mood(.night) }
        for s in ["be happy", "cheer up", "smile", "happy mode", "get happy", "be cheerful"] { p[s] = .mood(.happy) }
        return p
    }()

    // No "get" or "come": "get to work" is not a place.
    private static let verbs = ["go", "walk", "run", "move", "head", "hop", "wander", "roll"]
    private static let joiners = ["over to", "back to", "to", "towards", "toward", "over by", "by", "near"]
    private static let articles = ["the ", "your ", "that ", "my "]

    /// "go over to the big plant" -> "big plant"; nil if the message isn't "<verb> <joiner> <place>".
    private static func afterMovementVerb(_ s: String) -> String? {
        for verb in verbs where s.hasPrefix(verb + " ") {
            let afterVerb = String(s.dropFirst(verb.count + 1))
            for joiner in joiners where afterVerb.hasPrefix(joiner + " ") {
                var rest = String(afterVerb.dropFirst(joiner.count + 1))
                for article in articles where rest.hasPrefix(article) { rest = String(rest.dropFirst(article.count)); break }
                let bareArticle = articles.contains(rest + " ")   // "go to the" (unfinished): no place given
                return rest.isEmpty || bareArticle ? nil : rest
            }
        }
        return nil
    }

    /// Lowercase, curly quotes straightened, apostrophes dropped ("let's" -> "lets"), other punctuation to spaces.
    static func normalize(_ text: String) -> String {
        var out = ""
        for ch in text.lowercased() {
            if ch == "'" || ch == "\u{2019}" { continue }
            out.append(ch.isLetter || ch.isNumber ? ch : " ")
        }
        return out.split(separator: " ").joined(separator: " ")
    }

    private static let leading = ["hey", "hi", "ok", "okay", "byte", "please", "can you", "could you", "would you",
                                  "will you", "i want you to", "go ahead and", "now"]
    private static let trailing = ["please", "now", "byte", "right now", "for me"]

    /// Drops polite filler at either end, repeatedly: "hey byte, can you please jump now" -> "jump".
    static func strip(_ s: String) -> String {
        var s = s
        var changed = true
        while changed {
            changed = false
            for w in leading where s.hasPrefix(w + " ") { s = String(s.dropFirst(w.count + 1)); changed = true }
            for w in trailing where s.hasSuffix(" " + w) { s = String(s.dropLast(w.count + 1)); changed = true }
        }
        return s
    }
}
