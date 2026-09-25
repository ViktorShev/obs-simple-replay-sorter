# Simple Replay Sorter (SRS)

SRS automatically moves your OBS replay buffer clips into per-game subfolders, using the app that had focus when the clip was saved to decide the folder name. **Windows only.**

## Installation

1. [Download](https://github.com/ViktorShev/obs-simple-replay-sorter/releases) `obs-simple-replay-sorter.zip` from the releases tab.
2. Extract the contents of the archive to your desired folder.
3. In OBS, go to **Tools → Scripts**.
4. Click the **+** button and select `srs.lua`.

No extra dependencies to install — everything the script needs is built into OBS or already present on Windows.

# Search & Replace List

Simple Replay Sorter (SRS) names each sorted folder after whatever application had focus when the replay was saved. By default this is the raw executable name, title-cased — for example, `ApexLegends` will become `Apex Legends`. But sometimes certain games can have "ugly" executable names, for example, `valorant-shipping64_final.exe` would become `Valorant Shipping64 Final`. That's rarely the name you actually want on a folder.

The **Search & Replace List** lets you clean this up: define your own rules to turn messy or unrecognizable executable names into the folder names you actually want.

## Where to configure it

In OBS, go to **Tools → Scripts**, select Simple Replay Sorter (`srs.lua`), and find the **Search & Replace List** field. It's a multiline text box — one rule per line.

## Format

Each line follows one of two forms:

```
<search text> = <replacement>
<search text>
```

### `search = replacement`

```
valorant = VALORANT
deadlock = DL
cs2 = Counter-Strike 2
```

If the detected executable name **contains** the text on the left (case-insensitive), the folder is named exactly what's on the right — used verbatim, with whatever casing/spacing you wrote.

Example: the raw detected name `valorant-shipping64_final` contains `valorant`, so the clip is sorted into a folder named `VALORANT`.

### `search` only (no `=`)

```
deadlock
```

If a line has no `=` at all, the search text and the replacement are the same — the line above is shorthand for `deadlock = deadlock`. Useful when the executable name includes/is the "friendly" game name and you just want to use your own casing (e.g. DeadLock) instead of relying on the default title-case.

### A trailing `=` with nothing after it

```
deadlock =
```

This is technically a misconfigured search & replacement, but it's handled gracefully anyway. If you write `=` and leave the right-hand side blank, it's treated the same as if you'd omitted the `=` entirely — the search text is used as its own replacement.

## Matching rules

- **Case-insensitive.** `VALORANT`, `Valorant`, and `valorant` in your **search term** (left side of the `=`) all match the same way against the detected name.
- **Substring match, not exact match.** Your search text just needs to appear *somewhere* in the detected executable name — it doesn't need to match the whole thing. This is what allows `valorant` to match a messy real-world name like `valorant-shipping64_final`.
- **Not a pattern/regex.** Your search text is matched literally, character for character. A search text like `S.T.A.L.K.E.R.` matches that exact text, including the periods — it won't accidentally match unrelated text the way a regex `.` (any character) would.
- **First match wins.** Rules are checked in the order you wrote them, top to bottom, and the first line whose search text matches is used. If you have overlapping rules (e.g. both `counter` and `counter-strike 2`), put the more specific one first if you want it to take priority.

## Precedence

Folder naming is decided in this order:

1. **Known system windows** (Desktop, Explorer, etc.) — always mapped to a fixed built-in label, regardless of your search & replace list.

   > You can expand / change these system overrides by editing the `SYSTEM_PROCESS_NAMES_OVERRIDE` map inside the script (`srs.lua`).
3. **Your Search & Replace List**, checked top to bottom, first match wins.
4. **Automatic fallback** — if nothing in your list matches, the raw executable name is used, title-cased automatically (e.g. `quake_3_arena` → `Quake 3 Arena`).

## Example list

```
VALORANT
deadlock = DL
cs2 = Counter-Strike 2
r5apex = Apex Legends
Ppssppwindows64 = PPSSPP
Quake3 = Quake 3
Diablo IV
```

With this list, a detected executable like `r5apex_dx12.exe` sorts into a folder named `Apex Legends`, while an unrecognized game not in the list falls back to its automatically title-cased executable name.

---
## Fun fact!

This Search & Replace list is essentially a lightweight version of what NVIDIA's ShadowPlay and AMD's ReLive does under the hood — it also relies on an internally maintained database mapping known game executables to friendly display names.

The difference is that NVIDIA maintains that database centrally, across every supported title, as a company. I'm one developer without the resources to track and maintain exe-name mappings for every game that exists — so instead of trying to ship (and you having to constantly update) a giant built-in database, I just give you the mechanism to extend the list yourself for whatever you personally play.
