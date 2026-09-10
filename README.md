# Tich

A macOS menu bar app that turns your English into native-sounding English.

Phase 1 (this): type or paste a sentence, get a natural rewrite plus a short list of
what changed and why — meant to be used right before you hit send on an email.

Write in **English** and it is rewritten to sound native. Write in **Italian** and it is
translated the way a native speaker would actually put it, with the word-for-word
version shown alongside so you can see where idiomatic English departs from it.
Either way you get a glossary of the words and expressions used, explained in Italian,
and the reason for each change is written in Italian too.

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
- Type, pick a tone, press **↩** to improve. **⇧↩** inserts a line break.
- **⌘⇧C** copies the improved text.

Everything stays on this machine: rewrites are logged to
`~/Library/Application Support/Tich/history.jsonl`. Nothing is sent anywhere until
you ask for an improvement. Delete that file to wipe it.

Model: `gemini-3.7-flash`, structured JSON output, thinking disabled for latency.
