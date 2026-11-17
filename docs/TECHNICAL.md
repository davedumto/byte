Byte: Offline AI Desk Pet for iPod touch 7th gen




  Byte: Offline AI Desk Pet for iPod touch 7th
  gen

  Overview
  Byte is a desk companion that lives on a jailbroken iPod touch (7th gen): a small robot in a
  3D room that reacts to how you work, wakes up when you say "Hey Byte", and answers out
  loud using a Llama model running entirely on the device. Nothing it hears or says leaves
  the iPod; the only network traffic is a local event from your Mac when you push code.

  Goals

          React to work in real time: steady typing makes it focused, idle time makes it sleepy, a
          git push makes it celebrate.
          Wake on "Hey Byte", listen, and answer short developer questions out loud, fully
          offline.
          Live in the 3D world exactly as designed in the prototype, moving on x, y and z.
          Act as a rubber duck for debugging and a light desk helper (timers, break nudges,
          end-of-day recap).
          Run for days on a desk without attention.

  Non-goals

          Being a capable general assistant. The model is tiny; its limits are part of the character.
          Cloud features, accounts or sync.
          Running on stock (non-jailbroken) iPods in v1.

  Design principles

      1. Offline by default. Inference, audio analysis and speech all happen on the iPod.
      2. Nothing is recorded. Audio is analysed in memory and discarded; only counters and
          mood values are kept.
      3. Personality over accuracy. Short, characterful answers beat long, wrong ones.
      4. Small and replaceable parts. The UI, the brain and the Mac companion talk over plain
         local HTTP, so each can be rebuilt alone.




                                                                                               Page 1 of 13
Byte: Offline AI Desk Pet for iPod touch 7th gen




  Build rules for agents (read first)
  The interface is finished. Any agent building Byte must ship the prototype's world,
  character and controls exactly as they are, and spend its effort on what sits behind them:
  voice, the model, the mood engine and the Mac link.

  Source of truth

          Live prototype: Byte: 3D world prototype
          Source files, kept in the repo under byte-world/ : main.js (scene, character, moods,
          controls, collisions), page.html (screen, HUD and controls markup and styles) and
           mini_bot.glb (the robot model).
          Build: npx esbuild main.js --bundle --minify --format=iife --
          loader:.glb=binary --outfile=bundle.js , then inline bundle.js into page.html
          where it says /*BUNDLE*/ . three.js is pinned at 0.170.0.

  Keep exactly as they are

          The room: layout, objects, colours, positions, the 9 x 7 tile floor and the cutaway walls.
          The robot: model, scale (1.15 units tall), face glow colour per mood, head poses, walk
          bob, hop, spin and the lying-down sleep on the bean bag.
          Mood spots: Happy and Celebrating on the rug, Focused at the desk, Sleepy lying on
          the bean bag, Bored by the plant, Night owl at the window.
          Axes and units: x is left and right (-4.1 to +4.1), z is back and forward (-3.1 to +3.1), y is
          up; one unit is one floor tile.
          Camera: start position, limits and drag-to-orbit behaviour.
          HUD: mood chip with energy bar, coordinates readout, axis gizmo, D-pad, Jump, Ask
          Byte and the question bubble.
          Collisions with the desk, bookshelf, plant, mailbox and lamp, and the bean bag as a
          surface Byte climbs onto.

  Allowed changes

          Drop the device frame, page header, mood pills and notes around the screen. On the
          iPod, the 852 x 480 screen area fills the display (it scales to the real 568 x 320 point
          screen).
          Replace the prototype's canned answers with the real model, and drive moods from
          the mood engine instead of the pills.
          Add the Listening, Thinking and Speaking states described under Voice, built only
          from the existing face glow, head poses and question bubble.


                                                                                                    Page 2 of 13
Byte: Offline AI Desk Pet for iPod touch 7th gen




          Performance fixes that do not change how anything looks: lower pixel ratio, a
          simplified robot mesh, a frame-rate cap.

  Anything else (new objects, colours, camera, layout or controls) needs David's sign-off
  before it is built.

  Credits that must stay visible in the app (an About screen is enough)

          Robot: "Mini_bot" by allzeronce, CC BY 4.0, from Sketchfab.
          Model: "Built with Llama", as the Llama 3.2 Community License requires.


  Hardware and platform constraints
  Every design choice follows from a 2GB, A10 device stuck on iOS 15 with a semi-tethered
  jailbreak.


     Item                     Value                        What it means for Byte

     Chip                     Apple A10 Fusion, arm64      CPU inference only; plan for a few tokens per
                                                           second

     RAM                      2GB, shared with iOS         Model file at most about 500MB; load it on
                                                           demand

     OS                       iOS 15.x (final supported)   Swift and SwiftUI targets capped at iOS 15 APIs

     Jailbreak                palera1n, rootless           Files live under /var/jb; daemons run from
                                                           /var/jb/Library/LaunchDaemons

     Boot                     Semi-tethered                After any reboot, daemons stop until re-
     model                                                 jailbroken from the Mac over USB

     Display                  4-inch, 1136 x 640           One creature, one line of speech, one input at a
                                                           time

     Audio                    Built-in mic and speaker     Enough for keystroke detection, push-to-talk
                                                           and speech output

     Network                  Wi-Fi and Bluetooth, no      All Mac to iPod traffic goes over the local Wi-Fi
                              cellular                     network


  Working without a USB cable




                                                                                                         Page 3 of 13
Byte: Offline AI Desk Pet for iPod touch 7th gen




  Day-to-day development can run entirely over Wi-Fi (see Development setup). Two things
  still need a data-capable Lightning cable: re-jailbreaking after a reboot, and charging. Until
  you have one, keep the iPod charged with any working charger and avoid reboots, low-
  battery shutdowns and iOS updates.


  System architecture
  Byte is one iPod app with two halves, a native Swift shell and the prototype's 3D world in a
  web view, plus a brain daemon on the iPod and a git alias on the Mac. The shell and the
  world talk through the window.byte bridge; everything else is plain local HTTP.




  Byte architecture · Mac and iPod over local Wi-Fi

  The four flows that matter:

      1. Talking: "Hey Byte" wakes the shell's listener; the shell records, transcribes, asks the
          brain, speaks the answer, and moves Byte through Listening, Thinking and Speaking
          via the bridge.
      2. Typing: key clicks reach the shared mic stream, the shell counts them, and the mood
          engine sends the new mood to the world.
      3. Pushing: git shipit pushes, the Mac sends a push event to port 7420, and the shell
          calls byte.celebrate() .
      4. Building: Claude Code changes and builds the code on the Mac, deploys it over SSH,
         and restarts the app or the brain.




                                                                                             Page 4 of 13
Byte: Offline AI Desk Pet for iPod touch 7th gen




  Component specs
  Byte has four moving parts on the iPod (mood engine, ears, brain, voice) and one on the
  Mac (the push hook).


  Mood engine
  Three values from 0 to 100 drive everything the creature shows and says.


     Value                    Rises when                        Falls when

     Energy                   Typing activity, a push, a chat   Idle time; faster after 23:00

     Happiness                Pushes, chats, breaks taken       Long sessions with no break

     Focus                    Sustained typing rhythm           Stop-start typing, long idle


          The engine ticks once per second and decays each value toward a resting level of 50.
          Visible states are picked from the values: Focused, Happy, Sleepy, Bored, Night owl,
          plus a 10-second Celebrating state on a push.
          State and counters are saved to /var/jb/var/mobile/byte/state.json every minute, so
          mood survives an app restart.


  Ears (keyboard detection)
          The native app shell captures the mic once with AVAudioEngine at 16kHz mono. The
          same stream feeds keystroke detection and the "Hey Byte" wake-word listener; the
          3D world never touches the mic.
          A high-pass filter keeps the sharp clicks of keys and drops most voice and room hum.
          Onset detection with an adaptive threshold counts clicks per 5-second window; a
          steady 2 to 10 clicks per second reads as typing.
          Only the counts reach the mood engine. Raw audio is never written to disk.
          Keystroke counting pauses while Byte is listening or speaking, so your voice and its
          voice never count as typing.


  Brain (on-device model)
          llama.cpp, built for arm64 with NEON and no GPU backend, running its llama-server
          on 127.0.0.1:8080.




                                                                                                Page 5 of 13
Byte: Offline AI Desk Pet for iPod touch 7th gen




          Model: Meta's Llama 3.2 1B Instruct in GGUF form. The 3B model is too large for 2GB
          of RAM; do not use it.


     Quantization                 File size        Use

     Q4_K_M                       808 MB           Default

     Q3_K_M                       691 MB           Fallback if iOS keeps killing the brain for memory


  Sizes from the Llama 3.2 1B Instruct GGUF listing.

          Context window of 1,024 tokens; answers capped at 80 tokens and streamed.
          The system prompt sets the persona and injects the current mood, for example: "You
          are Byte, a small robot who lives on a developer's desk. Mood: sleepy. Answer in at
          most two short sentences that sound natural spoken aloud. No markdown, no code
          blocks; say commands plainly."
          The model loads on the first "Hey Byte" of a session and unloads after 10 idle minutes
          to give RAM back to iOS. While it loads, Byte stays in the Thinking state.


  Voice: "Hey Byte"
  Saying "Hey Byte" starts a fully offline voice turn: wake, listen, transcribe, think, speak.
  Tapping Ask Byte starts the same turn without the wake word, and always works as the
  fallback.

      1. Wake. An always-on listener checks the shared mic stream for "hey byte". Use a
         custom openWakeWord-compatible model (ONNX or TFLite) trained for that phrase
          with openWakeWord's training notebook, then run it with ONNX Runtime or
          TensorFlow Lite for iOS; confirm the chosen runtime still supports iOS 15. Do not use
          Picovoice Porcupine: its iOS SDK needs iOS 16 or later, and the iPod tops out at iOS 15.
      2. Listen. Record until 1.2 s of silence (simple energy check), up to 10 s.
      3. Transcribe. whisper.cpp with the tiny English model on the device. Move to the base
          model only if accuracy is poor and speed allows.
      4. Think. Send the text and current mood to the brain; stream the answer.
      5. Speak. AVSpeechSynthesizer reads the answer sentence by sentence as it streams
          in, and the same words type into the question bubble.
      6. Return. Byte goes back to Idle and walks to its mood spot.




                                                                                                        Page 6 of 13
Byte: Offline AI Desk Pet for iPod touch 7th gen




     State                 Starts when                             What Byte does (existing visuals only)

     Idle                  Default                                 Mood behaviour exactly as in the prototype

     Listening             "Hey Byte" heard or Ask Byte            Sits up if lying down, walks to the ask spot
                           tapped                                  (0, 2.4), faces the camera; face glow pulses
                                                                   with your voice level; bubble shows
                                                                   "Listening..."

     Thinking              You stop talking                        Head tilts to one side, slow glow pulse;
                                                                   bubble shows your transcribed question

     Speaking              First words of the answer               Glow pulses on each spoken word; answer
                                                                   types into the bubble


          The wake-word listener pauses while Byte speaks, so the iPod's own speaker cannot
          wake it. Tap Byte to interrupt.
          A false wake ends quietly: no speech within 4 s returns Byte to Idle.


  Push hook (on the Mac)
          Git has no post-push hook, so Byte uses a git alias ( git shipit ) that runs git push
          and, on success, sends one push event to the iPod.
          A global pre-push hook is the fallback: it fires before the push, which is close enough
          for a celebration.
          Events are sent with curl to the iPod over the local network (see Interfaces).



  Interfaces
  Two HTTP endpoints carry all traffic: one on the local network for events from the Mac,
  one on localhost for the model.


     Endpoint                           Host and port        Exposed to      Purpose

     POST /event                        iPod, 0.0.0.0:7420   Local Wi-Fi     Mac sends push and other work
                                                             only            events

     GET /health                        iPod, 0.0.0.0:7420   Local Wi-Fi     Liveness check from the Mac
                                                             only




                                                                                                              Page 7 of 13
Byte: Offline AI Desk Pet for iPod touch 7th gen




     Endpoint                           Host and port    Exposed to      Purpose

     POST                               iPod,            The iPod only   App shell asks the brain; llama-
     /completion                        127.0.0.1:8080                   server API


  Event schema

     {
          "type": "push",
          "repo": "vellar-sdk",
          "branch": "main",
          "commits": 3,
          "ts": "2026-11-16T15:40:00Z"
     }


           type is one of push , commit , test_pass , test_fail , break ; unknown types are
          ignored, so new events can be added later.
          Commit messages are not sent. The recap only needs counts and repo names.

  Example call from the Mac

     curl -s -X POST http://byte.local:7420/event \
          -H "Authorization: Bearer $BYTE_TOKEN" \
          -H "Content-Type: application/json" \
          -d '{"type":"push","repo":"vellar-sdk","branch":"main","commits":3}'


  Discovery and security

          The iPod advertises itself with Bonjour as byte.local , so the Mac never needs its IP
          address.
          Every request carries a shared token, generated once on the iPod and copied to the
          Mac's environment.
          Port 8080 binds to localhost only, so nothing on the network can talk to the model
          directly.
          No endpoint accepts audio, files or commands; the worst a leaked token can do is
          make the pet dance.

  Native app to 3D world bridge

  The world runs in a WKWebView loaded from local files inside the app. The native shell
  (audio, voice, brain, events) talks to it through one small API that main.js exposes as
    window.byte ; each call reuses the functions the prototype's own buttons already call.



                                                                                                        Page 8 of 13
Byte: Offline AI Desk Pet for iPod touch 7th gen




     Direction                 Call                                Effect

     App to                      byte.setMood("sleepy")            Byte walks to that mood's spot, same
     world                                                         as the prototype's mood pills

     App to                      byte.setVoiceState("listening")   Switches between idle, listening,
     world                                                         thinking and speaking

     App to                      byte.say("text so far")           Updates the question bubble
     world

     App to                      byte.setLevel(0.6)                Voice level from 0 to 1; drives the face
     world                                                         glow pulse

     App to                      byte.celebrate()                  Push event: celebrate and raise the
     world                                                         mailbox flag

     World to                    {"type": "ready"}                 World finished loading
     app

     World to                    {"type": "askTapped"}             Start a voice turn without the wake
     app                                                           word


  World to app messages go through webkit.messageHandlers.byte.postMessage(...) .


  Development setup over Wi-Fi
  All building happens on the Mac, and every deploy goes to the iPod over SSH on the
  shared Wi-Fi network; no cable is needed while the iPod stays jailbroken.

  One-time setup on the iPod

      1. Open Sileo and install OpenSSH (and optionally rsync and curl ).
      2. In the NewTerm app, or on first SSH login, set new passwords for both mobile and
           root with passwd . Do this before anything else.
      3. Settings > General > Auto-Lock > Never, so the device stays awake on the desk.
      4. Settings > Wi-Fi > (i): note the IP address, and reserve it on your router so it never
          changes.

  One-time setup on the Mac




                                                                                                       Page 9 of 13
Byte: Offline AI Desk Pet for iPod touch 7th gen




     ssh-copy-id mobile@<ipod-ip>                  # key login, no password prompts
     ssh mobile@<ipod-ip> uname -a                 # confirm the connection
     brew install cmake ldid                       # build and fake-sign arm64 binaries


          Theos installed on the Mac builds the app shell and the daemons as rootless packages
          ( .deb ).
          llama.cpp is cross-compiled with CMake for iOS arm64, CPU only, then signed with
           ldid -S .

  Daily loop

      1. Change code on the Mac (by hand or with Claude Code).
      2. Build: make package (Theos) or the CMake build for the brain.
      3. Deploy: rsync the binary or .deb to the iPod, then install it over SSH with dpkg -i .
      4. Restart: launchctl kickstart -k for the daemon, or relaunch the app.
      5. Watch logs over SSH with tail -f /var/jb/var/mobile/byte/byte.log .

  Claude Code can run this whole loop itself once SSH key login works: it builds on the Mac,
  deploys over SSH and reads the logs back.

  Test the world on the iPod first

  Before building the native app, serve the built index.html from the Mac ( python3 -m
  http.server 8000 in byte-world/ ) and open http://<mac-ip>:8000 in Safari on the
  iPod, added to the Home Screen so it runs full screen. This shows how the A10 handles the
  robot and room. If it drops below 30 fps, apply the allowed performance fixes before
  anything else.


  Privacy, performance and risks
  Byte must stay trustworthy with an always-on mic and stay within a 2GB device; these
  budgets and rules are the acceptance bar for every release.

  Privacy rules

          No audio is stored, ever. Keystroke and wake-word analysis run on short in-memory
          buffers.
          The wake-word listener is always on, but it only answers one question on the iPod
          ("was that Hey Byte?") and sends nothing anywhere.




                                                                                          Page 10 of 13
Byte: Offline AI Desk Pet for iPod touch 7th gen




          Speech is transcribed only after the wake word or a tap. The audio is discarded
          straight after, and only the text reaches the model.
          Chat history is kept in memory for the current conversation only, and cleared after 10
          idle minutes.
          The only network listener is the event endpoint, and it accepts small JSON events,
          nothing else.

  Performance budgets (targets, to verify on the device)


     Budget                                                            Target

     3D world (web view) memory                                        under 250MB

     Brain memory, model loaded                                        under 1.1GB

     Wake-word listener CPU                                            under 10% of one core

     "Hey Byte" to Listening state                                     under 0.5 s

     End of your question to Byte's first spoken word                  under 4 s

     Model load time                                                   under 15 s

     3D world frame rate                                               30 fps or better


  Risks and mitigations


     Risk                                          Effect                           Mitigation

     Reboot or flat battery                        Daemons stop until re-           Keep it charged; buy a data
                                                   jailbroken over USB              Lightning cable; app falls back
                                                                                    to no-brain mode

     Model too slow or too big                     Long waits, iOS kills the        Drop to the 360M model;
                                                   process                          unload when idle

     iOS kills the brain for                       Questions fail                   Pet app restarts the daemon
     memory                                                                         and says it "dozed off"

     Keystroke detection fooled                    Wrong moods                      High-pass filter, rhythm
     by music or talking                                                            checks, and a sensitivity
                                                                                    setting




                                                                                                                Page 11 of 13
Byte: Offline AI Desk Pet for iPod touch 7th gen




     Risk                                          Effect                     Mitigation

     Heat on long sessions                         Throttling, battery wear   Model only on demand; lower
                                                                              frame rate when idle

     Open SSH with default                         Anyone on the Wi-Fi gets   Change passwords on day one;
     passwords                                     root                       key-only login




  Roadmap
  v1 puts the finished world on the iPod with a working brain; v2 adds "Hey Byte" and the
  full voice loop; v3 adds desk helpers.

  v1: weekend MVP

          SSH over Wi-Fi with key login and new passwords
          Prototype world running full screen on the iPod at 30 fps or better
          Native shell app hosting the world in a WKWebView, with the window.byte bridge
          llama.cpp with Llama 3.2 1B (Q4_K_M) answering typed questions from Ask Byte in
          the bubble
           git shipit alias on the Mac triggering byte.celebrate()

  v2: it hears you

          Shared mic stream, with keyboard detection driving the mood engine
          "Hey Byte" wake-word model trained and running on the iPod
          whisper.cpp transcription and spoken replies through AVSpeechSynthesizer
          Listening, Thinking and Speaking states in the world

  v3: it helps you

          End-of-day recap, spoken on request
          Timers and break nudges, spoken aloud
          More event types (test pass and fail, CI status)
          A one-tap clip of Byte reacting, for sharing

  Open questions

          Do the 3D world and the 808MB model fit in 2GB together, or must the world pause
          rendering while Byte thinks?
          How reliable is the "hey byte" model with fans, music and typing nearby?


                                                                                                      Page 12 of 13
Byte: Offline AI Desk Pet for iPod touch 7th gen




          Is whisper tiny accurate enough for coding words like git, regex and npm?
          Which iOS 15-compatible runtime, ONNX Runtime or TensorFlow Lite, runs the wake-
          word model with the least CPU?




                                                                                      Page 13 of 13
