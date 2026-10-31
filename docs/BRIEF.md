# HAApp

A macOS menu bar app that talks to your Home Assistant server over its API, so you can flip lights and switches and glance at sensors without opening a browser. You choose what goes in its menu.

Repo: `ha-app` · Bundle id: `com.krekas.haapp`

## Replaces
Opening the Home Assistant web UI or phone app to toggle a light or check a sensor.

## Main jobs
1. Toggle lights and switches with one click from the menu bar popover.
2. Glance at sensor values (temperature, humidity, power, …) in the popover.
3. Customize the popover: pick entities, put them in groups, reorder them by dragging, and rename or re-icon them.

## Data
- **Server**: base URL, long-lived access token (stored in Keychain, never in plain files), connection state.
- **MenuGroup**: title, order, collapsed flag.
- **MenuItem**: entity_id, custom name (optional), custom SF Symbol (optional), order, group, shown in the menu bar, shown in the window.
- **EntityState** (live, not persisted): entity_id, domain, state, attributes (friendly_name, unit, brightness, device_class), last_changed.

## Shape
A normal app with a Dock icon and a main window that shows the custom groups and items. A menu bar icon (`MenuBarExtra`, window style) with the same groups and items is optional: Settings > General > "Show in menu bar". When it's on, HAApp keeps running after its window closes. A Settings window has the **General** tab (server URL and access token with Connect, and the menu bar toggle) and the **Menu** tab (entity picker with search, drag to reorder, groups). macOS 26 or later.

## Connection
Home Assistant API, with no add-on or integration needed on the HA side:
- WebSocket API (`/api/websocket`): auth with the token, `get_states`, `subscribe_events` for `state_changed` (live updates), and `call_service` (toggle).
- REST API (`/api/`): used as a fallback and for "Test connection".
- Reconnects automatically after sleep/wake and network changes. Works over the LAN or a remote URL (Nabu Casa, reverse proxy).

It needs the network to reach the HA server. The menu layout is stored locally. No accounts.

## System hooks
Menu bar item, launch at login, and an optional global shortcut to open the popover (decided by the agent).

## Reference
None. The official Home Assistant Companion app for macOS shows what to avoid: a heavy app whose menu you can't customize.

## Look
Native macOS 26 (Liquid Glass popover, SF Symbols). The accent color is Home Assistant blue `#18BCF2` (decided by the agent).

## Not in version one
- Showing sensor values in the menu bar title itself (later: pin one sensor next to the icon).
- Climate, covers, media players, scenes and scripts (later: more domains).
- Multiple HA servers, OAuth login, mDNS discovery of the server.
- Notifications, Shortcuts actions, and history graphs.
- iCloud sync of the menu layout.
