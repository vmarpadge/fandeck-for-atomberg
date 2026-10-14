# FanDeck for Atomberg — macOS menu bar app

Control Atomberg smart ceiling fans from your Mac's menu bar: power on/off, speed (1–6),
and light on/off. Built on the **official [Atomberg Home Public API](https://developer.atomberg-iot.com/overview)** —
no reverse engineering, no traffic sniffing, no firmware changes.

> **Trademark & affiliation.** This project is an independent, unofficial tool. It is not
> affiliated with, authorized, endorsed by, or sponsored by Atomberg Technologies Pvt. Ltd.
> "Atomberg" and all related names, logos, and marks are trademarks of their respective owner
> and are used here only descriptively, to indicate compatibility. The source code in this
> repository is © 2026 Vineethkumar Marpadge and released under the [MIT License](LICENSE); that
> licence covers this code only and grants no rights in any third-party trademark or API.

---

## Contents

- [Quick start](#quick-start)
- [Get your API credentials](#get-your-api-credentials)
- [How it works](#how-it-works)
- [Requirements](#requirements)
- [Build it yourself](#build-it-yourself)
- [Using it](#using-it)
- [API quota and how it is managed](#api-quota-and-how-it-is-managed)
- [Security](#security)
- [Project layout](#project-layout)
- [Troubleshooting](#troubleshooting)
- [Support](#support)
- [License](#license)

---

## Quick start

1. **Get the app.** Download `FanDeck-for-Atomberg.zip` from the [Releases page](../../releases),
   unzip it, and move **FanDeck for Atomberg.app** to your `Applications` folder. (Prefer to compile it?
   See [Build it yourself](#build-it-yourself).)
   - The build is ad-hoc signed, so the first launch needs a one-time override: **right-click the
     app → Open → Open** again at the warning (or allow it under *System Settings → Privacy & Security*).
2. **Get your credentials** from the phone app: **Atomberg Home → Profile → Developer Options**,
   enable developer mode, and copy the **API key** and **refresh token**.
3. **Paste them into the app:** click the fan icon in the menu bar, enter the API key and refresh
   token in the two boxes, and press **Save**. Your fans appear within a few seconds — no Terminal needed.
4. Flip a fan on/off, drag the speed slider (1–6), toggle its light, and tick **Launch at login**.

## Get your API credentials

The app needs two values from **your own** Atomberg account: an **API key** and a **refresh token**.
You generate them in the Atomberg Home mobile app (not on a website), and they only work for the
Wi-Fi devices on the account that created them.

**Step by step:**

1. Install and open the **Atomberg Home** app on your phone
   ([iOS App Store](https://apps.apple.com/app/atomberg-home/id1608682336) /
   [Google Play](https://play.google.com/store/apps/details?id=com.atomberg.atomberg)) and sign in
   with the account your fans are set up on.
2. Make sure your fan(s) already appear in the app and are **online** — this project controls the
   same devices the app sees.
3. Tap the **Profile** tab (bottom bar), then open **Developer Options** / **Developer Mode**.
   (If you don't see it, update the app to the latest version — the developer section is only in
   recent releases.)
4. **Enable developer mode.** The app then shows two values:
   - **API Key** — a long string sent as the `x-api-key` header on every request.
   - **Refresh Token** — a long-lived token the app exchanges for a short-lived (24 h) access token.
5. Copy both. On a phone, use the app's copy button and paste them somewhere you can reach from your
   Mac (e.g. a note you sync, or a password manager). **Treat them like passwords** — anyone with
   both can control your fans.
6. In the menu bar app, click the fan icon, paste the **API key** and **refresh token** into the two
   boxes, and press **Save**.

**Good to know:**

- **Scope:** credentials only control the fans on the account that generated them. They do not give
  access to anyone else's devices.
- **Revoking / rotating:** disabling developer mode or regenerating the credentials in Developer
  Options immediately **revokes the old pair**. If you ever leak them, regenerate to cut off access,
  then re-enter the new pair in the app (use **Remove credentials** first, then Save the new ones).
- **Quota:** the API allows **100 calls/day** and **5 calls/second** per account, shared across every
  tool using it. See [API quota and how it is managed](#api-quota-and-how-it-is-managed).
- **One account, many tools:** if you also use Home Assistant, the CLI, or other integrations on the
  same account, their calls count against the same daily quota.

> Exact menu labels and the location of Developer Options can change between app versions. If the
> wording differs, look under **Profile / Account → Developer** for an option that reveals an API key
> and a refresh token.

## How it works

```
 Menu bar app
      │  HTTPS (x-api-key + Bearer token)
      ▼
 api.developer.atomberg-iot.com/v2  ──►  Atomberg cloud  ──►  your fans (Wi-Fi)
```

| Endpoint | Purpose | Quota cost |
|---|---|---|
| `GET /get_access_token` (Bearer **refresh** token) | Issues a 24-hour access token | 1 — cached and reused |
| `GET /get_list_of_devices` | Fan names, IDs, series | 1 — refreshed daily |
| `GET /get_device_state?device_id=all` | Power, speed, light, online status of **all** fans | 1 for all fans |
| `POST /send_command` `{"device_id": "...", "command": {...}}` | Power / speed / light | 1 |

A `200` from `send_command` means the command was **accepted**, not applied, so every command is
shown optimistically and confirmed with one state read ~8 seconds later. Only fans are handled
(series starting with `R`, `K`, `I`, `M`, `S`); purifiers and locks on the same account are ignored.
The light is on/off only — the public API does not expose brightness/dimming.

## Requirements

- macOS 14 Sonoma or later
- Atomberg smart fan(s) set up in the **Atomberg Home** app and online
- To build from source: Apple's Command Line Tools (`xcode-select --install`). No full Xcode or
  Apple ID is needed for the menu bar app.

## Build it yourself

```bash
cd AtombergFans
./build-menubar.sh                           # → build/FanDeck for Atomberg.app
open "build/FanDeck for Atomberg.app"
```

Optional: set your own bundle identifier prefix with `BUNDLE_ID_PREFIX=io.github.<you> ./build-menubar.sh`.

Install permanently:

```bash
osascript -e 'quit app "FanDeck for Atomberg"' 2>/dev/null
cp -R "build/FanDeck for Atomberg.app" ~/Applications/
open ~/Applications/"FanDeck for Atomberg.app"
```

Then tick **Launch at login** in the menu, or add it under *System Settings → General → Login Items*.

## Using it

- First launch: if no credentials are stored, the menu shows two boxes — paste your **API key** and
  **refresh token** and press **Save** (no Terminal needed). Use **Remove credentials** to clear them.
- Menu bar icon: filled fan when any online fan is running.
- Each fan: on/off switch, 1–6 speed slider (sends one command on release, not while dragging),
  status line (`On · Speed 4`, `Off`, `Offline`, `Turning on…`).
- Fans with a light show a **Light** on/off toggle (on/off only — no brightness/dimming).
- Offline fans are dimmed and disabled.
- ↻ forces a refresh (1 call). Footer shows last update time and calls used today.

### Storing credentials from the command line (optional)

The app can store the credentials for you, so this is optional. If you prefer, add them yourself
(values are prompted for, so they never appear in shell history):

```bash
security add-generic-password -U -s atomberg -a api_key -w
security add-generic-password -U -s atomberg -a refresh_token -w
```

## API quota and how it is managed

Atomberg's default limits: **100 calls/day** and **5 calls/second** per account. The app is designed
around that budget:

| Mechanism | Detail |
|---|---|
| Token reuse | One `get_access_token` per ~24 h (renewed 1 h before expiry, or on a 401) |
| Batched reads | `device_id=all` reads every fan for one call |
| Hourly background refresh | The app wakes every 5 min but only fetches when the cache is ≥ 1 h old |
| Daily device list | Fan names/IDs fetched once a day |
| Command reserve | Background polling stops at 85 calls so 15 remain for your commands |
| One-shot commands | Toggle/speed/light = 1 call + 1 confirmation read; the slider sends only on release |
| Back-off | On HTTP 429 the app stops polling for an hour |

The "calls today" counter resets at local midnight; calls from other tools on the same account also
count against the quota.

## Security

- The API key and refresh token are never written to disk in plain text or logged. They are read
  from the **login Keychain** via `/usr/bin/security`.
- Access tokens (24 h) are cached in a 0600 file.
- All traffic is HTTPS to `api.developer.atomberg-iot.com`; `URLSession` uses an ephemeral
  configuration (no disk cache or cookies).
- If your credentials leak, regenerate them in *Developer Options* — that revokes the old pair.

> **Atomberg's own guidance:** please ensure your developer credentials are stored securely. If you
> suspect they have been leaked, disable **Developer Mode** immediately from the Atomberg Home app.

## Project layout

```
.
├── README.md
├── LICENSE
├── .github/workflows/release.yml   # CI: builds & attaches the app to Releases
└── AtombergFans/
    ├── build-menubar.sh            # builds the menu bar app with swiftc
    ├── Shared/
    │   ├── Models.swift            # Fan, FanState, AppConfig (quota & timing constants)
    │   ├── AtombergAPI.swift       # API client (actor), token caching, 401 retry
    │   └── FanStore.swift          # cache, refresh policy, quota counter, optimistic updates
    └── MenuBar/
        ├── AtombergMenuBarApp.swift            # menu bar UI + credential entry
        └── LoginKeychainCredentialStore.swift  # login Keychain read/write via `security`
```

Tunable constants (refresh interval, command reserve, confirmation delay) live in
`Shared/Models.swift` → `AppConfig`.

## Troubleshooting

| Symptom | Fix |
|---|---|
| "Add your API key and refresh token…" | Enter both in the menu and press Save |
| `401` errors | Credentials were regenerated or developer mode was disabled — enter the new pair |
| "API quota reached" | Wait — polling pauses for an hour; check other tools using the same account |
| Fan shows **Offline** | The cloud lost contact: check the fan's mains power and Wi-Fi in the Atomberg app |
| Switch flips back after a few seconds | The confirmation read saw the old state; the fan may be offline or slow to report — press ↻ |
| App won't open ("unidentified developer") | Right-click the app → Open → Open, or allow it in *System Settings → Privacy & Security* |

## Support

For issues with **this macOS app**, please open an issue on the project's GitHub repository.

For questions about the **Atomberg developer API or your credentials** (which are provided by
Atomberg, not by this project), contact Atomberg at **app@atomberg.com**.

Please ensure your developer credentials are stored securely. If you suspect they have been leaked,
disable **Developer Mode** immediately from the Atomberg Home app — this revokes the credentials.

## License

[MIT](LICENSE) · © 2026 Vineethkumar Marpadge
