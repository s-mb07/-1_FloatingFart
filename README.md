# README — architecture & dev rules

This is the single source of truth for this kit. It replaces a scattered doc
set on purpose: one file, loaded at the start of every session, long enough
to actually answer questions instead of pointing elsewhere.

`code/` (this folder) mirrors a real Rojo project root. Copy `default.project.json`,
`rokit.toml`, `selene.toml`, `wally.toml` and `src/` straight into a new
repo and it builds. Everything under `src/` is either **CORE** (copy verbatim,
zero game coupling — Signal, Logger, Scheduler, PadTrigger, Navigation,
SafeUIResolver...) or **ADAPTABLE** (keep the engine, gut the example data —
NetworkEvents' event table, DataTemplate's fields, PanelTagsConfig's panels).
A handful of files are **GAME-SPECIFIC EXAMPLES** meant to be replaced outright
(Panels/Settings, the two example UITag actions) — they exist to show the
*shape* a real one takes, not to survive into your game unchanged.
`Panels/_Template/` is a fourth category, a **SCAFFOLD** — copy the folder to
start a new Fusion-built panel, it's not registered in `Panels/init.lua` and
was never meant to run as-is.

## 1. Toolchain

- Rokit (`rokit.toml`) manages `selene`, `stylua`, `lune`. Add `rojo-rbx/rojo` too
  (`rokit add rojo`).
- Lint: `selene src`. Format check: `stylua --check src` (drop `--check` to apply).
- Convention check: `lune run scripts/lint-conventions` — mechanically enforces §9.1
  (`--!strict` on every file) and §9.3 (pcall budget); see that section for the
  `--!derogation:` escape hatch. Vendored files are skipped (see the script's own
  `VENDORED_PATHS`/`Packages/**` exclusion).
- Pre-commit hook: `scripts/hooks/pre-commit` runs stylua + selene + the convention
  check. Install once with `cp scripts/hooks/pre-commit .git/hooks/pre-commit && chmod
  +x .git/hooks/pre-commit`.
- CI (`.github/workflows/ci.yml`): the same four checks, plus a `luau-lsp analyze`
  type pass, on every push/PR to `main`.
- Sourcemap (for Luau LSP): `rojo sourcemap default.project.json -o sourcemap.json`
- Editor: `.vscode/settings.json` points the Luau LSP extension at the sourcemap +
  `globalTypes.d.luau`. That defs file isn't committed (fetched fresh in CI) — grab it
  once locally too: `curl -sL https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/main/scripts/globalTypes.d.luau -o globalTypes.d.luau`.
- Sync into Studio: `rojo serve default.project.json`, connect via the Rojo Studio plugin
- Tests: `lune run scripts/test-utils` — hand-rolled, covers the pure functions in
  `Libraries/Utils/` (no TestEZ/Studio dependency). Everything else is manual in
  Studio (Play mode) + selene/Luau LSP — there's no in-Studio test runner in this kit.
- UI: **Fusion** (see §7). Already a real dependency in `wally.toml` — `wally install`
  after cloning.

## 2. Project tree & the client/server boundary

```
src/
├── ReplicatedFirst/          -- runs before anything else, client-side
│   ├── LoadingManager.lua    -- weighted/phased asset preload
│   └── AssetManifest.lua     -- raw asset IDs referenced dynamically (no Studio instance)
├── ReplicatedStorage/
│   ├── Libraries/            -- AGNOSTIC ONLY: zero Instance/GuiObject dependency,
│   │   │                        genuinely callable from both sides (Signal, Logger,
│   │   │                        NumberUtil, Debounce, Scheduler, PadTrigger, NetworkEvents)
│   │   ├── Utils/             -- barrel of small pure helpers (Array/Dict/Table/String/
│   │   │                        Math/Vector/Color/Format/Guard/Random/RateLimiter/
│   │   │                        Spawn/Throttle/Instance/Time) -- see Utils/init.lua
│   │   └── Middleware/        -- composable payload validation for remote handlers
│   │                             (NetworkEvents already rate-limits, no RateLimit gate here)
│   └── Config/                -- config actually READ from both sides (GlobalConfig)
│       └── AssetIds/          -- empty typed asset id registries, fill in as you upload assets
├── ServerScriptService/
│   ├── Packages/ProfileStore.lua  -- vendored, server-only persistence lib
│   └── Bootstrapper/
│       ├── init.server.lua   -- scans Services/, calls Init() then Start()
│       ├── GameEvents.lua    -- server-internal signal bus (never replicated)
│       ├── Config/            -- server-only config (DataTemplate, AdminConfig)
│       └── Services/          -- one ModuleScript = one service (§8 lists all 8 examples)
└── StarterPlayerScripts/
    └── Bootstrapper/
        ├── init.client.lua   -- scans StandaloneControllers/, requires Panels/
        ├── Libraries/         -- CLIENT-ONLY libraries (UXEffects, SafeUIResolver+UITag, UIListKit, ResponsiveScale)
        ├── Config/             -- client-only config (UI theme/animation/panel tags, KeybindsConfig, PadConfig)
        ├── Events/             -- EventBus (client signal bus) + PlayerDataFetcher
        ├── Navigation/         -- panel stack/transitions
        ├── Effects/            -- multi-channel player feedback (camera/sound/haptic/visual/world)
        ├── Panels/             -- one folder per UI panel
        └── StandaloneControllers/  -- everything else, Init/Start-scanned
```

**The rule that drives all of the above:** a piece of code lives in
`ReplicatedStorage` **only if both the client and the server genuinely
require it**. Everything else moves to whichever side actually uses it —
UI/VFX/input code goes under `StarterPlayerScripts/Bootstrapper`, persistence/
anti-cheat/moderation code goes under `ServerScriptService/Bootstrapper`.
`ReplicatedStorage/Types` does not exist as a folder: a type lives **in the
config file whose shape it describes** (`DataTemplate.lua` exports
`PlayerProfile` right next to the values that satisfy it — one file, values
and shape edited together, no risk of the two drifting apart). The client
can't `require` anything under `ServerScriptService` anyway (hard engine
limit, not a convention) — a client handler for `"DataInitialized"` types its
payload as `any` and narrows locally rather than importing a server type.

When you add a new file, ask "does the OTHER side need this too?" before
defaulting it into `ReplicatedStorage`. If the honest answer is "maybe
later", it starts on the side that needs it now and gets promoted to
`ReplicatedStorage` the day a second consumer on the other side shows up —
promoting later is a one-line move, defaulting to shared and never
revisiting it is how a project ends up with a `ReplicatedStorage` nobody
can reason about.

## 3. Bootstrap pattern (both sides)

Server (`init.server.lua`) and client (`init.client.lua`) both do the same
thing: scan a folder (`Services/` / `StandaloneControllers/`), `require`
every direct `ModuleScript` child, call `:Init()` synchronously inside a
`pcall`, then `:Start()` via `task.spawn` inside a `pcall`. A module is a
service/controller by virtue of sitting in that folder — nothing else is
wired automatically. Failures are caught, logged, never crash the bootstrap.

**Panels are not scanned this way.** `Panels/init.lua` is `require`d once,
explicitly, and does its own registration into `Navigation.PanelRegistry`
(side-effect require, not Init/Start). See §6.

A dormant experimental path (`ENABLE_EXPERIMENTAL_DEPENDENCIES` in
`init.client.lua`) topologically sorts controllers by an optional
`Dependencies: {string}` field on a controller — leave it `false` unless you
have a genuine ordering need between two specific controllers. Don't reach
for it by default; `pairs()` order (undefined but stable enough in practice)
is fine for anything that doesn't have a real dependency.

**`LoadingController.RunPreload(...)` is the one deliberate exception.** It's
still a normal `Init`/`Start` `StandaloneController` (so other code can find
it the same way), but its actual preload work is a public method you call
explicitly and early — a loading screen needs to run *before* the rest of
the boot sequence, and the scan above gives no ordering guarantee. Call it
from the top of `init.client.lua`, or later, before a teleport into a scene
with its own assets to warm up.
`init.client.lua` already calls it once at the end of boot (spawned, not
awaited, so a slow preload never holds a controller back); it preloads the
Studio-scanned containers, `AssetManifest.Entries` and every `AnimationIds`
entry.

## 4. Networking — two buses, never confuse them

- **`ReplicatedStorage/Libraries/NetworkEvents.lua`** — the only place a
  `RemoteEvent`/`RemoteFunction` is created. Server creates them from
  `EVENT_DEFINITIONS`, client fetches by name. Built-in per-event rate
  limiting (`RATE_LIMITS`). **Never instantiate a Remote directly** in a
  service or controller. On the client, `NetworkBridgeController` is the
  *only* controller allowed to call `NetworkEvents.OnClientEvent` directly —
  everyone else listens via `EventBus` instead.
- **`ServerScriptService/Bootstrapper/GameEvents.lua`** — server-internal
  signal bus (built on `Signal.lua`), never replicated, interconnects
  Services only (`OnDataLoaded`, `OnCurrencyEarned`, `OnCurrencySpent`, ...).
- **`StarterPlayerScripts/Bootstrapper/Events/EventBus.lua`** — the client
  mirror of GameEvents: interconnects Controllers/Panels without them
  `require`-ing each other directly, isolates the network layer inside
  `NetworkBridgeController`.

A new event goes in `NetworkEvents` only if it actually crosses the
client/server boundary; otherwise it's a `GameEvents` or `EventBus` signal.
All value-affecting logic is server-side; the client never computes anything
that matters and **every remote must be re-validated server-side** — the
client can lie about anything it sends, including the contents of a UI
button click. `AntiCheatService` (movement sanity) is a second, independent
layer — it does not replace per-remote validation in the owning service.

## 5. Data & persistence

`ServerScriptService/Bootstrapper/Config/DataTemplate.lua` is the single
source of truth for player data: it exports both the **types**
(`PlayerProfile` and friends) and the **default values** ProfileStore uses
to initialize a new profile. `Services/DataService.lua` is a facade —
every mutation of `profile.Data` goes through a typed public method here,
which writes synchronously then calls `markDirty(player, key)`; a
`task.defer`-coalesced flush emits one `"DataUpdated"` per player per frame
with the *complete* snapshot of each dirty key (never a partial diff). Direct
`FireClient("DataUpdated", ...)` calls anywhere else are not allowed.

Don't let `DataService` grow into a god-service (see its own file header):
once a data domain (inventory, progression, whatever you add) has enough
logic to justify its own file, give it a dedicated service that reads/writes
through `DataService`'s mutators rather than piling more methods on top.

## 6. UI: Navigation, Panels, Fusion

`PanelDefinition.lua` is the contract every panel implements:
`Init(deps)` / `Activate()` / `Deactivate()` / `Destroy()`, plus optional
`CaptureState()`/`RestoreState(snapshot)` for a panel whose runtime state
(search text, active tab...) is worth preserving across a pop/push. A
server-truth panel (reads from `EventBus.Data`, no local-only state) usually
skips Capture/Restore — a re-fetch on `Activate()` is simpler and can't go
stale.

`Navigation/Controller.lua` owns the stack: `Push`/`PushChild`/`Pop`/`CloseAll`,
`KeepAlive` panels are only `Deactivate()`d, non-KeepAlive ones are destroyed
and rebuilt. `Panels/init.lua` wires each panel's HUD button (if any) to
`Push`/`Pop` and registers panels that open by other means (pad proximity,
a server event) via `NavigationController.Prewarm`, which forces `Init()` to
run without activating — otherwise a panel whose only trigger lives inside
its own `Init()` would never run that `Init()` in the first place.

**UI is built with [Fusion](https://github.com/dphfox/Fusion)** (a real
`wally.toml` dependency, not just a note — `wally install` pulls it into
`ReplicatedStorage/Packages`). A Panel's `Root` is the Fusion-mounted tree;
`Init(deps)` is where you `Fusion.scoped(Fusion)` it and hand the built
instance to `self.Root`, `Destroy()` calls `scope:doCleanup()`. `Panels/_Template/`
is a working, copy-this example of the whole thing (`scope:New`, `[Children]`,
`[OnEvent]`, a `Value`/`Computed` pair) — read it before writing your first
real Fusion panel. The Navigation/PanelDefinition contract above doesn't
change — Fusion only changes *how* a panel builds and updates `Root`'s
descendants, not the lifecycle Navigation drives it through. `UXEffects`
(tweens, particles, panel transitions) and `UITag` (tag-driven click/hover
wiring) stay useful under Fusion for anything that isn't naturally
reactive state (one-shot bursts, camera shake, sound) — don't reach for a
Fusion `Spring`/`Tween` where a `UXEffects` call already does the job in one
line.

`SafeUIResolver` (`Libraries/SafeUIResolver/init.lua`) resolves a Studio-authored
path event-driven with a timeout-warn instead of a hard `WaitForChild` hang —
`UITag` (nested under it, same folder) is the sibling tag-driven framework:
both solve "get a hold of a UI Instance safely", one by exact path, the
other by `CollectionService` tag. `UIListKit` (`CellCache`/`Diff`) is for a
list/grid UI that reuses cells instead of destroying/recreating them.

## 7. World interaction: PadTrigger + Scheduler

Every "player is near this pad" check goes through
`ReplicatedStorage/Libraries/PadTrigger.lua` (client **and** server) —
never hand-write a `.Touched`/`.TouchEnded` pad. It runs off ONE shared
`Scheduler.lua` task (10 Hz), tracks an enter/exit state machine per
(pad, player), measures distance to the pad's SURFACE with hysteresis, and
re-reads `player.Character` every tick (respawn-safe by construction).
"Pad opens a Navigation panel" needs zero code — one entry in
`Config/PadConfig.lua`, `StandaloneControllers/PadController.lua` wires it.
A pad with real logic (reward, shop, minigame) keeps its own service/
controller and calls `PadTrigger.Bind` directly.

`Scheduler.lua` is the general answer to "this needs to tick every N
seconds": one Heartbeat connection for the whole project, phase-offset by a
golden-ratio sequence so same-frequency tasks never spike on the same frame.
`Scheduler.Report()` (Studio console) shows real per-task cost — use it
before guessing which task is expensive. Mark a task `cosmetic = true` if
(and only if) lowering graphics quality is allowed to slow it down;
gameplay-critical tasks (proximity, anything with a cooldown) never take
that flag, so `QualityController`/`GraphicsQualityConfig`'s
`CosmeticRateScale` never makes the game less responsive, only less shiny.

## 8. Server-side platform services

`ServerScriptService/Bootstrapper/Services/` includes nine example
services worth knowing about before you extend them:

- **`AntiCheatService.lua`** — server-only movement sanity check (implicit
  speed from position delta over time), independent of and *not* a
  replacement for per-remote validation in the service that owns each
  remote. Call `AntiCheatService.ResetTracking(player)` after any legitimate
  server-side teleport, or it reads as a speed violation.
- **`PlayerCollisionService.lua`** — anti-fling at the root: every character
  part (Fly model included) is in the `Players` collision group
  (`FlyConfig.PlayerCollisionGroup`), which collides with the world but not
  with itself. `CharacterLock` restores it after a flight through `Apply`.
  `AntiCheatService` also caps linear/angular velocity outside the flight.
- **`ModerationService.lua`** — `FilterForBroadcast` is the ONLY sanctioned
  way to turn one player's text into text shown to another player (chat,
  a custom display name, anything player-authored). Ban list here is an
  in-memory example — persist it in its own DataStore in a real game, never
  inside a player's own ProfileStore (a ban must apply before that player's
  profile session even opens).
- **`AnalyticsService.lua`** — thin wrapper over the *engine's*
  `AnalyticsService` (name collision is unfortunate but intentional, it's
  the platform's own name). Server-only by engine restriction; the client's
  `AnalyticsController` only reports a candidate event over `NetworkEvents`
  (`"AnalyticsEvent"`), which this service whitelists before actually
  logging — never trust an event name that came from the client.
- **`PlayerService.lua`** — the single `Players.PlayerAdded`/`PlayerRemoving`
  listener. Other services query `GetRegisteredPlayers()`/`IsRegistered()` or
  react to `GameEvents.OnPlayerRegistered`/`OnPlayerUnregistered` instead of
  each hooking the engine event independently.
- **`LeaderstatsService.lua`** — owns the `leaderstats` Folder Studio's
  default leaderboard reads from. `SetStat(player, name, value)` is the only
  sanctioned writer; leaderstats are a **display** of data, not the source of
  truth — the real value still lives in `DataService`/ProfileStore.
- **`TeleportService.lua`** — thin wrapper over the engine's
  `TeleportService`. `placeId` must always come from trusted server logic; a
  client asking to leave should send an intent, not a place id.
- **`InactivityService.lua`** — anti-kick. Roblox kicks ~20min idle; one
  `task.delay(InactivityConfig.IdleTimeout)` per player (no polling) teleports
  them to another server of the same place first. The client
  `InactivityController` sends a zero-payload `"PlayerActivityPing"` on any
  input (throttled `PingThrottle`), each ping re-arms the timer; the remote
  is rate-limited server-side (55s < 60s). Teleport fails in Studio and for
  private servers → falls back to `Kick`. Tune in `Config/InactivityConfig.lua`.
- **`CommandService.lua`** — admin/dev command registry.
  `RegisterCommand(name, handler)` from any service's `Init()`; `Execute`
  re-checks `AdminConfig.Admins` itself on every call — never assume a caller
  already authorized the player.
- **`MonetizationService.lua`** — gamepass ownership (`OwnsGamepass`, always
  re-verified against Roblox, never trusts the client) and developer product
  purchases. `RegisterProductHandler(productId, handler)` wires the engine's
  `ProcessReceipt` callback to your own grant logic; a handler **must be
  idempotent** — Roblox can call `ProcessReceipt` again for the same
  `PurchaseId` if its backend didn't durably record your prior
  `PurchaseGranted` decision.
- **`NotificationService.lua`** — server-driven push notifications
  (`Send(player, ...)`/`Broadcast(...)`), as opposed to a client triggering
  its own `Effects`/`UXEffects.Toast` locally for something it already knows
  happened (a button press). Fires `NetworkEvents "Notify"`;
  `NetworkBridgeController` bridges it to `EventBus.Notification.Received`,
  which `NotificationController` (client) renders via `UXEffects.Toast` — the
  client only ever displays what the server tells it to.

## 9. Dev rules

### 9.1 Strictness & typing
- `--!strict` is the **first line** of every `.lua`/`.luau` file. No exceptions.
- Everything is typed: tables, function arguments, parameters, return values,
  and any variable whose type isn't trivially inferred. No implicit `any` —
  an explicit `data: any` at a real boundary (an untyped network payload) is
  fine, an `any` used to dodge writing a type is not.
- Public types are `export type` from the module that owns the VALUES that
  shape describes (see §2 — no separate `Types/` folder). Reference them via
  `require(...).TypeName` in a `type` position from any consumer.

### 9.2 Comments & prints
- English only, everywhere — comments, prints, warnings, identifiers. (This
  kit's own extracted files still carry French comments inherited from the
  project they were pulled from; treat that as a backlog to translate as you
  touch each file, not a precedent to keep writing new French comments.)
- Public API members carry doc comments: `--- summary`, `--- @param name T -- desc`,
  `--- @return T -- desc`. A module/class opens with an `@module`/`@class`
  block explaining what it's for and, if non-obvious, why it exists.
- Prefer `Logger.new(moduleName)` (`:Info`/`:Warn`/`:Error`/`:Debug`) over
  raw `print`/`warn` in shipped logic — `Logger:Debug` is silent unless
  `Logger.SetDebugMode(moduleName | "Global", true)`, so it's safe to leave
  verbose diagnostics in place permanently instead of deleting-then-
  re-adding them on the next bug hunt.

### 9.3 pcall budget
- Max 2–3 `pcall` per file. Needing more is a signal the file is doing too
  much error-prone work in one place — split it, or the boundary you're
  guarding against isn't actually where you think it is.
- The bootstrappers (`init.server.lua`, `init.client.lua`) and `UITag/init.lua`
  (isolates one tagged-instance handler at a time so a bad handler can't
  break dispatch for every other tagged instance) are the sanctioned
  exceptions: failure isolation between independent units of work is their
  entire job, one `pcall` per unit by design, not a violation to fix. Mark a
  genuine exception with `--!derogation: pcall <reason>` on its own line near
  the top of the file — that's what exempts it from the check below.
- Mechanically enforced: `lune run scripts/lint-conventions` (also in
  `scripts/hooks/pre-commit` and CI) fails the build on any file over budget
  without a `--!derogation:` comment, or missing its `--!strict` header (§9.1).
  Vendored third-party files (`Signal.lua`, anything under `Packages/`) are
  skipped — they aren't ours to retype or refactor down.

### 9.4 DRY
- Anything repeated across two or more files moves to the appropriate
  `Libraries/` (agnostic → `ReplicatedStorage/Libraries`, client-only →
  `StarterPlayerScripts/Bootstrapper/Libraries`, server-only → a module
  under `ServerScriptService/Bootstrapper`). Copy-pasted logic is a defect,
  not a shortcut — this kit exists because six copies of a pad-proximity
  check each diverged with their own bugs (see `PadTrigger.lua`'s own
  header for the full story).

### 9.5 Unique responsibility (no god-files)
- One module = one domain. A module handling more than ~3 distinct logics
  for the same domain has violated this — split it. `DataService.lua` is
  flagged in its own header as the file most tempted to break this rule;
  don't let a second one grow the same way.

### 9.6 Scalable-optional (no over-engineering)
- Design so the system scales when it genuinely needs to, and stays simple
  while it doesn't. Add a seam (a config table, a registry, an extra layer
  of indirection) only where growth is *actually* expected soon, not
  hypothetically someday. Three similar lines beat a premature abstraction.
  `PerfFlags`-style A/B transition flags (kept in the source project, not in
  this kit) are exactly the kind of scaffolding to delete once its job is
  done, not to leave as permanent config.

### 9.7 Façade API (no black boxes)
- Every Service and Controller exposes a typed public method API AND/OR
  declares the signals it emits (`GameEvents.OnX` / `EventBus.Domain.Event`).
  Other modules interact ONLY through that façade or by reacting to those
  signals — never by reaching into another module's internals (a private
  `_state` field, a local upvalue). `DataService`'s mutator-only write
  facade (§5) is the reference example.

### 9.8 Lifecycle & launch order
- Modules are side-effect-free at `require` time — actual work happens in
  `:Init()` then `:Start()` (see §3). Neither should yield indefinitely;
  spawn an internal loop (`task.spawn`, `Scheduler.Every`) instead of
  blocking the bootstrap.
- Boot order: `pairs()` order (undefined) by default. If two specific
  modules genuinely need a guaranteed order, give the dependent one a
  `Dependencies: {"OtherModuleName"}` field and flip
  `ENABLE_EXPERIMENTAL_DEPENDENCIES` to `true` in `init.client.lua` (server
  side has no equivalent yet — add the same topological sort to
  `init.server.lua` if you need it there, following the client's pattern).
  Don't reach for this before you have a real ordering bug.

### 9.9 Data-driven content (config-as-code)
- A content-heavy domain (abilities, items, quests, enemies, UI actions...)
  uses the **registry pattern**: each entry is a self-contained module
  (`{ Name, Run/Execute, ... }`), auto-collected by its owner from a folder
  of siblings and invoked by name. `Config/UIActions/` is the reference
  implementation — `init.lua` scans its own children, validates the
  contract, indexes by `Name`; adding an action means dropping a new file
  in that folder, never editing the registry itself. `RarityVisualConfig`,
  `PanelTagsConfig`, `AssetIds` (raw asset id strings, one file per category),
  and `NetworkEvents.EVENT_DEFINITIONS` are the same idea at a smaller scale
  (a flat table instead of a folder of modules) — reach for a full registry
  once the entries stop being "one line each".

### 9.10 Naming
- `PascalCase` — modules, services, controllers, types, public methods.
- `camelCase` — locals, parameters, private fields.
- `SCREAMING_SNAKE_CASE` — constants.
- Bus signals — `Domain.Event` (`EventBus.Data.Initialized`,
  `GameEvents.OnCurrencyEarned`); prefer a verb-first name for something
  that *just happened* (`OnCurrencyEarned`, not `CurrencyEarnedEvent`).
- Tags (`CollectionService`) — `<Domain>_<Subtype>_<Detail>`
  (e.g. `Hitbox_OpenWorld_Shop`). Use a tag when the object's identity/logic
  differs from its siblings; use an attribute when it's the same object with
  different parameters (speed, color, intensity).
- World elements — ONE tag per TYPE (`Config/AssetIds/TagNames.lua`), the
  variant is an attribute, the rules live in a code registry:

  | Tag | Attributes | Registry |
  |---|---|---|
  | `Pad_Win` | `Stage`, `Vip` | `TrophyPadConfig` |
  | `Pad_Treadmill` | `Id` | `TreadmillConfig.Treadmills` |
  | `Pad_Skin` | `Id` | `SkinConfig.Skins` |
  | `Hitbox_Checkpoint` | `Stage` | — |
  | `Kill_Part` | — | — |

  Access (free / rebirths / Robux) goes through `AccessGate`; while
  `MonetizationConfig.FreeMode` is on every Robux path is open.

## 10. Adding things — quick reference

| I want to... | Do this |
|---|---|
| Add a server system | New `ModuleScript` in `ServerScriptService/Bootstrapper/Services/` with `Init`/`Start` |
| Add a client system | New `ModuleScript` in `StarterPlayerScripts/Bootstrapper/StandaloneControllers/` with `Init`/`Start` |
| Add a UI panel | Copy `Panels/_Template/` (Fusion-built), rename its folder + panelId, register it in `Panels/init.lua` |
| Add a client↔server event | Add to `NetworkEvents.EVENT_DEFINITIONS` (+ `RATE_LIMITS` if it needs one), bridge it in `NetworkBridgeController` if client-bound, add an `EventBus` domain if none fits |
| Add a server-only signal | Add to `GameEvents.lua` |
| Add a pad that opens a panel | One entry in `Config/PadConfig.lua`, tag the hitbox in Studio |
| Add a treadmill / skin / win pad | Place the Part, tag it (see §9.10 table) + set `Id`/`Stage`/`Vip`, add ONE entry in its registry (`rebirth`/`GamepassId` fields = access rule) |
| Add a player data field | Edit `DataTemplate.lua` (value AND type, same file), add a mutator in `DataService.lua` if it's writable |
| Add a UI action (tag-driven click) | New file in `Config/UIActions/` |
| Add a quality-scalable cosmetic loop | `Scheduler.Every(name, hz, fn, true)` |
| Add a raw asset id (sound/image/mesh/particle/animation/tag) | One entry in the matching `Config/AssetIds/*.lua` file |
| Add / tune a sound effect | A `Sound` instance (id, volume, pitch) in `ReplicatedStorage/Assets/sfx` (Studio, any subfolder) + a recipe `Sound = { Name = "..." }` in `Config/EffectsConfig.lua`, played with `Effects.Play(recipeId)` |
| Validate a remote payload's shape | `Middleware.Validation.Create(validator)`, call at the top of the `OnServerEvent` handler (rate limiting is already automatic, see `NetworkEvents.RATE_LIMITS`) |
| Register an admin/dev command | `CommandService.RegisterCommand(name, handler)` from your service's `Init()` |
| Add/update a leaderboard stat | `LeaderstatsService.SetStat(player, name, value)` |
| Grant a developer product on purchase | `MonetizationService.RegisterProductHandler(productId, handler)` from your service's `Init()` — `handler` must be idempotent |
| Preload assets before a scene/screen | `LoadingController.RunPreload(config)` — see §3's boot-order callout, it's not auto-invoked |
| Exempt a file from the pcall budget | `--!derogation: pcall <reason>` on its own line near the top |
| Push a server-driven notification to a player | `NotificationService.Send(player, message, type, duration)` (or `.Broadcast(...)` for everyone) |
