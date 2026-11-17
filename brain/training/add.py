#!/usr/bin/env python3
"""Check pasted training examples and append the good ones to byte-style.jsonl.

Usage: python3 -I brain/training/add.py BATCH.jsonl [--dataset PATH] [--dry-run]

Each line must follow the format in the data-gathering prompt: the exact Byte system prompt with one of the
six moods, user/assistant turns ending with the assistant, a short topic label and a source URL (or "none").
Assistant answers must sound like Byte: at most 2 sentences and 50 words, no markdown, code blocks or emoji.
Lines whose last question is already in the dataset (or earlier in the batch) are skipped as duplicates.
Nothing is written unless at least one line passes; rejected lines are reported with their reasons.
"""
import argparse
import json
import re
import sys
from collections import Counter
from pathlib import Path

HERE = Path(__file__).resolve().parent
DATASET = HERE / "byte-style.jsonl"

# Must match Persona.systemPrompt in app/Sources/LlamaBrain.swift.
SYSTEM_PREFIX = ("You are Byte, a small robot who lives on a developer's desk. "
                 "Answer in at most two short sentences that sound natural spoken aloud. "
                 "No markdown, no code blocks; say commands plainly. Mood: ")
MOODS = {"happy", "focused", "sleepy", "bored", "night owl", "celebrating"}
MAX_WORDS = 50
MAX_SENTENCES = 2

# A sentence ends at . ! or ? followed by a space and a capital letter, or at the end of the text.
# "e.g. this" or ".gitignore" or "v1.2" don't end sentences.
SENTENCE_END = re.compile(r"[.!?](?=\s+[A-Z\"'])|[.!?]+[\"')]*\s*$")
ABBREVIATIONS = re.compile(r"\b(e\.g|i\.e|etc|vs|Mr|Dr)\.", re.IGNORECASE)
MARKDOWN = re.compile(r"`|\*\*|__|^\s*([-*+]|#{1,6}|\d+\.)\s", re.MULTILINE)
EMOJI = re.compile("[\U0001F000-\U0001FAFF☀-➿️]")


def sentences(text):
    return len(SENTENCE_END.findall(ABBREVIATIONS.sub("eg", text.strip()))) or 1


def answer_problems(text):
    problems = []
    if not text.strip():
        return ["empty answer"]
    if "\n" in text:
        problems.append("answer has a line break")
    if MARKDOWN.search(text):
        problems.append("answer has markdown or backticks")
    if EMOJI.search(text):
        problems.append("answer has an emoji")
    words = len(text.split())
    if words > MAX_WORDS:
        problems.append(f"answer is {words} words (max {MAX_WORDS})")
    n = sentences(text)
    if n > MAX_SENTENCES:
        problems.append(f"answer is {n} sentences (max {MAX_SENTENCES})")
    return problems


def check(obj):
    """Returns a list of problems (empty means the example is good)."""
    if not isinstance(obj, dict):
        return ["not a JSON object"]
    msgs = obj.get("messages")
    if not isinstance(msgs, list) or len(msgs) < 3:
        return ["needs messages: system, user, assistant"]
    if not all(isinstance(m, dict) and isinstance(m.get("role"), str) and isinstance(m.get("content"), str) for m in msgs):
        return ["every message needs a string role and content"]
    problems = []
    system = msgs[0]
    if system["role"] != "system" or not system["content"].startswith(SYSTEM_PREFIX):
        problems.append("system prompt isn't Byte's exact prompt")
    else:
        mood = system["content"][len(SYSTEM_PREFIX):]
        if not mood.endswith(".") or mood[:-1] not in MOODS:
            problems.append(f"unknown mood {mood!r}")
    for i, m in enumerate(msgs[1:]):
        want = "user" if i % 2 == 0 else "assistant"
        if m["role"] != want:
            problems.append(f"message {i + 2} should be {want}, got {m['role']}")
            break
    if msgs[-1]["role"] != "assistant":
        problems.append("must end with an assistant answer")
    for m in msgs[1:]:
        if m["role"] == "user" and not m["content"].strip():
            problems.append("empty question")
        if m["role"] == "assistant":
            problems += answer_problems(m["content"])
    topic = obj.get("topic")
    if not (isinstance(topic, str) and 0 < len(topic.strip()) <= 30):
        problems.append("topic must be a short label")
    source = obj.get("source")
    if not (source == "none" or (isinstance(source, str) and re.match(r"https://\S+$", source))):
        problems.append("source must be an https URL or \"none\"")
    return problems


def key(obj):
    """Duplicate key: the whole conversation's user questions, normalised."""
    qs = [m["content"] for m in obj["messages"] if m["role"] == "user"]
    return " | ".join(re.sub(r"[^a-z0-9 ]", "", q.lower()).strip() for q in qs)


def load(path):
    if not path.exists():
        return []
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("batch")
    ap.add_argument("--dataset", default=str(DATASET))
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args(argv)

    dataset = Path(args.dataset)
    existing = load(dataset)
    seen = {key(o) for o in existing}
    good, rejected, dupes = [], [], 0

    raw = Path(args.batch).read_text(encoding="utf-8")
    # Tolerate the code fences a chat window adds around a pasted batch.
    lines = [l for l in raw.splitlines() if l.strip() and not l.strip().startswith("```")]
    for n, line in enumerate(lines, 1):
        try:
            obj = json.loads(line)
        except json.JSONDecodeError as e:
            rejected.append((n, [f"not valid JSON ({e.msg})"], line))
            continue
        problems = check(obj)
        if problems:
            rejected.append((n, problems, line))
            continue
        k = key(obj)
        if k in seen:
            dupes += 1
            continue
        seen.add(k)
        good.append(obj)

    if good and not args.dry_run:
        dataset.parent.mkdir(parents=True, exist_ok=True)
        with dataset.open("a", encoding="utf-8") as f:
            for obj in good:
                f.write(json.dumps(obj, ensure_ascii=False) + "\n")

    total = existing + ([] if args.dry_run else good)
    print(f"batch: {len(lines)} lines, {len(good)} added{' (dry run)' if args.dry_run else ''}, "
          f"{dupes} duplicates skipped, {len(rejected)} rejected")
    for n, problems, line in rejected:
        print(f"  line {n}: {'; '.join(problems)}\n    {line[:140]}")
    counts = Counter(o.get("topic") for o in total)
    print(f"dataset: {len(total)} examples  " + ", ".join(f"{t} {c}" for t, c in sorted(counts.items())))
    return 0 if not rejected else 1


if __name__ == "__main__":
    sys.exit(main())
