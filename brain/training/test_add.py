#!/usr/bin/env python3
"""Tests for add.py. Run: python3 -I brain/training/test_add.py"""
import io, json, sys, tempfile
from contextlib import redirect_stdout
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
import add

fails = count = 0
def check(cond, name):
    global fails, count
    count += 1
    if not cond: fails += 1; print("FAIL", name)

SYS = add.SYSTEM_PREFIX + "happy."
def ex(answer="Run git stash pop to bring your changes back.", q="how do I get my stash back", mood="happy",
       topic="git", source="https://git-scm.com/docs/git-stash", extra=None):
    msgs = [{"role": "system", "content": add.SYSTEM_PREFIX + mood + "."}, {"role": "user", "content": q},
            {"role": "assistant", "content": answer}] + (extra or [])
    return {"messages": msgs, "topic": topic, "source": source}

check(add.check(ex()) == [], "good example passes")
for mood in add.MOODS: check(add.check(ex(mood=mood)) == [], f"mood {mood}")
check(add.check(ex(mood="angry")) != [], "unknown mood")
bad_sys = ex(); bad_sys["messages"][0]["content"] = "You are a helpful assistant."
check(add.check(bad_sys) != [], "wrong system prompt")
check(add.check(ex(answer="Use `git stash pop`.")) != [], "backticks")
check(add.check(ex(answer="Steps:\n- run it")) != [], "line break / list")
check(add.check(ex(answer="**Run** git stash pop.")) != [], "bold")
check(add.check(ex(answer="Run git stash pop 🎉")) != [], "emoji")
check(add.check(ex(answer="One. Two. Three.")) != [], "three sentences")
check(add.check(ex(answer="Edit your .gitignore, e.g. add node_modules. That's it!")) == [], ".gitignore and e.g. don't split sentences")
check(add.check(ex(answer="Upgrade to v1.2.3 first. Then rerun npm install.")) == [], "version numbers don't split sentences")
check(add.check(ex(answer=" ".join(["word"] * 51) + ".")) != [], "over 50 words")
check(add.check(ex(answer="")) != [], "empty answer")
check(add.check(ex(q="  ")) != [], "empty question")
check(add.check(ex(source="http://x.com")) != [], "http source refused")
check(add.check(ex(source="none")) == [], "source none")
check(add.check(ex(topic="")) != [], "empty topic")
check(add.check(ex(extra=[{"role": "user", "content": "and undo that?"}])) != [], "must end with assistant")
check(add.check(ex(extra=[{"role": "user", "content": "and undo that?"},
                          {"role": "assistant", "content": "Run git stash to put them back."}])) == [], "follow-up conversation")
check(add.check(ex(extra=[{"role": "assistant", "content": "Again."}])) != [], "roles must alternate")
check(add.check([1]) != [] and add.check({"messages": "x"}) != [], "wrong shapes")

with tempfile.TemporaryDirectory() as d:
    batch, data = Path(d) / "batch.jsonl", Path(d) / "data.jsonl"
    lines = ["```json", json.dumps(ex()), json.dumps(ex(q="How do I get my STASH back?!")),
             json.dumps(ex(answer="Use `x`.", q="other")), "not json", json.dumps(ex(q="what is a branch",
             answer="A branch is a movable pointer to a commit.")), "```"]
    batch.write_text("\n".join(lines))
    with redirect_stdout(io.StringIO()) as out: rc = add.main([str(batch), "--dataset", str(data), "--dry-run"])
    check(not data.exists(), "dry run writes nothing")
    with redirect_stdout(io.StringIO()) as out: rc = add.main([str(batch), "--dataset", str(data)])
    rows = data.read_text().splitlines()
    check(len(rows) == 2, "two good, one duplicate, two rejected")
    check("1 duplicates skipped, 2 rejected" in out.getvalue(), "summary line")
    check(rc == 1, "exit 1 when something was rejected")
    with redirect_stdout(io.StringIO()): add.main([str(batch), "--dataset", str(data)])
    check(len(data.read_text().splitlines()) == 2, "re-adding the same batch adds nothing")

print(f"OK: {count} training checks passed" if not fails else f"{fails} of {count} training checks FAILED")
sys.exit(1 if fails else 0)
