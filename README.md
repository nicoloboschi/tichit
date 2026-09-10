# Tich

A macOS menu bar app that turns your English into native-sounding English.

Phase 1 (this): type or paste a sentence, get a natural rewrite plus a short list of
what changed and why — meant to be used right before you hit send on an email.

Write in **English** and it is rewritten to sound native. Write in **Italian** and it is
translated the way a native speaker would actually put it, with the word-for-word
version shown alongside so you can see where idiomatic English departs from it.
Either way you get a glossary of the words and expressions used, explained in Italian,
and the reason for each change is written in Italian too.

Phase 2 (now): passively capture everything you type, one sentence per row, so the
app can later surface the mistakes you keep repeating.

## Capture

Turn on **Capture my typing** in the ⋯ menu. macOS will ask for Accessibility
permission (System Settings → Privacy & Security → Accessibility). A red dot in the
popover shows whenever capture is live, and the Captured tab of the History window
shows what has been recorded.

Sentences are split on `.`/`!`/`?`, after 3s idle, or when you switch app. Return is
a boundary only in chat apps where it sends the message (`returnSendsApps`); in a mail
client or editor it is treated as a line break and the lines are joined, so a paragraph
typed across several lines stays one sentence.

Capture is an **allowlist**: only Brave Browser and Slack are recorded
(`KeystrokeCapture.capturedApps`). Every other app is ignored, including any installed
later — add a bundle ID there to widen it.

Within those two apps, also **not** recorded:

- anything typed while macOS secure input is on (password fields)
- ⌘/⌃/⌥ shortcuts
- anything that doesn't look like prose: under 12 chars, fewer than 3 words,
  under 55% letters, or starting with a URL or path

Everything stays on this machine in
`~/Library/Application Support/Tich/`: `history.jsonl` (rewrites) and
`captured.jsonl` (passive capture). Nothing is sent anywhere until you press Improve.
Delete either file to wipe it.

## Build

```
./scripts/build-app.sh          # -> build/Tich.app
open build/Tich.app
```

Copy it to `/Applications` when you like it. No Xcode needed, just the Swift toolchain.

## Setup

On first launch it opens Settings and asks for a Gemini API key
(https://aistudio.google.com/apikey). It is stored in the macOS Keychain.
For `swift run` during development you can set `GEMINI_API_KEY` instead.

## Use

- Click the menu bar icon, or press **⌘⇧E** from anywhere.
- Type, pick a tone, hit **⌘↩**.
- **⌘⇧C** copies the improved text.

Model: `gemini-3.7-flash`, structured JSON output, thinking disabled for latency.
