# Byte

**An offline AI desk pet that lives on an old iPod touch.**

Byte is a small robot in a cozy 3D room, running full screen on a jailbroken iPod touch (7th gen) that sits on your desk. Ask it a coding question and it answers with a language model running **entirely on the iPod**: no cloud, no account, no API key. Push code from your Mac with `git shipit` and Byte throws a little party.

```
  Mac                                   iPod touch 7th gen (iOS 15, A10, 2 GB RAM)
  ───                                   ─────────────────────────────────────────
  git shipit ──► byte-event ──Wi-Fi──►  Byte app (Swift, Theos)
                 (Bonjour "Byte",         ├─ WKWebView: the 3D world (three.js)
                  port 7420, token)       │    window.byte.setMood / say / celebrate / goTo …
                                          ├─ Event listener :7420  (push → celebrate)
                                          └─ Brain client ──localhost:8080──► llama-server
                                                                                (launchd daemon,
                                                                                 Qwen2.5-Coder 0.5B)
```

## What it does today (v1)

- **A living room.** Byte wanders a hand-built 3D room (desk, bean bag, plant, window, bookshelf, mailbox, rug) with moods: Happy, Focused, Sleepy, Bored, Night owl and Celebrating.
- **Ask Byte.** Tap *Ask Byte*, type a question, and the answer streams into the speech bubble. The first word appears in about **0.3–0.5 s** and the rest at about **27 tokens/s**, all on the iPod's A10.
- **Follow-up questions.** While the bubble is open Byte remembers the last two exchanges, so "and how do I undo that?" works. Nothing is saved to disk.
- **Moods you can set.** "focus mode", "be bored", "night owl mode", "cheer up", "go to sleep" and "wake up" change how Byte looks and how it talks. A `git commit` makes Byte Focused.
- **Typed commands.** "go to the plant", "go to bed", "jump", "celebrate", "wake up" and friends are matched before the model is asked, so they're instant and always work. Questions like *"how do I jump to a git tag?"* still go to the brain.
- **`git shipit`.** A git alias that runs `git push` and, if new commits went out, tells Byte, which celebrates for 10 s with the mailbox flag up.
- **Stays smooth while thinking.** The world drops to 15 fps while the model is generating (the A10 has two fast cores), then returns to 60 fps.

## How it's built

| Part | Where | What |
|---|---|---|
| 3D world | [`byte-world/`](byte-world) | three.js scene in `main.js`, bundled by esbuild and inlined into one `index.html`. Exposes a small `window.byte` API. |
| App shell | [`app/`](app) | Theos Swift app: hosts the world in a WKWebView, runs question turns and typed commands, talks to the brain, listens for push events, shows the About/credits sheet. |
| Brain | [`brain/`](brain) | llama.cpp's `llama-server` cross-compiled for the A10 (CPU/NEON, static), plus a tiny root launcher, shipped as a rootless `.deb` with a launchd daemon on `127.0.0.1:8080`. |
| Mac side | [`tools/mac/`](tools/mac) | `byte-event` (sends events), `git-shipit` (the alias), `git-commit-hook` and `install.sh`. |
| Spec | [`docs/TECHNICAL.md`](docs/TECHNICAL.md) | The full design spec (text copy of the PDF in the root). |
| Build log | [`BUILD_LOG.md`](BUILD_LOG.md) | Every decision, measurement and dead end, in order. Start here to see *why* things are the way they are. |

### Making an LLM run on a 2019 iPod

Some of the interesting problems (details in the build log):

- **The 6 MB jetsam limit.** iOS gives third-party launch daemons a 6 MB memory limit, so llama-server was killed the moment it loaded the model. [`brain/launcher/byte-brain-launcher.c`](brain/launcher/byte-brain-launcher.c) starts as root, lifts its own limit with `memorystatus_control` (private entitlement), drops to the `mobile` user for good, then `exec`s llama-server. The raised limit survives the exec.
- **Background priority.** launchd's default "adaptive" daemon priority starved generation (no answer in 2 minutes). `ProcessType Interactive` fixed it.
- **Picking a model that fits.** Llama 3.2 1B Q3_K_M fit but answered coding questions poorly. Qwen2.5-Coder 1.5B answered well on the Mac but thrashed the iPod (~11,000 page-ins/s, no answer at all). **Qwen2.5-Coder 0.5B Q8_0** (676 MB) was the sweet spot: better answers than Llama and about 3× faster.
- **Sharing two CPU cores.** WebGL at 60 fps took about 75% of the CPU and cut generation to about 1 token/s, hence the 15 fps "busy" mode.

### Security

The iPod sits on your home Wi-Fi with a jailbreak, so the design is defensive:

- The brain listens on **localhost only** and requires a **bearer token** (`brain.token`, 32 random bytes, mode 600), so web pages open in Safari on the device can't use it.
- Push events use a **separate token** (`events.token`), so a leaked Mac token can only make Byte dance. The listener accepts private/link-local addresses only, takes a few connections at a time, caps bodies at 4 KB and times out slow clients.
- Tokens are compared in constant time and never appear on a command line (`ps`). Logs record counts and states, never questions, answers or repo names.

## Hardware and requirements

- **iPod touch 7th gen** on iOS 15, jailbroken with palera1n (rootless), with OpenSSH and key login. Change the default `mobile`/`root` passwords first.
- **A Mac** with Xcode, [Theos](https://theos.dev), `ldid`, CMake, Node.js and Python 3.

> ⚠️ palera1n on this device is semi-tethered: a reboot drops the jailbreak until you re-run it over a cable. Nothing here ever reboots the device.

## Build and install

Run each step from the repository root.

```sh
# 1. The 3D world (also run automatically by the app build)
(cd byte-world && npm install && ./build.sh)      # -> index.html; open it in a browser to play with it

# 2. The brain: llama.cpp b12444 for the A10, the launcher, and the .deb
(cd brain && ./build.sh && ./package.sh && ./test.sh)

# 3. The model (676 MB), downloaded on your Mac and copied to the iPod
curl -LO https://huggingface.co/Qwen/Qwen2.5-Coder-0.5B-Instruct-GGUF/resolve/main/qwen2.5-coder-0.5b-instruct-q8_0.gguf
shasum -a 256 qwen2.5-coder-0.5b-instruct-q8_0.gguf
# expect e1a77721fa97d412f121878223eec81fb4ae6f271e18f922d746711f67b344d1
scp qwen2.5-coder-0.5b-instruct-q8_0.gguf mobile@<ipod>:/var/jb/var/mobile/byte/models/

# 4. The app
(cd app && ./test.sh && make package && ./deploy.sh)  # copies the .deb over and prints the sudo install command

# 5. git shipit and the commit hook on the Mac (asks before changing anything)
tools/mac/install.sh
```

Packages install with `sudo dpkg -i …` on the iPod. The brain daemon starts once the model file exists.

## Tests

Every part has tests that run on the Mac, no iPod needed:

```sh
app/test.sh          # Swift: bridge, turns, commands, memory, brain client vs a fake llama-server,
                     #        HTTP parser/router, and a real event listener on a local port
brain/test.sh        # C: token-file creation and hardening (symlinks, wrong owner, malformed files…)
tools/mac/test.sh    # shell: byte-event vs a fake Byte, Bonjour discovery, git-shipit vs a temp repo
```

## Using it

- **Ask:** tap *Ask Byte*, type, send. Closing the bubble ends the conversation.
- **Commands:** `go to the desk | bean bag | bed | plant | window | bookshelf | mailbox | rug`, `jump`, `celebrate`, `dance`.
- **Moods:** `focus mode` / `get to work`, `be bored`, `night owl mode`, `cheer up`, `go to sleep`, `wake up`. Moods stay until something changes them.
- **Commit:** every `git commit` makes Byte Focused. It's a global config-based hook that runs alongside your repos' own hooks and never slows a commit. Turn it off for one repo with `git config hook.byte.enabled false`.
- **Push:** `git shipit` (any `git push` arguments work). Pushing only tags, a dry run or a failed push doesn't celebrate.
- **Credits:** long-press the mood chip.
- **Check from the Mac:** `tools/mac/byte-event health`

> Byte runs a 0.5B-parameter model. It's quick and often helpful, but it can be **confidently wrong**. Treat its answers as hints, especially for anything destructive like `git reset`.

## Roadmap

- **v1 (now):** the world on the iPod, typed questions with on-device answers, commands, conversation memory, `git shipit`.
- **Next:** a style-only fine-tune so answers are reliably short and spoken (no code blocks).
- **v2, it hears you:** shared mic stream, keystroke detection driving a mood engine, a "Hey Byte" wake word, whisper.cpp transcription, spoken replies.
- **v3, it helps you:** desk helpers.

## Credits

- Robot: **"Mini_bot"** by [allzeronce](https://sketchfab.com/allzeronce), licensed [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/), from [Sketchfab](https://sketchfab.com/3d-models/mini-bot-bb951fb4e285427cbbf6b9241eac78cb). Animated and recoloured for Byte.
- Brain: **[Qwen2.5-Coder 0.5B Instruct](https://huggingface.co/Qwen/Qwen2.5-Coder-0.5B-Instruct)** by the Qwen team, Alibaba Cloud, licensed Apache 2.0. Runs with **[llama.cpp](https://github.com/ggml-org/llama.cpp)** (MIT).
- 3D: [three.js](https://threejs.org) (MIT). Fonts: Inter and Space Grotesk, SIL Open Font License 1.1.
- Room: original, built for Byte.
