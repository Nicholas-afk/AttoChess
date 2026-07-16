# The 278-Byte Chess Challenge

A static, client-side web tribute to [AttoChess](https://github.com/Nicholas-afk/AttoChess), the playable 278-byte DOS chess program by Nicholas Tanner derived from Dmitry Shechtman's LeanChess.

The browser challenge uses an independently structured TypeScript adaptation of the documented compact-board, movement, material-evaluation, and deterministic-search ideas. The web app is not itself 278 bytes and deliberately labels the original ruleset limitations.

## Local development

```bash
npm install
npm run dev
```

## Verification

```bash
npm test
npm run lint
```

The application has no accounts, database, application API, scheduled work, secrets, or runtime third-party service dependency. `.openai/hosting.json` intentionally declares no D1 or R2 resources.

See `public/third-party-notices.txt` for the complete upstream MIT notice and attribution.
