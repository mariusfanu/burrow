# Burrow design

Burrow should feel calm and trustworthy. The feeling it aims for is relief: you can see what's under the surface, and clearing it lifts a weight.

## System rules

- **Standard first.** The sidebar, toolbar, sheets, alerts, menus and Settings window are system components, so they get Liquid Glass and accessibility behavior from macOS.
- **Glass floats and content doesn't.** Liquid Glass appears only on controls above content: the toolbar, the sidebar, prominent buttons and the Undo message. Cards and the treemap stay in the content layer.
- **Color comes from the person's Mac.** Burrow has no brand color. The accent marks actions and selection, and the Overview scene and treemap are derived from it, in whichever accent is chosen in System Settings. Status colors are the system's own and always appear with a symbol or words.
- **Layout comes from `Theme`.** Corner radii and spacing are named tokens in `Sources/Burrow/DesignSystem/Theme.swift`, so nested shapes stay related. The odd values left in views, such as 3 and 5, are optical adjustments.
- **Derived colors stay readable.** `AccentPalette` keeps treemap labels at 4.5:1 or better at every depth, for every macOS accent, and tests hold it to that.
- **One primary action.** Each page has at most one prominent button. The toolbar and the Actions menu read from the same `PageAction`, so they can't disagree.
- **Rest when idle.** Nothing animates forever. Motion follows an event and then stops.
- **Numbers read like the system writes them.** Sizes use one formatter, so zero is "0 bytes" rather than "Zero KB". Rates and counters never drop to bytes, so an idle disk reads "0 KB/s" and a count-up starts at "0 KB" instead of switching units on its first tick. History speaks in page names ("Touch ID", "Project Purge"), relative dates ("Yesterday at 23:39"), inflected counts ("1 item") and grouped digits ("2,145"), and it leaves a column empty rather than filling it with zeros.

## Motion

All motion comes from `Sources/Burrow/DesignSystem/Motion.swift`, so Reduce Motion is honored in one place. When it's on, movement, scale and blur become short fades.

| Token | Animation | Used for |
|---|---|---|
| `snap` | Snappy, 0.2 s | Hover, selection, toggles |
| `glide` | Smooth, 0.34 s | Page and state changes |
| `settle` | Spring, 0.5 s, slight bounce | Things arriving and coming to rest |
| `lift` | Spring, 0.75 s, almost no bounce | Meter levels and treemap layout |

| Moment | What happens | What it tells you |
|---|---|---|
| Moving between pages | The new page rises from the direction you moved in the sidebar, and the old one dissolves | Where you went |
| Clean scan | Groups rise in and the total rolls upward, in a layout that's already final when the scan ends | The preview is really finding this, right now |
| Disk Explorer, opening a folder | The tile grows until it fills the map, and its contents appear inside in shades of its color | Where you are, and that color marks the branch |
| Disk Explorer, going back | The same trip in reverse, ending on the tile you opened | Where you came from |
| Move to Trash | The tile leaves, the others close over the gap, and a message offers Undo | What changed, and that it can be undone |
| Overview scene | The level rises and settles, then holds still, and falls when disk use drops | How full the disk is |
| Running a command | Finished lines rise into the log with drawn checkmarks, and the bar moves only when a section starts | Real progress |
| Finishing a command | A checkmark draws, then lands with one bounce and a single ring rippling outward, while the space freed counts up and a soft light rises and fades once | It worked, and what you gained |
| Wrong password | The field shakes, and the message says why | Try again |
| Status samples | Traces glide one step and a dot marks the newest sample, the live dot pulses, and the process table updates in place. A young trace sits on a hairline floor and fades in from its first sample | The data is fresh, and a table that reorders every tick stays readable |
| Waiting for a figure | A soft placeholder holds the number's place until it's measured | Something is coming, and nothing will jump |
| Sidebar | Icons bounce once on selection, with a spinner or result at the trailing edge | Work continues on other pages |

## HIG audit

This compares the first version with the Human Interface Guidelines as of November 2026, focusing on what applies to a Mac app.

### Fixed

| Finding | Guideline | Change |
|---|---|---|
| Primary actions sat in a bar at the window's bottom | Avoid controls at the bottom of a window | Moved to the toolbar's trailing edge |
| Commands weren't all in the menu bar, and there was no Settings item | The menu bar should offer every command, and Settings belongs in the app menu | Added Actions and Go menus, View commands, Help items and a Settings window, and moved setup out of the sidebar |
| "Clean" and "Move to Trash" used the red destructive style | That style is for actions people didn't deliberately choose | Now standard buttons with specific verbs |
| Move to Trash always asked first | Don't warn about undoable actions | No confirmation for ordinary items, and added Undo (Edit menu and message) |
| Return confirmed actions that can't be undone | Make the default button the safe choice for destructive actions | Clean, external volume cleanup, Installers, Project Purge and Skip the Trash need a click, and each sheet says whether a removal can be undone |
| Custom page background, hard-coded brown palette, status colors and a brand mark in the sidebar | Use system colors, and let branding defer to content | Removed, and every color now comes from the system or is derived from its accent |
| Many tinted buttons | One or two prominent buttons per view | One primary action, in the Liquid Glass prominent style |
| Glass-like custom surfaces with no real material | Glass is for controls, not content | Real Liquid Glass above content, and plain content surfaces |
| Page titles repeated the window title | Use the toolbar title, and keep hierarchy clear | Window title and subtitle carry the page name and selection |
| Generic "Confirm" buttons | Button titles should be specific verbs | Titles come from the CLI's question, such as Remove or Delete |
| Spinner with no progress information | Prefer determinate progress | Clean and Optimize progress by section |
| Flat app icon with baked-in effects | Layered icons, with no custom shadows or highlights | Layered `.icon` rendered by the system |
| Lists had no keyboard path | Support keyboard-only use | Arrow keys move, Space toggles and Command-A selects all |
| An in-window transition could overflow the window | Resizable layouts must hold at any size | Page frame contains every page |
| Page state was lost on relaunch | Restore prior state | The last page is restored |

### Deliberately different

- **Clean, external volume cleanup and Optimize still confirm.** The guideline warns only about unexpected loss, but cleaning can't be undone. A short alert is cheap protection, and it isn't styled as destructive.
- **Disk Explorer asks before high-risk moves.** Moving `~/.ssh`, `~/Library/Keychains` or a whole folder at the top of home can be undone, but it can do harm first, such as breaking sign-ins or syncing a removal to other devices. These items get an alert first. Ordinary files still move in one click, like the Finder.
- **Selection rows use checkboxes and full-row clicks.** A native table's selection model suits browsing, but choosing what to delete is clearer with visible checkboxes.

### Not done or not verified

- **Sortable, resizable table columns:** lists use a sort menu instead.
- **Customizable toolbar:** the View menu's command exists, but the items aren't customizable.
- **Help book:** the Help menu links to Mole's documentation instead.
- **Checks not yet run:** VoiceOver, Full Keyboard Access, Increase Contrast, Reduce Transparency, right-to-left layout and touch input.
