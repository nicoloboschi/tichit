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

Two ways to power it, chosen in Settings (default **Automatic**):

- **Codex subscription** — reuses the OAuth login the Codex CLI already stores in
  `~/.codex/auth.json` to call `gpt-5.6-luna` on the Codex backend directly. No API
  key, nothing to pay per call, ~6-9s. Tokens are refreshed against the OAuth
  endpoint when the JWT `exp` claim is near and written back to `auth.json`, so the
  CLI and this app stay in sync. Auth and request shape are ported from Hindsight's
  `codex_auth.py` / `codex_llm.py`.
- **Gemini API key** — `gemini-3.7-flash` over HTTPS, ~3s. Get a key at
  https://aistudio.google.com/apikey; it is stored in the macOS Keychain.
  For `swift run` you can set `GEMINI_API_KEY` instead.

Automatic prefers Codex when it is signed in and falls back to Gemini. Both providers
are sent the identical brief (`Prompts.system`), so switching changes the model, not
the behaviour.

## Use

- Click the menu bar icon, or press **⌘⇧E** from anywhere.
- Type, pick a tone, press **↩** to improve. **⇧↩** inserts a line break.
- **⌘⇧C** copies the improved text.

Everything stays on this machine: rewrites are logged to
`~/Library/Application Support/Tich/history.jsonl`. Nothing is sent anywhere until
you ask for an improvement. Delete that file to wipe it.

Structured JSON output on both providers: `responseSchema` on Gemini, and on Codex a
single forced function tool whose parameters are the schema, so the backend does
constrained decoding and the answer arrives as tool-call arguments.
