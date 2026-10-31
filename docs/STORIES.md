# HAApp — Stories

Source: `docs/BRIEF.md`. There is no reference app, so `Screens:` lists the snapshot pages that will show each story.

Snapshot pages:
- `menu-empty`: the menu before anything is added
- `menu-items`: the menu with the seed groups
- `menu-offline`: the menu when the server can't be reached
- `main`: the main window
- `settings-general`: the General tab (connection and menu bar)
- `settings-menu`: the Menu tab
- `entity-picker`: the sheet for adding entities

Seed data (snapshot mode, served by a fake HA client):
- Group **Living Room**: `light.living_room` (on, 60 %), `switch.tv_plug` (off), `sensor.living_room_temperature` (21.4 °C)
- Group **Office**: `light.desk_lamp` (custom name "Desk", custom symbol `lamp.desk`), `sensor.office_power` (132 W)

Every attribute the seed data uses is something a story lets the user create: groups (S-010), custom names and symbols (S-012), and order (S-011).

---

## M1 Core loop: connect, pick, toggle

### S-001 Connect to Home Assistant with a URL and token
As the user, I open Settings → General, paste my server URL and a long-lived access token, and click Connect.
Screens: settings-general
Acceptance:
- [snap] The General tab shows a URL field, a secure token field, a Connect button, and a status line.
- [unit] The URL is normalized: a trailing slash is stripped, `http`/`https` is kept, and `ws(s)://…/api/websocket` is derived from it.
- [unit] The WebSocket auth handshake (`auth_required` → `auth` → `auth_ok`/`auth_invalid`) is parsed into a connection state.
- [self] With a bad token the error reads "Home Assistant rejected the access token. …", and with a server that can't be reached it reads "Can't reach Home Assistant at <url>. …".
- [unit] The token is saved in the Keychain and the URL in UserDefaults. The token never appears in plain files or logs.
UX:
- Flow: Menu footer "Settings…" (⌘,) or the first-run "Connect to Home Assistant" button -> General tab, Server URL field has focus -> paste URL, Tab, paste access token -> Return or "Connect" -> status line changes to "Connected to Home Assistant 2026.10" -> close Settings. Way back: fields keep their last saved values until Connect succeeds; "Disconnect" clears the token.
- Surface: a Settings window tab (a place people come back to). Errors are shown inline under the fields, never in an alert.
- States: empty fields with placeholders `http://homeassistant.local:8123` and "Paste a long-lived access token"; a spinner and "Connecting…" after half a second; error "Home Assistant rejected the access token. Create a new one in your Home Assistant profile under Security." (with a "Open Profile" link button) or "Can't reach Home Assistant at <url>. Check the server URL and that the server is running."; done "Connected to Home Assistant <version>" with a green dot and the word "Connected".
- Words: "Server URL", "Access token", "Connect", "Disconnect", help text under the token field: "Create one in Home Assistant: Profile → Security → Long-lived access tokens."
- Access: Return triggers Connect (default button); the token is a SecureField; the status is announced via VoiceOver when it changes; status uses a word plus a dot, not color alone.
Status: in progress (URL, token in Keychain, REST check done; WebSocket handshake with S-002)

### S-002 Stay connected and receive live state
As the user, I see entity states update within a second of changing them anywhere else (wall switch, HA UI).
Depends: S-001
Acceptance:
- [unit] After `auth_ok` the client sends `get_states`, then `subscribe_events` for `state_changed`, and keeps an in-memory store keyed by `entity_id`.
- [unit] A `state_changed` event updates exactly one entry in the store.
- [unit] When the socket drops, the client reconnects with backoff (1 s, 2 s, 5 s, 10 s, capped at 30 s) and resubscribes.
- [manual] After sleep/wake or a Wi-Fi change, the app reconnects without any action from me.
UX:
- Flow: none for the user; state just updates in the open menu.
- Surface: none (background). The visible result lives in S-003/S-008.
- States: while reconnecting, items keep their last known state, dimmed (see S-008), so nothing jumps to empty.
- Words: none new.
- Access: state changes in an open menu are not announced (too chatty); VoiceOver reads the current state when focus lands on an item.
Status: todo

### S-003 Open the menu from the menu bar
As the user, I click the HAApp icon in the menu bar and the menu opens showing my chosen entities.
Screens: menu-empty, menu-items
Depends: S-002
Acceptance:
- [snap] `menu-items` shows the groups and rows in order, each row with a symbol, a name, and its state.
- [snap] `menu-empty` explains that nothing is added yet and has an "Add Entities…" button that opens Settings → Menu.
- [snap] The menu footer has Settings… and Quit HAApp.
- [self] The menu bar icon shows only when Settings → General → "Show in menu bar" is on (off by default). The app has a Dock icon and a main window.
UX:
- Flow: click the menu bar icon (or the global shortcut, S-031) -> the menu opens with keyboard focus on the first item -> click outside, Escape, or click the icon again to close.
- Surface: `MenuBarExtra` with `.window` style (a few related choices tied to one control). Fixed width 320 pt, height grows with content up to 560 pt, then scrolls.
- States: empty "No items yet" / "Add lights, switches, and sensors from Home Assistant." with an "Add Entities…" button; not connected → see S-041; too much → names truncate in the middle with the full name in a tooltip, the list scrolls.
- Words: group headers in title case as the user typed them; footer "Settings…" (⌘,) and "Quit HAApp" (⌘Q).
- Access: arrow keys move between items (S-032); each item is one accessibility element: "Living Room light, on, 60 percent".
Status: todo

### S-004 Turn a light or switch on or off from the menu
As the user, I click a light or switch row to turn it on or off.
Screens: menu-items
Depends: S-003
Acceptance:
- [unit] Clicking a row sends `call_service` with domain `light`/`switch`, service `toggle`, and the row's `entity_id`.
- [snap] An "on" row shows a filled, tinted symbol and an "off" row a plain one. The state is drawn from the store, not guessed.
- [self] While the call is pending the row shows a busy state. If the call fails, the row returns to its previous state and shows the error in its help text.
UX:
- Flow: click anywhere on a light or switch item -> the symbol fills immediately (optimistic) -> confirmed by the next `state_changed` -> on failure it reverts.
- Surface: inline (changes one value on screen). The whole item is the button; no separate switch control, to keep items one line tall.
- States: on = filled symbol in the accent color plus the word "On"; off = outline symbol, secondary color, "Off"; pending = small spinner replacing the state word after 0.3 s; error = state reverts, a red exclamation mark appears for 4 s, help text "Couldn't turn on Desk: <HA message>".
- Words: state words "On" / "Off"; help on hover "Turn on Living Room" / "Turn off Living Room".
- Access: Space or Return toggles the focused item; VoiceOver action name "Turn On"/"Turn Off"; on/off is shown with symbol shape plus a word, not color alone.
Status: todo

### S-005 Read a sensor value in the menu
As the user, I see sensors like temperature and power with their value and unit.
Screens: menu-items
Depends: S-003
Acceptance:
- [unit] A sensor row shows `state` + `unit_of_measurement` ("21.4 °C", "132 W"), and `unavailable`/`unknown` shows as "—".
- [snap] Sensor rows are read-only: no hover highlight and no click action.
- [unit] The default symbol comes from `device_class` (temperature → `thermometer.medium`, power → `bolt`, humidity → `humidity`, otherwise `gauge`).
UX:
- Flow: none; the value is visible when the menu opens.
- Surface: inline, read-only item.
- States: unavailable → "—" with help "Home Assistant reports this sensor as unavailable."; long values truncate at the trailing end.
- Words: value and unit as Home Assistant sends them, digits in monospaced numerals so the column doesn't jitter.
- Access: VoiceOver reads "Office power, 132 watts"; the item is not focusable as a button (it is static text).
Status: todo

### S-006 Add entities to the menu
As the user, I open Settings → Menu, click "+", search my entities, and check the ones to show.
Screens: settings-menu, entity-picker
Depends: S-002
Acceptance:
- [snap] The picker lists the supported entities (`light.*`, `switch.*`, `sensor.*`) with their friendly name and `entity_id`, and has a search field.
- [unit] Search matches the friendly name or `entity_id`, ignoring case.
- [self] Added entities appear in the menu right away, in the order they were added.
UX:
- Flow: Settings → Menu tab -> "+" button below the list or the empty-state "Add Entities…" button (also from the menu's empty state) -> sheet "Add Entities" with the search field focused -> type, check entities -> "Add" (Return) -> sheet closes, new items selected in the list. Escape or "Cancel" closes without changes.
- Surface: sheet on the Settings window (one short task that must finish or cancel).
- States: loading the list is instant from the live store; not connected → "Connect to Home Assistant to see your entities." with a "Connection Settings" button; no search results → "No entities match “<query>”."; entities already in the menu show a checkmark and are disabled with help "Already in the menu".
- Words: sheet title "Add Entities", button "Add 3 Entities" (count updates, disabled at 0), "Cancel"; "+" tooltip "Add entities from Home Assistant to the menu".
- Access: arrow keys move through results, Space checks, Return adds; each result reads "Desk Lamp, light.desk_lamp, not added".
Status: todo

### S-007 Keep my menu across restarts
As the user, I quit and relaunch, and my menu looks exactly the same.
Depends: S-006
Acceptance:
- [unit] MenuGroup and MenuItem are stored in SwiftData. A relaunch restores them in the same order.
- [unit] An item whose entity no longer exists in HA stays in the menu and shows "Not found in Home Assistant" instead of disappearing.
UX:
- Flow: none; the menu is simply the same after relaunch.
- Surface: a not-found item in the menu and in Settings.
- States: not found → item dimmed, symbol `questionmark.circle`, state word "Not found", help "light.old_lamp isn't in Home Assistant anymore. Remove it in Settings → Menu."
- Words: "Not found".
- Access: VoiceOver reads "Old Lamp, not found in Home Assistant".
Status: todo

### S-008 See when the server is unreachable
As the user, I can tell at a glance when HAApp isn't connected.
Screens: menu-offline
Depends: S-003
Acceptance:
- [snap] When disconnected, the menu bar icon shows a slashed variant.
- [snap] `menu-offline` shows a banner "Can't reach Home Assistant. Retrying…" with a Retry button. Rows are dimmed and can't be clicked.
UX:
- Flow: connection drops -> menu bar icon changes to its slashed variant -> opening the menu shows a banner at the top -> "Retry" reconnects now; it otherwise retries on its own.
- Surface: inline banner at the top of the menu (information plus one action; never an alert).
- States: retrying "Can't reach Home Assistant. Retrying…" with "Retry"; token rejected "Home Assistant rejected the access token." with "Connection Settings" (no auto-retry); items dimmed with their last known state and not clickable.
- Words: "Retry", "Connection Settings".
- Access: the banner is the first focusable element; the icon change is paired with the VoiceOver label "HAApp, not connected" on the menu bar item.
Status: todo

---

## M2 Customize

### S-010 Create and rename groups
As the user, I add a group in Settings → Menu, name it, and move items into it.
Screens: settings-menu, menu-items
Depends: S-006
Acceptance:
- [snap] Groups appear as section headers in both Settings and the menu.
- [self] Renaming a group updates the menu header right away. Deleting a group asks first and moves its items to "Ungrouped".
Status: todo

### S-011 Reorder items and groups by dragging
As the user, I drag rows and groups in Settings → Menu to change their order.
Screens: settings-menu
Depends: S-010
Acceptance:
- [unit] Moving an item updates `order` for its group only, and moving it across groups updates both groups.
- [self] The new order shows in the menu and survives a relaunch.
Status: todo

### S-012 Give an item a custom name and symbol
As the user, I select an item and set a display name and an SF Symbol.
Screens: settings-menu, menu-items
Depends: S-006
Acceptance:
- [snap] The inspector shows a name field (with the friendly name as placeholder) and a symbol picker with search.
- [unit] Clearing the custom name falls back to the friendly name, and clearing the symbol falls back to the default for the domain or device class.
Status: todo

### S-013 Remove an item from the menu
As the user, I select an item and press Delete, or choose Remove from its context menu.
Screens: settings-menu
Depends: S-006
Acceptance:
- [self] The item disappears from Settings and the menu. Command-Z undoes it.
Status: todo

### S-014 Collapse a group in the menu
As the user, I click a group header in the menu to collapse or expand it.
Screens: menu-items
Depends: S-010
Acceptance:
- [unit] The collapsed state is saved per group and survives a relaunch.
Status: todo

---

## M3 Light control

### S-020 Set brightness of a dimmable light
As the user, I adjust a dimmable light's brightness with a slider in its row.
Screens: menu-items
Depends: S-004
Acceptance:
- [unit] The slider only appears when `supported_color_modes` includes a mode that supports brightness.
- [unit] Releasing the slider sends `light.turn_on` with `brightness_pct`. Changes while dragging are throttled to at most 4 calls a second.
Status: todo

---

## M4 System

### S-030 Launch at login
As the user, I turn on "Open at login" in Settings → General.
Acceptance:
- [self] The toggle uses `SMAppService.mainApp` and reflects the real registration status.
Status: todo

### S-031 Open the menu with a global shortcut
As the user, I press a shortcut I chose (no default) to open the menu from anywhere.
Depends: S-003
Acceptance:
- [manual] The shortcut opens and closes the menu while any app is frontmost.
- [snap] Settings → General has a shortcut recorder.
Status: todo

### S-032 Navigate the menu with the keyboard
As the user, I use the arrow keys to move between rows, Return or Space to toggle, and Escape to close.
Depends: S-004
Acceptance:
- [self] The focus ring follows the arrow keys, Return toggles the focused light or switch, and Escape closes the menu.
Status: todo

---

## M5 Polish

### S-040 App icon and menu bar glyph
Acceptance:
- [snap] There is a Liquid Glass app icon, and a template menu bar glyph that looks right in light and dark menu bars.
Status: todo

### S-041 First-run welcome
As a new user, opening the menu before connecting shows one step: "Connect to Home Assistant", with a button to the General tab.
Depends: S-001
Acceptance:
- [snap] `menu-empty` shows different text before and after connecting.
Status: todo

---

## Later
- Pin one sensor's value next to the menu bar icon.
- More domains: scenes, scripts, climate, covers, media players.
- Color and color-temperature controls for lights.
- Multiple servers.
- iCloud sync of the menu layout.
- Shortcuts actions ("Toggle entity").

## Dropped
- Accounts or OAuth login: a long-lived token is enough for one user.
- mDNS server discovery: one URL, entered once.
- Notifications from HA: the HA phone app already covers them.
- History graphs: the HA web UI covers them.
- Analytics and crash reporting: personal app.
