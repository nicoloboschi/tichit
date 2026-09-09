# Tich

A macOS menu bar app that turns your English into native-sounding English.

Phase 1 (this): type or paste a sentence, get a natural rewrite plus a short list of
what changed and why — meant to be used right before you hit send on an email.

Phase 2 (planned): passively capture everything you write and surface the mistakes
you keep repeating. Every rewrite is already logged to
`~/Library/Application Support/Tich/history.jsonl` to feed that.

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
