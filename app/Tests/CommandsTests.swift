import Foundation

// Tests for Commands.swift (matcher and replies) and for how TurnController acts commands out.

func runCommandsTests() {
    func m(_ s: String) -> CommandMatch? { CommandMatcher.match(s) }
    func go(_ p: Place) -> CommandMatch { .action(.goTo(p)) }

    // MARK: Places, with the words people actually type
    let placePhrases: [(String, Place)] = [
        ("go to the plant", .plant), ("Go to the flower", .plant), ("walk to the flowers", .plant), ("go to the tree", .plant),
        ("go to the table", .desk), ("go to the desk", .desk), ("go to your desk", .desk), ("head to the computer", .desk),
        ("go to the bed", .beanBag), ("go to the bean bag", .beanBag), ("go to the beanbag", .beanBag), ("go to the couch", .beanBag),
        ("go to the window", .window), ("go to the moon", .window),
        ("go to the bookshelf", .bookshelf), ("walk over to the books", .bookshelf), ("go to the shelf", .bookshelf),
        ("go to the mailbox", .mailbox), ("go to the mail box", .mailbox), ("run to the letterbox", .mailbox),
        ("go to the rug", .rug), ("go to the middle", .rug), ("move to the carpet", .rug),
        ("go over to the plant", .plant), ("go back to the rug", .rug), ("go towards the window", .window), ("go near the plant", .plant)
    ]
    for (phrase, place) in placePhrases {
        eq(m(phrase), go(place), "'\(phrase)' -> \(place)")
    }
    eq(m("go look at the moon"), nil, "'go look at the moon' isn't a supported shape (falls through to the brain)")

    // MARK: Polite filler and punctuation
    eq(m("Hey Byte, can you please go to the plant?"), go(.plant), "filler and punctuation stripped")
    eq(m("go to the plant please!!"), go(.plant), "trailing please")
    eq(m("  GO   TO   THE   PLANT  "), go(.plant), "case and spaces")
    eq(m("could you go to the desk now, byte"), go(.desk), "filler at both ends")
    eq(m("Let\u{2019}s celebrate"), .action(.celebrate), "curly apostrophe")
    eq(m("let's party"), .action(.celebrate), "straight apostrophe")

    // MARK: Actions
    for s in ["jump", "Jump!", "jump up", "do a jump", "hop", "jump for me", "please jump"] { eq(m(s), .action(.jump), "'\(s)' -> jump") }
    for s in ["celebrate", "party", "dance", "party time", "celebrate!"] { eq(m(s), .action(.celebrate), "'\(s)' -> celebrate") }
    for s in ["go to sleep", "go to bed", "sleep", "take a nap", "nap", "bedtime"] { eq(m(s), .action(.sleep), "'\(s)' -> sleep") }
    for s in ["wake up", "get up", "rise and shine"] { eq(m(s), .action(.wakeUp), "'\(s)' -> wake up") }
    let moodPhrases: [(String, Mood)] = [
        ("focus", .focused), ("focus mode", .focused), ("Get to work!", .focused), ("lets focus", .focused), ("lock in", .focused),
        ("be bored", .bored), ("look bored", .bored), ("night owl", .night), ("Night owl mode", .night),
        ("hey byte, go night owl please", .night), ("cheer up", .happy), ("be happy", .happy), ("smile", .happy)
    ]
    for (s, mood) in moodPhrases { eq(m(s), .action(.mood(mood)), "'\(s)' -> \(mood)") }
    for s in ["how do I focus an input in javascript", "why am I bored", "what is a night owl", "is happy a git command",
              "focus on the error", "smile emoji code"] {
        eq(m(s), nil, "'\(s)' is a question, not a mood command")
    }
    for mood in [Mood.focused, .bored, .night, .happy] {
        check(!CommandMatcher.reply(.action(.mood(mood))).isEmpty, "reply for mood \(mood)")
    }
    eq(m("go to bed"), .action(.sleep), "'go to bed' sleeps, while...")
    eq(m("go to the bed"), go(.beanBag), "...'go to the bed' only walks to the bean bag")

    // MARK: Unknown places
    eq(m("go to the kitchen"), .unknownPlace("kitchen"), "unknown place")
    eq(m("go to the big red chair"), .unknownPlace("big red chair"), "three-word unknown place")
    eq(m("go to the room at the very end"), nil, "long phrase is not a place request")

    // MARK: Questions and chat must reach the brain
    for s in ["how do I jump to a git tag?", "what does git celebrate do", "how do I make my code sleep for a second",
              "jump to line 5 in vim", "where is the desk?", "can you go to the plant and tell me a joke about it ok",
              "come to the plant", "go", "go to", "go to the", "please", "", "   ", "?!",
              "what is a bean bag", "is the plant real", "how do I go to the next line in python",
              "I want to celebrate my release, what should I do"] {
        eq(m(s), nil, "'\(s)' is not a command")
    }

    // MARK: Replies
    eq(CommandMatcher.reply(go(.plant)), "On my way to the plant!", "place reply")
    eq(CommandMatcher.reply(go(.beanBag)), "On my way to the bean bag!", "bean bag spoken name")
    eq(CommandMatcher.reply(.unknownPlace("kitchen")),
       "There's no kitchen in my room. I can go to the desk, bean bag, plant, window, bookshelf, mailbox or rug.",
       "unknown place lists every place")
    for a in [WorldAction.jump, .celebrate, .sleep, .wakeUp] { check(!CommandMatcher.reply(.action(a)).isEmpty, "reply for \(a)") }
    for p in Place.allCases { check(Place.synonyms[p.spokenName] == p || Place.synonyms[p.rawValue] == p, "\(p) reachable by its own name") }
    eq(Set(Place.synonyms.values), Set(Place.allCases), "every place has a synonym")

    // MARK: World commands
    eq(WorldCommand.goTo(.beanBag).javaScript, "window.byte.goTo(\"beanBag\")", "goTo JS")
    eq(WorldCommand.jump.javaScript, "window.byte.jump()", "jump JS")

    // MARK: TurnController acting out commands
    final class Clock {
        var jobs: [(TimeInterval, () -> Void)] = []
        func schedule(_ d: TimeInterval, _ w: @escaping () -> Void) { jobs.append((d, w)) }
        func fire() { let j = jobs; jobs = []; j.forEach { $0.1() } }
    }
    func make() -> (TurnController, ScriptedBrain, Clock, () -> [String]) {
        var out: [String] = []
        let bridge = WorldBridge { out.append($0) }
        let brain = ScriptedBrain(), clock = Clock()
        let turns = TurnController(bridge: bridge, brain: brain, schedule: clock.schedule)
        turns.handle(.ready)
        return (turns, brain, clock, { out })
    }
    let speak = "window.byte.setVoiceState(\"speaking\")", idle = "window.byte.setVoiceState(\"idle\")"

    do { // command: reply, wait, close, act; brain never called
        let (turns, brain, clock, out) = make()
        turns.handle(.ask(text: "go to the plant"))
        eq(out(), [speak, "window.byte.say(\"On my way to the plant!\")"], "command shows its reply")
        eq(brain.calls.count, 0, "command never reaches the brain")
        eq(clock.jobs.map { $0.0 }, [TurnController.commandDelay], "action waits commandDelay")
        clock.fire()
        eq(Array(out().suffix(2)), [idle, "window.byte.goTo(\"plant\")"], "then idle, then goTo (order matters)")
    }
    do { // closing the bubble early acts at once, and only once
        let (turns, _, clock, out) = make()
        turns.handle(.ask(text: "jump"))
        turns.handle(.askClosed)
        eq(Array(out().suffix(2)), [idle, "window.byte.jump()"], "askClosed acts immediately")
        let n = out().count
        clock.fire()
        eq(out().count, n, "timer after close does nothing (no double jump)")
    }
    do { // a new message replaces a waiting command
        let (turns, brain, clock, out) = make()
        turns.handle(.ask(text: "go to the desk"))
        turns.handle(.ask(text: "how do I rebase?"))
        clock.fire()
        check(!out().contains("window.byte.goTo(\"desk\")"), "replaced command never runs")
        eq(brain.calls.count, 1, "the question went to the brain")
    }
    do { // a command replaces a streaming answer
        let (turns, brain, clock, out) = make()
        turns.handle(.ask(text: "how do I rebase?"))
        brain.calls[0].onText("Use")
        turns.handle(.ask(text: "celebrate"))
        check(brain.calls[0].handle.cancelled, "command cancels the answer in flight")
        brain.calls[0].onText("Use git late")
        check(!out().contains("window.byte.say(\"Use git late\")"), "old answer can't leak after a command")
        clock.fire()
        eq(Array(out().suffix(2)), [idle, "window.byte.celebrate()"], "celebrate acted out")
    }
    do { // sleep and wake change the mood the brain hears
        let (turns, brain, clock, out) = make()
        turns.handle(.ask(text: "go to sleep")); clock.fire()
        eq(out().last, "window.byte.setMood(\"sleepy\")", "sleep -> sleepy mood")
        eq(turns.mood, .sleepy, "controller mood updated")
        turns.handle(.ask(text: "wake up")); clock.fire()
        eq(out().last, "window.byte.setMood(\"happy\")", "wake up -> happy mood")
        turns.handle(.ask(text: "q")); eq(brain.calls.last?.mood, .happy, "brain hears the new mood")
        turns.handle(.ask(text: "night owl mode")); clock.fire()
        eq(out().last, "window.byte.setMood(\"night\")", "mood command -> setMood")
        turns.handle(.ask(text: "q2")); eq(brain.calls.last?.mood, .night, "brain hears the commanded mood")
    }
    do { // setMood (also used by commit events): changes once, repeats are no-ops
        let (turns, _, _, out) = make()
        turns.setMood(.focused)
        eq(out(), ["window.byte.setMood(\"focused\")"], "setMood sends once")
        turns.setMood(.focused)
        eq(out().count, 1, "same mood again sends nothing (no walking back and forth)")
        eq(turns.mood, .focused, "controller mood updated")
        turns.handle(.ask(text: "go to sleep")); turns.handle(.askClosed)
        eq(turns.mood, .sleepy, "a command still changes it")
        turns.setMood(.focused)
        eq(out().last, "window.byte.setMood(\"focused\")", "a commit wakes Byte into Focused")
    }
    do { // unknown place: reply only, bubble stays open, nothing scheduled
        let (turns, brain, clock, out) = make()
        turns.handle(.ask(text: "go to the kitchen"))
        eq(out().count, 2, "speaking + reply only")
        check(out().last?.contains("no kitchen in my room") == true, "lists the places")
        eq(clock.jobs.count, 0, "nothing scheduled"); eq(brain.calls.count, 0, "brain not called")
        turns.handle(.askClosed)
        eq(out().count, 2, "closing after an unknown place does nothing more")
    }
    do { // world reload drops a waiting command
        let (turns, _, clock, out) = make()
        turns.handle(.ask(text: "jump"))
        turns.reset()
        clock.fire()
        check(!out().contains("window.byte.jump()"), "reset cancels a waiting command")
    }
}
