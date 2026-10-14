# pr — ADMINJAIL

An admin jail that is served in **work**, not minutes. Staff hand out a number of
community-service jobs (sweep the yard, mop, collect trash, blow leaves, pull weeds, scrub
graffiti, fix the fence) and the inmate walks out only when the last one is done. Give someone
300 and they do 300.

**Version 1.0.0**

---

## What it does

- **Served in jobs.** Each job is done at a spot the server picked, takes as long as the server
  says, and has ox_lib skill checks along the way. Fail a check and that job doesn't count.
  Some jobs have two steps: pick up the trash bag, then carry it to the dumpster.
- **You can't get out of it.** The server checks everything:
  - **Leash.** Walk out of the yard and you get dragged back, with **+5 tasks** (configurable).
  - **Bucket.** If any script moves you to another routing bucket, you get put back, with a penalty.
  - **Vehicles.** You get pulled out, with a penalty. Yard buckets are entity-locked, so menus
    can't spawn cars there anyway.
  - **Disconnecting.** The sentence is saved in the database and starts again the moment you
    load back in, on any character.
  - **New account.** A sentence matches on licence, Discord, Steam *or* FiveM id, so changing
    one of them isn't enough.
  - **Teleporting to the job.** If you reach a spot faster than anyone could run there, the
    attempt is refused, logged, and you get a different job.
  - **Faking the event.** Every job has a random token. A job finished faster than its
    duration, or one that was never started, doesn't count and gets logged.
  - **Staff.** Staff can't release or reduce their own sentence, can't touch an owner, and a
    jailed staff member loses the panel.
- **Pick the bucket.** For each sentence you choose where it's served:
  | mode | |
  |---|---|
  | **Yard** | the yard's shared bucket, with all its other inmates |
  | **Solitary** | a private bucket for this inmate only |
  | **Public** | bucket 0, the main world, so everyone can watch them mop |
  | **Custom** | any bucket number you type in |
- **An owner panel**, `/jailpanel`:
  - **Sentence:** jail an online player, someone who just disconnected, or an offline player
    by Discord / licence / Steam / FiveM id.
  - **Inmates:** live progress for everyone serving, with buttons to add, remove or set tasks,
    move yard or bucket, or release.
  - **History:** every sentence, with identifiers and its full event log.
  - **Activity:** a live feed of what's happening.
  - **Staff** (owners only): choose **who** can open the jail and **what** each of them can do,
    plus an optional per-staff cap on how many tasks they can give.
- **Server-side Discord logs.** Webhooks live in a server-only file and never reach a client.
  Every log has the player's name, character, server ID, a Discord mention + ID, a Steam profile
  link, licence and FiveM ID. Add a bot token if you also want real Discord usernames and avatars.
- **HUD and cinematics.** A tasks-left counter, a progress bar, your current job with distance,
  and a red warning when you get near the fence. You get a full-screen **SENTENCED** card when
  jailed and a **SERVED** card when you finish.
- **English and Hebrew** (`setr ox:locale he`).

---

## Requirements

| | |
|---|---|
| OneSync | required, because positions and buckets are checked on the server |
| `ox_lib` | 3.x |
| `oxmysql` | 2.x |

The framework is detected automatically: `qbx_core`, `qb-core`, ESX or standalone. It's only
used to tell when a character is loaded (so nobody gets pulled out of character selection)
and to show the character name in logs.

---

## Install

1. Copy the folder to `resources/[custom]/pr-adminjail`.
2. Database: the tables are created on first start. `sql/install.sql` has the same DDL if you'd
   rather run it yourself.
3. Open `configs/s.secrets.lua` and add:
   - your Discord ID under `Config.Owners`
   - your webhooks under `Config.Webhooks` (one per channel, or just `default`)
   - optionally `Config.DiscordBotToken` for usernames and avatars in logs
4. In `server.cfg`, after ox_lib, oxmysql and your framework:
   ```cfg
   ensure pr-adminjail
   ```
5. In game, run `/jailpanel`, open the **Staff** tab, and give your team access.

---

## Commands

| command | who | |
|---|---|---|
| `/jailpanel` | owners + staff | open the panel |
| `/ajail <id> <tasks> <reason>` | `jail` permission | quick jail into the default yard |
| `/aunjail <id> <reason>` | `release` permission | cancel a sentence |
| `/tasksleft` | inmates | how many jobs are left |
| `/ajspot` | owners | copy your position as a ready-to-paste task spot |

Command names can be changed in `Config.Commands`.

## Permissions

Owners have every permission. You give staff any mix of these:

| key | |
|---|---|
| `jail` | sentence online players |
| `offline` | sentence by identifier or from the recently-disconnected list |
| `modify` | add / remove / set tasks, move yard or bucket |
| `release` | cancel a sentence early (also needed to lower one to 0) |
| `history` | history, activity feed, identifiers |

Each staff member can also have a **max tasks** cap.

---

## Configuration

- **`configs/sh.config.lua`**: yards, jobs, buckets, anti-escape tuning, HUD and log categories.
  Every option is documented inline.
- **`configs/s.secrets.lua`**: owners, webhooks, bot token. Server-only.
- **`configs/s.hooks.lua`**: how to revive an inmate with your medical script, plus
  `OnJailed` / `OnReleased` hooks (for example, to disable a phone).

### Adding a yard

Stand at each place you want a job and run `/ajspot`. It copies a line like
`{ coords = vec3(…) },` to your clipboard. Then add a block under `Config.Yards` with a
`spawn`, a `leash` (center + radius), the `spots`, and some `dropoffs` for the trash job. At
boot the resource warns you about any spawn, spot or dropoff that's outside its own leash.

### Adding a job

Add an entry under `Config.Jobs`. Each stage takes a `scenario` (GTA brings its own props and
other players see it) or an `anim` with an optional local `prop`. It also needs a `durationMs`,
which the server enforces, and optional `skill` checks.

---

## Exports

```lua
-- server
exports['pr-adminjail']:IsJailed(source)     -- boolean
exports['pr-adminjail']:GetSentence(source)  -- { id, total, done, left, reason, yard, bucket, ... } | nil

-- client
exports['pr-adminjail']:IsJailed()
```

---

## Performance

- **Players who aren't jailed: 0.00 ms.** The client doesn't run any loops for them.
- **Inmates:** one 1-second check, the per-frame control lock, and the marker loop, which only
  runs within 25 m of the current job.
- **Server:** a single watchdog that only goes over inmates (every 1.5 s), and a join check that
  looks at each player once. Identifiers are cached per player, and logs are queued and batched
  per webhook so Discord's rate limit is respected.

---

## Layout

```
pr-adminjail/
├─ fxmanifest.lua
├─ configs/          sh.config.lua · s.secrets.lua · s.hooks.lua
├─ escrowed/
│  ├─ sh.const.lua
│  ├─ client/        c.util · c.tasks · c.main · c.panel
│  └─ server/        s.util · s.lib.{framework,identity,log,db,access,jail,tasks} · s.panel · s.main
├─ locales/          en.json · he.json
├─ sql/              install.sql
└─ ui/               src/ + dist/ (Vite + React)
```

Rebuild the interface with `cd ui && npm install && npm run build`. Running `npm run dev`
outside FiveM opens a preview with sample data (`?show=panel`, `?show=hud`, `?show=cine`).

---

© pr
