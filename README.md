<img src="docs/icon.png" width="120" align="right" alt="Tichit">

# Tichit

A macOS menu bar app that turns what you write into natural, native-sounding English —
and explains, in Italian, why it changed.

Built for a fluent-but-not-native speaker who wants the correction *and* the rule.

## What it does

The popover has three tabs — **Improve**, **Captured**, **History**.

Press **⌘⇧E** anywhere, type a sentence, press **↩**.

- **Write in English** → it is rewritten to sound like a native wrote it.
- **Write in Italian** → it is translated the way a native would actually put it, with
  the word-for-word version shown alongside so you can see where idiomatic English
  departs from a literal translation.

Either way you get back:

- the improved sentence, ready to copy (**⌘⇧C**)
- an optional second phrasing
- **what changed and why**, explained in Italian
- a **glossary** of the words and expressions used — idioms, phrasal verbs,
  collocations — with their Italian meaning and a note on any false friend

Everything you improve is kept in a searchable history (**⌘Y**), so you can look back
at the mistakes you keep making.

### Example

Input (Italian):

> Ti faccio sapere appena ho novità, non vorrei farti perdere tempo.

Output:

> **Word for word** — I make you know as soon as I have news, I would not want to make you lose time.
>
> **In English** — I'll let you know as soon as I have an update. I don't want to waste your time.
>
> - `Ti faccio sapere` → `I'll let you know` — In inglese "far sapere" si traduce con
>   "let (someone) know", non con "make you know" (calco errato da evitare).
> - `farti perdere tempo` → `waste your time` — "Far perdere tempo a qualcuno" è
>   un'espressione fissa: "to waste someone's time".

## The menu bar dot

The icon carries a status dot: **grey** idle, **yellow** while it is thinking,
**green** when an answer is waiting for you. A notification fires when the answer
lands while you are looking at something else — click it to jump straight to the text.

## Capture (optional)

Turn on **Capture my typing** in Settings to record the sentences you write, so you
see the mistakes you make in the wild rather than only the ones you thought to check.

Each captured sentence is sent for review automatically. The model decides in the same
pass whether the sentence is actually **worth correcting** — a grammar error, a calque
from Italian, an unnatural collocation — and only then does it reach the **Captured**
tab and fire a notification. Natural English, casual shorthand ("the deploy is done",
"on staging") and pure matters of taste are reviewed and dropped, so you are
interrupted for lessons, not for style opinions.

**Tone** (Settings → Correct captured text as) decides the register captured sentences
are judged against. The default, **As written**, keeps your own register — a quick
Slack line stays a quick Slack line, and only real mistakes are flagged. Pick `Formal`
instead and you will be told every time a chat message is not a business email.

Two registries, kept separate so a re-review never loses the original:

| File | Holds |
| --- | --- |
| `captured.jsonl` | every raw sentence, exactly as typed |
| `reviews.jsonl` | the model's verdict on each: rewrite, notes, worth-reporting |

macOS will ask for Accessibility permission; capture starts by itself the moment you
grant it. A red dot in the popover shows while it is live.

Capture is an **allowlist** — only **Brave Browser** and **Slack**
(`KeystrokeCapture.capturedApps`). Every other app is ignored, including any installed
later. Within those two, also never recorded:

- anything typed while macOS secure input is on (password fields)
- ⌘/⌃/⌥ shortcuts
- anything that doesn't look like prose: under 12 chars, fewer than 3 words,
  under 55% letters, or starting with a URL or path

A sentence is closed **only when you press Return** — the moment you committed to the
words. Half-typed thoughts are never reviewed, and switching away from Brave or Slack
discards whatever was in progress. Everything is stored locally in
`~/Library/Application Support/Tichit/captured.jsonl`.

> **Note:** the app is ad-hoc signed, so its code hash changes on every rebuild and
> the Accessibility grant stops matching — while System Settings still shows Tichit as
> enabled, which makes it look like the app is lying. Settings → **Reset and ask
> again** clears the stale record and re-prompts.
>
> To avoid it entirely, build with a real code-signing identity:
>
> ```sh
> TICHIT_SIGN_IDENTITY="Apple Development: you@example.com" ./scripts/build-app.sh --install
> ```
>
> Any stable identity works, including a self-signed one created in Keychain Access
> (Certificate Assistant → Create a Certificate → Code Signing).

## Install

Download the `.dmg` from [Releases](../../releases), open it, drag Tichit to
Applications. The app is unsigned, so the first launch needs a right-click → Open.

Or build it yourself — no Xcode required, just the Swift toolchain:

```sh
./scripts/build-app.sh --install   # -> /Applications/Tichit.app
```

To start it automatically, add it in System Settings → General → Login Items.

## Setup

Two ways to power it, chosen in Settings (default **Automatic**):

- **Codex subscription** — reuses the OAuth login the Codex CLI already stores in
  `~/.codex/auth.json` to call `gpt-5.6-luna` directly. No API key, nothing to pay
  per call, ~6-9s. Tokens are refreshed against the OAuth endpoint when the JWT
  `exp` claim is near and written back to `auth.json`, so the CLI and this app
  stay in sync.
- **Gemini API key** — `gemini-3.7-flash`, ~3s. Get a key at
  [aistudio.google.com/apikey](https://aistudio.google.com/apikey); it is stored in
  the macOS Keychain.

Automatic prefers Codex when it is signed in and falls back to Gemini. Both providers
receive the identical brief (`Prompts.swift`), so switching changes the model, not the
behaviour.

## Keys

| Key | Does |
| --- | --- |
| `⌘⇧E` | Open from anywhere |
| `↩` | Improve |
| `⇧↩` | New line |
| `⌘⇧C` | Copy the improved text |
| `⌘Y` | History |

## Privacy

Everything stays on your machine. History lives in
`~/Library/Application Support/Tichit/history.jsonl` — plain JSONL, delete it to wipe
it. Text is sent to your chosen provider only when you ask for an improvement.

## Layout

```
Sources/Tichit/
  AppDelegate.swift        menu bar item, popover, global hotkey, notifications
  ComposerView.swift       the popover UI and its view model
  SentenceEditor.swift     NSTextView wrapper: ↩ submits, ⇧↩ breaks lines
  HistoryWindow.swift      searchable history
  SettingsWindow.swift     provider choice and API key
  Prompts.swift            the single rewrite brief, shared by both providers
  GeminiClient.swift       Gemini provider
  CodexDirectClient.swift  Codex provider (forced-function-tool structured output)
  CodexAuth.swift          Codex OAuth: expiry, refresh, write-back
  RootView.swift           the tabbed shell: Improve / Captured / History
  Capture.swift            optional system-wide typing capture (Brave + Slack)
  ReviewQueue.swift        reviews captured sentences serially, decides what to flag
  Strikethrough.swift      plain-text strikethrough for notification bodies
  CapturedView.swift       the reviewed captures, flagged ones first
  Logo.swift               the mark, drawn in code, and the status dot
```
