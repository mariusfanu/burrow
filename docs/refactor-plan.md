# Burrow refactor plan — 12 November 2026

A code-quality and performance review of the whole codebase at `2e15a28` (Burrow 0.1.0), written as
instructions for the model that will implement it. The review used the SwiftUI Pro skill and Apple's
Xcode `swiftui-specialist` / `swiftui-whats-new-27` skills, and read every file under `Sources/`.

**Overall verdict.** The code is in good shape: Swift 6 strict concurrency with no warnings, every
`@Observable` model is `@MainActor`, every `@State` is private, no deprecated SwiftUI API, no
`AnyView`, no custom environment keys, `NavigationSplitView` and `Tab` are used correctly, and the
core engine is heavily tested. The findings below are therefore mostly about file structure,
duplication, a handful of closure bindings, a few formatting and search rules, and three small
performance items. Nothing here is a rewrite.

---

## 0. Read this first

### 0.1 Baseline (verified before writing this plan)

| Item | Value |
|---|---|
| Toolchain | Xcode 27.3, Swift 6.4.2, arm64 macOS 27.3 |
| Deployment target | macOS 26 (`Package.swift`, `project.yml`). **Do not change it.** |
| `swift build` | Clean, no warnings |
| `swift test` | 308 tests pass: 122 in `BurrowTests` (37 suites), 186 in `BurrowCoreTests` (32 suites). 3 host tests are skipped unless `BURROW_RUN_HOST_TESTS=1`. |
| Lint/format tools | None configured. Do not add any. |
| Snippets in this plan | The Swift in steps 1.2, 1.3, 1.5, 2.1, 2.3, 2.4, 2.5, 2.6, 3.1 and 6.1–6.2 was type-checked in Swift 6 language mode with this toolchain and run where it has output. |

### 0.2 Rules for the implementer

1. **Read `docs/simplification.md` before touching anything**, in particular "Decisions", "Left alone
   on purpose" and "Measurements that did not justify more code". Those are settled. This plan does
   not reopen any of them, and neither should you. The most relevant ones are repeated in section 9.
2. **Every step is behavior-preserving unless it says "Behavior change".** If a step cannot be done
   without changing behavior that the step doesn't name, stop and report instead of improvising.
3. **No new dependencies, no new build tools, no deployment-target change, no new caches** beyond the
   ones this plan names.
4. **One step, one commit.** Work on a branch named `refactor/review-2026-11`. Use the commit subject
   given in each step. Keep history linear (no merge commits). Do not push. If you have not been told
   you may commit, ask once before the first commit.
5. **After every step run:**
   ```bash
   swift build 2>&1 | grep -E "warning:|error:" ; swift test 2>&1 | grep -E "Test run with|failed|error:"
   ```
   Expected: no warning or error lines, and two `Test run with … passed` lines. Test counts only ever
   go up.
6. **At the end of every phase also run** the release suite and the bundle build, because optimized
   builds behave differently here (see the `TaskGroup` note in `UninstallModel.measure`):
   ```bash
   swift test -c release -Xswiftc -enable-testing 2>&1 | grep -E "Test run with|failed|error:"
   scripts/build-app.sh release
   ```
7. **Moving a type to its own file:** use `git mv` when a whole file moves. When extracting a type
   from a larger file, create the new file with only the imports that type needs (`SwiftUI`,
   `BurrowCore`, `AppKit`, `Foundation`), move the type with its doc comment unchanged, and remove
   `private` from the type declaration (it becomes internal). If the moved type used a
   `private`/`fileprivate` symbol of its old file, widen that one symbol to internal, never public.
   SwiftPM picks new files up automatically; `Burrow.xcodeproj` is generated and git-ignored.
8. **Line numbers below refer to the files as they are at `2e15a28`.** After Phase 1 they drift, so
   locate code by the symbol names given.
9. **Do not use `Binding(get:set:)`, computed `some View` properties, `String(format:)`,
   `DispatchQueue`, or `onTapGesture` in new code.** The existing accepted exceptions are listed in
   section 9.

### 0.3 Phase overview

| Phase | What | Risk | Steps |
|---|---|---|---|
| 1 | Small correctness and performance fixes | Low | 1.1 – 1.6 |
| 2 | Duplicate removal | Low | 2.1 – 2.7 |
| 3 | Closure bindings and view logic into models | Low–medium | 3.1 – 3.5 |
| 4 | Subview extraction (computed view properties) | Medium | 4.1 – 4.3 |
| 5 | File and folder structure (pure moves) | Low, large diff | 5.1 – 5.9 |
| 6 | Optional core hygiene | Low | 6.1 – 6.3 |
| 7 | Documentation | None | 7.1 |

Phases are ordered so that logic changes land against the current file layout and the big move comes
after them. Do them in order. Phase 6 is optional: do it only if asked.

---

## Phase 1 — Small correctness and performance fixes

### 1.1 Search apps with `localizedStandardContains`

**Why.** User-typed filters should match the way Finder does (case- and diacritic-insensitive,
locale-aware). `localizedCaseInsensitiveContains` is not diacritic-insensitive.

**File.** `Sources/Burrow/Features/Uninstall/UninstallModel.swift`, `visibleApps` (lines 73–79).

```swift
// Before
$0.name.localizedCaseInsensitiveContains(query)
    || ($0.bundleId?.localizedCaseInsensitiveContains(query) ?? false)

// After
$0.name.localizedStandardContains(query)
    || ($0.bundleId?.localizedStandardContains(query) ?? false)
```

**Behavior change.** "cafe" now finds "Café".

**Test.** Add to `Tests/BurrowTests/UninstallModelTests.swift`, following the existing pattern that
loads apps through `ScriptedCommands`: load an app named `Café`, set `searchText = "cafe"`, expect it
in `visibleApps`; set `searchText = "CAF"`, expect it; set `searchText = "zzz"`, expect empty.

**Commit.** `Search apps the way Finder does`

### 1.2 Replace C-style number formatting in the Status page

**Why.** `String(format:)` ignores the user's locale; the rest of the page already uses `FormatStyle`
(see `DiskRow` and `PercentReadout`). `docs/design.md` says "Numbers read like the system writes them".

**File.** `Sources/Burrow/Features/Status/StatusView.swift`. Five call sites:

| Line | Before | After |
|---|---|---|
| 259 | `String(format: "%.2f", snapshot.cpu?.load1 ?? 0)` | `(snapshot.cpu?.load1 ?? 0).formatted(.number.precision(.fractionLength(2)))` |
| 430 | `String(format: "%.0f", usage)` | `usage.formatted(.number.precision(.fractionLength(0)))` |
| 453 | `String(format: "%.0f", battery.percent ?? 0)` | `(battery.percent ?? 0).formatted(.number.precision(.fractionLength(0)))` |
| 461 | `String(format: "%.1f", snapshot.thermal?.systemPower ?? 0)` | `(snapshot.thermal?.systemPower ?? 0).formatted(.number.precision(.fractionLength(1)))` |
| 594 | `Text(String(format: "%.1f%%", process.cpu ?? 0))` | `Text("\((process.cpu ?? 0).formatted(.number.precision(.fractionLength(1))))%")` |

Keep the literal `%` suffix as `DiskRow` does; do not switch to `.percent`, which adds a space in
some locales and would make the column inconsistent with the rest of the page.

**Do not touch** the two `String(format:)` calls in `Sources/BurrowCore/Safety/OperationsLog.swift`.
That is a log interchange format that must stay locale-independent, and the file is on the
"left alone" list.

**Behavior change.** Decimal separators follow the locale (for example `1,25` in German).

**Commit.** `Format status figures with the system's number styles`

### 1.3 Stop building date formatters per history row

**Why (measured).** `HistoryDate.parse` and `HistoryDate.text(for:)` each build a `DateFormatter` on
every call, and both run for every history row that is drawn (`SessionRow`, `RecentSessionRow`,
`HistoryFiles` rows). An optimized standalone benchmark of 200 rows (parse + display, best of 7,
identical output verified): **54.8 ms with fresh formatters, 13.7 ms with shared ones.** This is a
formatter microbenchmark, not a whole-app figure.

**File.** `Sources/Burrow/Features/History/HistoryPresentation.swift`, replace the body of
`enum HistoryDate` (lines 78–99) with:

```swift
/// Reads the CLI's timestamps and writes them the way the Finder does.
enum HistoryDate {
    // Formatters are safe to share once configured, and these are never changed again.
    private static let parsers: [DateFormatter] = [
        "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ssZ", "yyyy-MM-dd'T'HH:mm:ssXXXXX",
    ].map { format in
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        // Autoupdating, so a time-zone change while the app runs is honored as it was before.
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = format
        return formatter
    }

    private static let display: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        return formatter
    }()

    static func parse(_ text: String) -> Date? {
        for parser in parsers {
            if let date = parser.date(from: text) { return date }
        }
        return nil
    }

    static func text(for date: Date) -> String {
        display.string(from: date)
    }
}
```

This follows the existing `ByteFormat` pattern in `Theme.swift`, without `nonisolated(unsafe)`:
`DateFormatter` is `Sendable` in this SDK, and the attribute produces an "unnecessary" warning
(checked with Swift 6.4.2). Do not add `@MainActor`; tests call these off the main actor.

**Test.** Add to `Tests/BurrowTests/HistoryPresentationTests.swift`: each of
`"2026-11-01 23:39:10"`, `"2026-11-01T23:39:10+0200"`, `"2026-11-01T23:39:10+02:00"` parses to
non-nil; `"sometime"` parses to nil; the two offset forms parse to the same `Date`.

**Commit.** `Share History's date formatters`

### 1.4 Read Mole's default whitelist only when it is needed

**Why.** `WhitelistStore.init` reads and scans `lib/core/base.sh` (77 KB in Mole 1.70.0) to learn the
default patterns. `ProtectedSettings.store` is a computed property, so every access builds a new
store: `reload()` reads the script twice and an add reads it three times, all on the main actor.
`CleanModel.protect` reads it once per protected path. The defaults only matter while the user's
whitelist file does not exist yet.

**File.** `Sources/BurrowCore/Config/WhitelistStore.swift`.

```swift
// Before
private let fileURL: URL
private let home: String
private let defaults: [String]

public init(home: String = NSHomeDirectory(), cliRoot: String?) {
    self.home = home
    fileURL = URL(fileURLWithPath: home + "/.config/mole/whitelist")
    defaults = Self.readDefaults(cliRoot: cliRoot, home: home)
}

// After
private let fileURL: URL
private let home: String
private let cliRoot: String?

/// Read from the installed CLI on demand: only a missing whitelist file needs them.
private var defaults: [String] { Self.readDefaults(cliRoot: cliRoot, home: home) }

public init(home: String = NSHomeDirectory(), cliRoot: String?) {
    self.home = home
    self.cliRoot = cliRoot
    fileURL = URL(fileURLWithPath: home + "/.config/mole/whitelist")
}
```

In `save(_:)`, read the defaults at most once: `if usesDefaults, defaults.isEmpty { throw … }` already
does that. `load()` is unchanged in text. No other file changes.

**Verify.** All existing `WhitelistStore` tests in `Tests/BurrowCoreTests` pass untouched (they cover
default fallback, broken links and first-save behavior).

**Commit.** `Read default protections only when the whitelist is missing`

### 1.5 Hoist constants out of the terminal's draw path

**Why.** `TerminalCanvas.cellSize` measures a string with `NSString.size(withAttributes:)` on every
`draw(_:)` and every `setFrameSize(_:)`, although the font never changes. `paletteColor(_:)` allocates
its two lookup arrays on every call, once per styled run of cells. These are constant hoists, not a
new cache; no speedup is claimed.

**File.** `Sources/Burrow/Run/TerminalPanel.swift`.

- Replace the computed `private var cellSize: CGSize { … }` with a stored constant. A property
  initializer can't read the `font` property, so it measures with a local copy of the same font:
  ```swift
  private let cellSize: CGSize = {
      let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
      let width = ("M" as NSString).size(withAttributes: [.font: font]).width
      return CGSize(width: ceil(width), height: ceil(font.ascender - font.descender + font.leading) + 2)
  }()
  ```
- In `paletteColor(_:)`, move `base` and `levels` to
  `private static let basePalette: [UInt32]` and `private static let cubeLevels: [CGFloat]`.

**Verify.** `TerminalAccessibilityTests` passes. Then run the app, start any command, toggle
**Terminal** in the toolbar and confirm colors and the cursor look as before.

**Commit.** `Compute the terminal's cell size and palette once`

### 1.6 Small modernizations (one commit)

All mechanical, same semantics:

- `Sources/BurrowCore/Config/WhitelistStore.swift` (4 uses) and
  `Sources/BurrowCore/Models/HistoryReport.swift` (1 use):
  `replacingOccurrences(of: a, with: b)` → `replacing(a, with: b)`.
- `Sources/Burrow/Run/RunController.swift` lines 123 and 424: `Date()` → `Date.now`.
- `Sources/BurrowCore/Models/StatusSnapshot.swift`: make `Disk` `Identifiable` with
  `public var id: String { mount ?? "" }`, and in `StatusView.swift` `DiskCard` change
  `ForEach(snapshot.disks ?? [], id: \.mount)` to `ForEach(snapshot.disks ?? [])`.
- `Sources/Burrow/Features/About/AboutView.swift`: remove every `public` (this is an executable
  target; `AboutViewTests` uses `@testable import`), remove the three `// App Header`-style section
  comments, and apply:
  - `.font(.title2.weight(.bold))` → `.font(.title2).bold()`
  - `.clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))` → `.clipShape(.rect(cornerRadius: 18))`
  - `.contentShape(Rectangle())` → `.contentShape(.rect)`
  - `.shadow(color: .black.opacity(0.12), radius: 6, x: 0, y: 3)` → `.shadow(color: .black.opacity(0.12), radius: 6, y: 3)`
- `Sources/Burrow/Features/Uninstall/UninstallModel.swift` and
  `Sources/Burrow/Features/Status/StatusStore.swift`: move the stored properties that currently sit
  *after* `init` to just above it, so each class reads properties → init → methods. No other change.
- `Tests/BurrowTests/AboutViewTests.swift`: delete `aboutViewCanBeInstantiated` and
  `aboutPanelControllerCanBeAccessed`. They assert only that a type has its own name and that a
  singleton equals itself. Keep the two tests that check real values.

**Commit.** `Tidy small API and style leftovers`

---

## Phase 2 — Duplicate removal

### 2.1 One mapping from a CLI command to its page

**Why.** `HistoryReport.Session.title` repeats seven page titles that already live in `Screen.title`,
and `Session.symbol` finds its page with `Screen.allCases.first { $0.rawValue.hasPrefix(commandName) }`,
which matches by accident (an empty command name matches Overview).

**Files.** `Sources/Burrow/App/Screen.swift`, `Sources/Burrow/Features/History/HistoryPresentation.swift`.

Add to `Screen.swift`:

```swift
extension Screen {
    /// The page a CLI command belongs to. Every command is named like its page except
    /// `mo installer`.
    init?(commandName: String) {
        switch commandName {
        case "installer": self = .installers
        default:
            guard let screen = Screen(rawValue: commandName) else { return nil }
            self = screen
        }
    }
}
```

Rewrite the two properties:

```swift
var title: String {
    if let screen = Screen(commandName: commandName) { return screen.title }
    switch commandName {
    case "touchid": return "Touch ID"
    case "update": return "Update"
    case "completion": return "Shell Completion"
    case "remove": return "Remove Mole"
    default: return commandName.capitalized
    }
}

var symbol: String {
    switch commandName {
    case "touchid": "touchid"
    case "update": "arrow.down.circle"
    default: Screen(commandName: commandName)?.symbol ?? "terminal"
    }
}
```

**Behavior change (tiny).** A session whose command is literally `status`, `history` or `overview`
would now be titled with the page name instead of the capitalized command. An empty command name now
gets the terminal symbol instead of Overview's.

**Verify.** `HistoryPresentationTests` passes untouched (`touchid` → "Touch ID",
`purge-dry-run` → "Project Purge", `something-new` → "Something-New"). Add expectations for
`installer` → "Installers" and `analyze` → "Disk Explorer", and for `symbol` of `clean`, `installer`,
`touchid` and `something-new` (`"sparkles"`, `"shippingbox"`, `"touchid"`, `"terminal"`).

**Commit.** `Map history commands to pages in one place`

### 2.2 One definition of "a session that did something"

**Why.** The same predicate is written in `HistorySessions.visibleSessions`
(`HistoryView.swift` line 65) and `OverviewView.recentSessions` (`OverviewView.swift` line 57), and
`HistorySessions` re-parses sizes that `Session.bytes` already provides.

**Change.** In `HistoryPresentation.swift` add to the `HistoryReport.Session` extension:

```swift
/// False for a logged session that touched nothing, which History leaves out.
var recordedWork: Bool { (items ?? 0) > 0 || (operationCount ?? 0) > 0 }
```

- `HistoryView.swift`: `guard session.recordedWork else { return false }`, and
  `let totalFreed = realSessions.map(\.bytes).saturatingSum`.
- `OverviewView.swift`: `.filter { !$0.isPreview && $0.recordedWork }`.

**Commit.** `Share History's test for a session that did work`

### 2.3 `Screen.tools` and the Go menu's shortcut

**Why.** `OverviewView.tools` re-lists nine of the ten `Screen` cases by hand, and
`BurrowCommands`' Go menu writes the same `Button` twice to add a shortcut to the first nine.

**Changes.**

`Screen.swift`:

```swift
/// Every page except the Overview, which is where they are listed.
static let tools = allCases.filter { $0 != .overview }

/// Command-1 through Command-9 for the first nine pages.
var goShortcut: KeyboardShortcut? {
    order < 9 ? KeyboardShortcut(KeyEquivalent(Character("\(order + 1)")), modifiers: .command) : nil
}
```

`OverviewView.swift`: delete `private let tools`, iterate `Screen.tools`.

`BurrowCommands.swift`, `CommandMenu("Go")`:

```swift
ForEach(Screen.allCases) { screen in
    Button(screen.title) { model.selection = screen }
        .keyboardShortcut(screen.goShortcut)
}
```

**Verify.** In the running app the Go menu shows ⌘1…⌘9 on the first nine pages and none on History,
and the Overview still shows nine tiles in the same order.

**Commit.** `Derive the tool list and Go shortcuts from Screen`

### 2.4 `LevelBar(part:of:)`

**Why.** `whole > 0 ? Double(part) / Double(whole) : 0` is written at four `LevelBar` call sites.

**Change.** In `Sources/Burrow/DesignSystem/NumberViews.swift`, add below `LevelBar`. It must be an
extension: an initializer written inside the struct would remove the memberwise one that the other
call sites use.

```swift
extension LevelBar {
    /// A bar showing `part` as a share of `whole`, empty when there's no whole to compare with.
    init(part: Int64, of whole: Int64, tint: Color = .accentColor, height: CGFloat = 6) {
        self.init(fraction: whole > 0 ? Double(part) / Double(whole) : 0, tint: tint, height: height)
    }
}
```

For example `LevelBar(part: item.bytes, of: largestBytes, height: 3)`. Use it at: `MenuItemRow` (`MenuFlowView.swift` ~188), `AppSizeColumn` (`UninstallView.swift` ~244),
`EntryRow` (`AnalyzeView.swift` ~300, keeps its `tint:`), and `CleanSectionHeader`
(`CleanView.swift` ~222; keep the surrounding `if section.bytes > 0, largestBytes > 0`).

**Commit.** `Give LevelBar a part-of-whole initializer`

### 2.5 One selection checkbox for both selectable lists

**Why.** `MenuItemRow` and `AppRow` both build
`Toggle("Select \(name)", isOn: Binding(get: { isSelected }, set: { _ in toggle() })).labelsHidden().toggleStyle(.checkbox)`.
The closure binding is deliberate (a click must also move keyboard focus and animate), so keep it,
but in exactly one place.

**Change.** New file `Sources/Burrow/DesignSystem/SelectionCheckbox.swift`:

```swift
import SwiftUI

/// The checkbox at the front of a selectable row. The whole row is clickable too, so the
/// checkbox reports the row's state and hands every change to the row's own toggle, which
/// also moves keyboard focus. That is why this is the one closure binding in the app.
struct SelectionCheckbox: View {
    let title: String
    let isSelected: Bool
    let toggle: () -> Void

    var body: some View {
        Toggle("Select \(title)", isOn: Binding(get: { isSelected }, set: { _ in toggle() }))
            .labelsHidden()
            .toggleStyle(.checkbox)
    }
}
```

Replace the two `Toggle(…)` blocks with
`SelectionCheckbox(title: item.name, isSelected: isSelected, toggle: toggle)` and
`SelectionCheckbox(title: app.name, isSelected: isSelected, toggle: toggle)`.

**Do not** merge `MenuItemRow` and `AppRow` themselves, and do not change `AppRow`'s inputs:
`docs/simplification.md` records that its stable inputs cut row evaluations from 14,400 to 239.
`SelectionCheckbox` is created *inside* those rows, so it doesn't affect that boundary.

**Commit.** `Share the selectable rows' checkbox`

### 2.6 Path and count helpers

**Why.** `(path as NSString).lastPathComponent` appears five times in the app target, and
`"\(n) \(n == 1 ? "item" : "items")"` three times in `AnalyzeModel`, while History already uses
automatic grammar agreement for the same phrase.

**Changes.**

`Sources/Burrow/DesignSystem/Theme.swift`, in the existing `extension String`:

```swift
/// The last component of a path, such as a file or volume name.
var lastPathComponent: String { (self as NSString).lastPathComponent }
```

Use it in `AppModel.swift` (line 227), `CleanModel.swift` (166), `CleanView.swift` (376, 404) and
`AnalyzeModel.swift` (16). Leave the `BurrowCore` uses alone.

Also in `Theme.swift`, beside the `Int64` size extension:

```swift
extension Int {
    /// "1 item", "1,974 items".
    var itemCount: AttributedString { AttributedString(localized: "^[\(self) item](inflect: true)") }
}
```

In `HistoryPresentation.swift`, `itemsText` becomes
`guard let items, items > 0 else { return nil }; return items.itemCount`.

In `AnalyzeModel.swift` replace the three hand-written plurals (in `trashSelection`, `moveToTrash`
and `restore`) with `String(count.itemCount.characters)`, for example
`"Moved \(String(moved.count.itemCount.characters)) to the Trash."`.

**Behavior change (tiny).** Counts of 1,000 or more in those three notices gain a grouping separator.

**Verify.** `AnalyzeModelTests` and `HistoryPresentationTests` pass. If any `AnalyzeModelTests`
expectation on a notice string fails, the output differs from before for small counts: fix the
helper, not the test.

**Commit.** `Share path-name and item-count wording`

### 2.7 Two types named `OutputBuffer`

**Why.** `Sources/Burrow/App/OutputBuffer.swift` (assembles lines, used by `OptimizeModel`) and the
private class in `Sources/BurrowCore/CLI/CommandRunner.swift` (accumulates bytes) share a name and do
different jobs.

**Change.** `git mv Sources/Burrow/App/OutputBuffer.swift Sources/Burrow/App/LineOutputBuffer.swift`,
rename the class to `LineOutputBuffer`, and update `OptimizeModel.preview` (line 40).

**Commit.** `Name the line-assembling buffer for what it does`

---

## Phase 3 — Closure bindings and view logic into models

Apple's guidance (and SwiftUI Pro's) is to project bindings from a property rather than build
`Binding(get:set:)` in a view: a closure binding allocates on every body evaluation and can't be
compared. For a no-argument projection the fix is a get/set computed property on the model. Each of
these also becomes unit-testable.

### 3.1 Disk Explorer's high-risk confirmation

**Files.** `AnalyzeModel.swift`, `AnalyzeView.swift`.

Add to `AnalyzeModel`, next to `pendingTrash`:

```swift
/// Whether the high-risk question is on screen. Dismissing it drops the question.
var isConfirmingTrash: Bool {
    get { pendingTrash != nil }
    set { if !newValue { pendingTrash = nil } }
}
```

In `AnalyzeView`: delete the `isConfirmingTrash` computed `Binding`, add `@Bindable var model = model`
as the first line of `body`, and pass `isPresented: $model.isConfirmingTrash`.

**Test.** In `AnalyzeModelTests`, in the existing test that produces a `pendingTrash`: expect
`isConfirmingTrash == true`, set it to `false`, expect `pendingTrash == nil`; setting it to `true`
with no pending question leaves `pendingTrash == nil`.

**Commit.** `Bind Disk Explorer's confirmation to the model`

### 3.2 External volume confirmation

**Files.** `CleanModel.swift`, `CleanView.swift` (`ExternalVolumeSheet`).

Add to `CleanModel`, next to `volumeAwaitingConfirmation`:

```swift
/// Whether the external-volume question is on screen. Dismissing it forgets the volume.
var isConfirmingExternalClean: Bool {
    get { volumeAwaitingConfirmation != nil }
    set { if !newValue { volumeAwaitingConfirmation = nil } }
}
```

In `ExternalVolumeSheet`: change `let model: CleanModel` to `@Bindable var model: CleanModel`, delete
the `isConfirming` computed `Binding`, and pass `isPresented: $model.isConfirmingExternalClean`.

**Test.** Extend the existing external-clean test in `DestructiveConfirmationTests` (or
`CleanProtectionTests`, whichever already calls `requestExternalClean`) the same way as 3.1.

**Commit.** `Bind the external volume confirmation to the model`

### 3.3 "Skip the Trash" asks before turning on

**Files.** `UninstallModel.swift`, `UninstallView.swift` (`UninstallOptionsMenu`).

Add to `UninstallModel`, next to `deletePermanently`:

```swift
/// The menu's Skip the Trash switch. Turning it on asks first, because it can't be undone.
var skipsTrash: Bool {
    get { deletePermanently }
    set {
        if newValue {
            isConfirmingPermanent = true
        } else {
            deletePermanently = false
        }
    }
}
```

In `UninstallOptionsMenu`: delete the `permanent` computed `Binding` and use
`Toggle("Skip the Trash…", isOn: $model.skipsTrash)`.

**Test.** In `UninstallModelTests`: setting `skipsTrash = true` leaves `deletePermanently == false`
and sets `isConfirmingPermanent == true`; with `deletePermanently = true`, setting
`skipsTrash = false` clears it.

**Commit.** `Bind Skip the Trash to the model`

### 3.4 A model for the Protected settings pane

**Why.** `ProtectedSettings` (`SettingsView.swift` lines 84–185) holds about fifty lines of loading,
validation, tilde expansion, saving and error handling inside a view, which is why
`docs/simplification.md` could only check it with a throwaway harness. `MaintenanceSettings` beside
it already has a tested model; this makes the two panes consistent.

**New file.** `Sources/Burrow/Features/Settings/ProtectedPathsModel.swift`:

```swift
import BurrowCore
import Foundation
import Observation

/// The Protected pane's list. Edits are refused in Preview Mode at the moment they run, not
/// when the control was drawn, because a file chooser can return after the mode has changed.
@MainActor
@Observable
final class ProtectedPathsModel {
    private(set) var patterns: [String] = []
    private(set) var usesDefaults = false
    private(set) var isLoaded = false
    var errorMessage: String?

    func load(from store: WhitelistStore) {
        usesDefaults = store.usesDefaults
        do {
            patterns = try store.load()
            isLoaded = true
        } catch {
            isLoaded = false
            errorMessage = error.localizedDescription
        }
    }

    /// Adds what was typed in the field, trimmed and with a leading `~/` expanded.
    /// Returns whether it was saved, so the field can keep text that wasn't.
    func addTyped(_ text: String, to store: WhitelistStore, home: String, isPreview: Bool) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        let expanded = trimmed.hasPrefix("~/") ? home + trimmed.dropFirst(1) : trimmed
        return add(expanded, to: store, isPreview: isPreview)
    }

    /// Adds a pattern exactly as given, such as a folder from the chooser.
    @discardableResult
    func add(_ pattern: String, to store: WhitelistStore, isPreview: Bool) -> Bool {
        guard isLoaded, !isPreview else { return false }
        do {
            try store.add(pattern)
            errorMessage = nil
            load(from: store)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// Returns whether the pattern was removed, so the selection can be cleared only then.
    @discardableResult
    func remove(_ pattern: String, from store: WhitelistStore, isPreview: Bool) -> Bool {
        guard isLoaded, !isPreview else { return false }
        do {
            try store.remove(pattern)
            load(from: store)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}
```

This is the view's current logic moved as it stands: typed text is trimmed and expanded, a chosen
folder is saved untouched, a successful load doesn't clear an earlier error, and a successful add does.

**`ProtectedSettings` after the change** keeps only presentation state:

- `@State private var model = ProtectedPathsModel()`, `@State private var newPattern = ""`,
  `@State private var selection: String?`.
- Remove `patterns`, `usesDefaults`, `isLoaded`, `errorMessage` state and the `reload`, `add` helper
  bodies; the view's actions become one-liners:
  - `reload()` → `model.load(from: store)`
  - `addTyped()` → `if model.addTyped(newPattern, to: store, home: AppModel.home, isPreview: app.effectivePreview) { newPattern = "" }`
  - `chooseFolder()` → `if let path = FilePicker.chooseFolder(prompt: "Protect") { model.add(path, to: store, isPreview: app.effectivePreview) }`
  - `removeSelected()` → `guard let selection else { return }; if model.remove(selection, from: store, isPreview: app.effectivePreview) { self.selection = nil }`
- `canEdit` becomes `model.isLoaded && !app.effectivePreview`; read `model.patterns`,
  `model.usesDefaults`, `model.errorMessage` in `body`. The dismiss closure of the error notice
  becomes `{ model.errorMessage = nil }`.
- Keep `private var store: WhitelistStore { … }` as is; after step 1.4 constructing it is free.

Every behavior must match the current view: a failed load leaves the list read-only and shows the
error; a failed add keeps the typed text; `isPreview` is evaluated when the action runs.

**Tests.** New file `Tests/BurrowTests/ProtectedPathsModelTests.swift`, using a throwaway home under
`TestScratch.root` and `WhitelistStore(home:cliRoot:)` with a fixture `lib/core/base.sh` containing a
`declare -a DEFAULT_WHITELIST_PATTERNS=(` block (see how `Tests/BurrowCoreTests` builds one). Cover:

1. Load with no file shows the defaults and `usesDefaults == true`.
2. `add` writes the file, reloads, returns `true`, and keeps the defaults.
3. `addTyped("  ~/Projects/keep ")` saves the trimmed, expanded path; `addTyped("   ")` returns `false`.
4. `addTyped("../x")` returns `false`, sets `errorMessage`, and writes nothing.
5. `add`, `addTyped` and `remove` with `isPreview: true` return `false` without writing.
6. A whitelist that is not UTF-8 makes `load` fail: `isLoaded == false`, and add/remove write nothing.
7. `remove` deletes exactly the given pattern and returns `true`.

**Commit.** `Give the Protected settings pane a tested model`

### 3.5 Move volume discovery out of the sheet

**Why.** `ExternalVolumeSheet.mountedVolumes()` is file-system work living in a view as a private
static.

**Change.** New file `Sources/Burrow/Features/Clean/ExternalVolumes.swift`:

```swift
import Foundation

/// The writable external volumes `mo clean --external` can work on.
enum ExternalVolumes {
    static func mounted() -> [String] { /* body of mountedVolumes(), unchanged */ }
}
```

In the sheet: `.onAppear { volumes = ExternalVolumes.mounted() }` and delete the static.

**Commit.** `Move external volume discovery out of the sheet`

---

## Phase 4 — Subview extraction

Both skills say the same thing: a section of a screen should be its own `View` struct, not a computed
`some View` property, because a computed property shares its parent's invalidation boundary. Only
three places break this in a way worth fixing. Small helpers reused inside one body
(`TreemapStage.outgoingLayer(in:)` and friends, `Sparkline.head`) are fine and stay.

### 4.1 `RunPanel.content`

**File.** `Sources/Burrow/Run/RunPanel.swift`.

Extract the `@ViewBuilder private var content`, `isFinished` and `showsLogByDefault` into a new view
in the same file for now (Phase 5 moves it):

```swift
/// What the panel shows in place of the terminal: the result, the log, or both.
struct RunPanelContent: View {
    let run: RunController
    @Binding var showsDetails: Bool

    var body: some View { /* the old `content` body, unchanged */ }

    private var isFinished: Bool { /* unchanged */ }
    private var showsLogByDefault: Bool { /* unchanged */ }
}
```

`RunPanel.body` uses `RunPanelContent(run: run, showsDetails: $showsDetails)` in the `else` branch.
`.animation(Motion.glide, value: showsDetails)` stays on `RunPanel`.

**Commit.** `Make the run panel's content its own view`

### 4.2 `CompletionView` → `CompletionHero` and `CompletionBanner`

**Why.** `CompletionView` is two unrelated layouts behind `isCompact`, written as `fullBody` and
`compactBody` computed properties. The four animation `@State` values and `celebrate()` belong only
to the full layout, but the compact one carries them too.

**Files.** `Sources/Burrow/Run/CompletionView.swift`, `RunPanel.swift` (after 4.1,
`RunPanelContent`).

1. New file `Sources/Burrow/Run/RunController+Completion.swift` holding the derived text and color as
   an extension, moved verbatim from `CompletionView`'s private properties and renamed:

   | Old (`CompletionView`) | New (`RunController`) |
   |---|---|
   | `symbol` | `completionSymbol: String` |
   | `tint` | `completionTint: Color` |
   | `headline` | `completionHeadline: String` |
   | `compactHeadline` | `completionBannerHeadline: String` |
   | `detail` | `completionDetail: String` |

   Replace `run.` with `self` access. The file imports `SwiftUI` (for `Color`) and `BurrowCore`.

2. In `CompletionView.swift`, replace `CompletionView` with two views:

   - `struct CompletionHero: View` — inputs `let run: RunController`,
     `@Binding var showsDetails: Bool`; owns `shownBytes`, `isDrawn`, `glow`, `landings` and
     `celebrate()`; its `body` is the old `fullBody` with `.onAppear(perform: celebrate)` attached to
     the outer `VStack`.
   - `struct CompletionBanner: View` — the same two inputs, no state; its `body` is the old
     `compactBody`.

   `LandingRipple` is unchanged.

3. In `RunPanelContent`: `CompletionView(run:showsDetails:)` → `CompletionHero(run:showsDetails:)`,
   and `CompletionView(run:showsDetails:isCompact: true)` → `CompletionBanner(run:showsDetails:)`.
   Keep each `.transition(Motion.materialize)`.

4. `git mv Sources/Burrow/Run/CompletionView.swift Sources/Burrow/Run/CompletionHero.swift`, and move
   `CompletionBanner` to `CompletionBanner.swift` and `LandingRipple` to `LandingRipple.swift`.

**Behavior.** Unchanged: the two call sites were already in different branches, so their identities
were already separate, and `celebrate()` only ever affected the full layout's state.

**Tests.** Add `Tests/BurrowTests/CompletionTextTests.swift` for the extension, driving a
`RunController` the way `RunControllerTests` does (a script that exits 0, one that exits 3, a
cancelled one): check `completionHeadline`, `completionSymbol` and `completionDetail` for success,
failure ("Couldn’t Finish", status in the detail) and cancel ("Stopped").

**Verify by eye.** Run a preview clean to completion: the checkmark draws, bounces once with one
ring, the byte count rolls up, and Show Details / Hide Details still switch between the two layouts.

**Commit.** `Split the completion view into its two layouts`

### 4.3 `AboutView.documentButton`

**File.** `Sources/Burrow/Features/About/AboutView.swift`.

Replace the `documentButton(_:file:)` and `localDocument(_:)` methods with a view (new file
`AboutDocumentButton.swift` in the same folder):

```swift
import SwiftUI

/// Reveals a bundled document such as the license in the Finder.
struct AboutDocumentButton: View {
    let title: LocalizedStringKey
    let file: String

    var body: some View {
        Button(title, action: reveal)
            .buttonStyle(.link)
            .font(.caption)
            .disabled(url == nil)
    }

    private var url: URL? { /* Bundle.main lookup, then the old localDocument fallback */ }

    private func reveal() {
        if let url { FilePicker.reveal(url.path) }
    }
}
```

Call sites: `AboutDocumentButton(title: "Show Notice in Finder", file: "NOTICE")` and the same for
`LICENSE`.

**Commit.** `Make About's document buttons a view`

---

## Phase 5 — File and folder structure

**Rule.** Every `View`, `ViewModifier`, `Shape`, `ButtonStyle`, `Commands`, `ToolbarContent`, model
and public type gets its own file, named after the type. A private *non-view* helper that exists only
to implement its file's main type may stay beside it (`ProcessBox`, `MasterDescriptor`, `ByteFormat`,
a keyframe `Values` struct nested in its view). Folders follow features.

**These steps are pure moves.** No logic, naming or formatting edits other than the renames listed
and dropping `private` on a moved type. Build and test after each step. If a move needs anything
else, stop.

Renames (private types whose bare names would be vague once internal). Apply each when you move it:

| Old | New |
|---|---|
| `TileView` | `TreemapTile` |
| `MapLayer` | `TreemapLayer` |
| `PathStep` | `AnalyzePathStep` |
| `EntryRow` / `EntryMenu` | `AnalyzeEntryRow` / `AnalyzeEntryMenu` |
| `CardTitle` / `ValueLine` / `PercentReadout` / `LiveDot` / `HealthStrip` | `StatusCardTitle` / `StatusValueLine` / `StatusPercentReadout` / `StatusLiveDot` / `StatusHealthStrip` |
| `AppRow` / `AppSizeColumn` | `UninstallAppRow` / `UninstallSizeColumn` |
| `SessionRow` | `HistorySessionRow` |
| `ToolTile` / `RecentActivity` / `RecentSessionRow` | `OverviewToolTile` / `OverviewRecentActivity` / `OverviewSessionRow` |
| `TerminalToggle` / `SheetControls` | `RunTerminalToggle` / `RunSheetControls` |

Everything else keeps its name.

### 5.1 `App/`

```
App/
  BurrowApp.swift              BurrowApp only
  AppDelegate.swift            AppDelegate
  Deadline.swift               finishes(within:_:)
  AppModel.swift  AppModel+Actions.swift  ExecutionPolicy.swift  PageAction.swift  Screen.swift
  CommandClient.swift  TrashClient.swift  FilePicker.swift  LineOutputBuffer.swift  DebugDriver.swift
  WindowVisibilityObserver.swift   VisibilityView.swift
  Commands/
    BurrowCommands.swift  ActionMenuItem.swift
  Root/
    RootView.swift  PageHost.swift  PageContent.swift  AppToolbar.swift
    PrimaryToolbarButton.swift  SecondaryToolbarButton.swift
    SidebarView.swift  SidebarRows.swift  SidebarRow.swift  MissingCLIView.swift
```

**Commit.** `Give the app shell one type per file`

### 5.2 `DesignSystem/`

```
DesignSystem/
  Theme.swift                  enum Theme only
  Color+Hex.swift              the NSColor and Color hex initializers
  Formatting.swift             the Int64 size extension, Int.itemCount and private enum ByteFormat
  String+Path.swift            abbreviatingHome, lastPathComponent
  Announcer.swift
  Motion/
    Motion.swift  View+Motion.swift (arrives, shake)  ArrivalState.swift
    ContentMotionEffect.swift  MaterializeEffect.swift  RiseEffect.swift  PageEffect.swift
    ShakeEffect.swift  ArrivalEffect.swift
  Components/
    Surface.swift  PointerGlow.swift  SurfaceButtonStyle.swift  SurfaceButtonBody.swift
    ToolIntro.swift  WorkingView.swift  InlineNotice.swift  NoticeBar.swift  FactTag.swift  GlassToast.swift
    HeroNumber.swift  CountingBytes.swift  LevelBar.swift  RingGauge.swift  SelectionCheckbox.swift
    Sparkline.swift  SparkShape.swift  StrataScene.swift  AnimatedGround.swift
```

While here, one two-line dedupe: `ArrivalState.isVisible(at:)` and `ArrivalEffect.isPartOfWave` both
hard-code `16`. Add `static let waveLimit = 16` to `ArrivalState` and use it in both.

Do **not** merge `InlineNotice` and `NoticeBar` (left alone on purpose).

**Commit.** `Give the design system one type per file`

### 5.3 `Run/`

```
Run/
  RunController.swift  RunController+Completion.swift  PromptRequest.swift
  RunPanel.swift  RunPanelContent.swift  RunTerminalToggle.swift  RunSheetControls.swift
  RunProgressHeader.swift  RunLogList.swift  HiddenLinesNote.swift
  LogFollowState.swift  LogViewport.swift  LogRow.swift  LogIcon.swift
  CompletionHero.swift  CompletionBanner.swift  LandingRipple.swift
  TerminalPanel.swift  TerminalCanvas.swift
  Prompts/
    PromptSheet.swift  PasswordPromptContent.swift  SystemCleanPromptContent.swift
    ConfirmPromptContent.swift  YesNoPromptContent.swift
```

**Commit.** `Give the run panel one type per file`

### 5.4 `Features/Status/`

```
Features/Status/
  StatusStore.swift  StatusTint.swift  StatusRate.swift (the bytesPerSecond helper)
  StatusView.swift  StatusDashboard.swift
  Cards/
    StatusHealthStrip.swift  CPUCard.swift  MemoryCard.swift  NetworkCard.swift  DiskCard.swift
    GPUCard.swift  PowerCard.swift  BluetoothCard.swift  ProcessCard.swift
  Components/
    StatusCardTitle.swift  StatusValueLine.swift  StatusPercentReadout.swift  StatusLiveDot.swift
    CoreBars.swift  RateTile.swift  DiskRow.swift  ProcessHeaderRow.swift  ProcessRow.swift
```

Two small tidy-ups that belong with this move:

- Move `DiskRow.tint` into `StatusTint` as `static func disk(_ percent: Double) -> Color` with the
  **same thresholds** (90 red, 75 orange), so every level color on the page is in one file.
- Turn the file-private free function `bytesPerSecond(_:)` into an internal one in `StatusRate.swift`
  with its name unchanged.

**Optional, only if asked:** narrow the inputs of the cards that don't change every sample, per
Apple's "pass views only the data they read": `DiskCard(disks:diskIO:trashSize:)`,
`GPUCard(gpu:)`, `PowerCard(battery:thermal:)`, `ProcessCard(processes:)`. The sub-structs are already
`Equatable`. At a two-second sampling interval the saving is small, so by this project's own rule it
needs a body-evaluation count (`let _ = Self._printChanges()` in a debug build) before it is kept.

**Commit.** `Split the Status page into cards and components`

### 5.5 `Features/Analyze/`

```
Features/Analyze/
  AnalyzeModel.swift  AnalyzeLevel.swift  TrashedBatch.swift
  AnalyzePresentation.swift  TrashConfirmation.swift  TrashUndoAction.swift
  AnalyzeView.swift  AnalyzePathBar.swift  AnalyzePathStep.swift  AnalyzeReadout.swift
  AnalyzeContent.swift  AnalyzeNotices.swift  AnalyzeEntryList.swift  AnalyzeEntryMenu.swift  AnalyzeEntryRow.swift
  Treemap/
    TreemapStage.swift  MapSnapshot.swift  ZoomPlate.swift  ZoomEffect.swift  TreemapLayer.swift
    MeasuringPlate.swift  TreemapTile.swift  TileFace.swift  SmallItemsTile.swift  TileLabel.swift
```

`AnalyzeModel` itself is **not** split (left alone on purpose). `TileFace` and `MapSnapshot` keep
their names because tests use them.

**Commit.** `Give Disk Explorer one type per file`

### 5.6 `Features/Clean/`, `Features/Menus/`, `Features/Uninstall/`

```
Features/Clean/
  CleanModel.swift  CleanPreviewStream.swift  ExternalVolumes.swift
  CleanView.swift  CleanIntro.swift  CleanReportView.swift  CleanTotalHeader.swift
  CleanSectionCard.swift  CleanSectionHeader.swift  CleanSectionDetails.swift  CleanPathRow.swift
  ExternalVolumeSheet.swift

Features/Menus/
  MenuFlowModel.swift  MenuFlowConfiguration.swift
  MenuFlowView.swift  MenuFlowIntro.swift  MenuFlowList.swift  MenuItemRow.swift  PurgePathsSheet.swift

Features/Uninstall/
  UninstallModel.swift  AppSizeClient.swift
  UninstallView.swift  UninstallList.swift  UninstallOptionsMenu.swift
  UninstallAppRow.swift  UninstallSizeColumn.swift  AppIconView.swift
```

**Commit.** `Give Clean, the menu flows and Uninstall one type per file`

### 5.7 `Features/History/`, `Overview/`, `Optimize/`, `Settings/`, `About/`

```
Features/History/
  HistoryModel.swift  HistoryPresentation.swift  HistoryDate.swift
  HistoryView.swift  HistorySessions.swift  HistorySessionRow.swift  HistoryFiles.swift  HistoryDeletionRow.swift

Features/Overview/
  OverviewView.swift  OverviewHero.swift  OverviewToolTile.swift  OverviewRecentActivity.swift  OverviewSessionRow.swift

Features/Optimize/
  OptimizeModel.swift  OptimizeView.swift  OptimizePlan.swift

Features/Settings/
  SettingsView.swift  SettingsPane.swift
  GeneralSettings.swift  ProtectedSettings.swift  ProtectedPathsModel.swift
  MaintenanceSettings.swift  MaintenanceSettingsModel.swift
  MoleSettings.swift  ManageModel.swift

Features/About/
  AboutView.swift  AboutLinkRow.swift  AboutDocumentButton.swift  AboutPanelController.swift  AboutWindowContent.swift
```

Notes:

- `HistoryDeletionRow` is the one extraction in this step that isn't a plain move: the `HStack` row
  written inline in `HistoryFiles`' `List(rows) { row in … }` becomes
  `struct HistoryDeletionRow: View { let row: HistoryReport.Deletion }` with the identical body, and
  the list becomes `List(rows) { HistoryDeletionRow(row: $0) }`.
- `ManageModel` moves from `Features/Manage/` to `Features/Settings/` and the `Manage` folder goes
  away. Its only view is `MoleSettings`, so a feature folder holding a lone model was misleading.
  `AppModel.manage` and the `"manage"` name in `DebugDriver` are unchanged.
- `OptimizePlan` keeps its nested private `PlanGroup`.

**Commit.** `Give the remaining features one type per file`

### 5.8 `BurrowCore/`

Public types only; private implementation helpers stay with their one user.

| From | Extract to |
|---|---|
| `CLI/CommandRunner.swift` | `CLI/CommandResult.swift`, `CLI/CommandError.swift` (keep `ProcessBox` and the private `OutputBuffer` in place) |
| `CLI/CLILocator.swift` | `CLI/CLIInfo.swift` |
| `CLI/MenuDriver.swift` | `CLI/MenuDriverError.swift` |
| `CLI/PTYSession.swift` | `CLI/PTYError.swift` (keep `MasterDescriptor` in place) |
| `CLI/ProcessLifecycle.swift` | `CLI/ChildExitWatcher.swift` (with `reapIfExited`), `CLI/ProcessRegistration.swift`. `ProcessLifecycle.finish(_:)` is `fileprivate` and called by `ProcessRegistration`: make it internal. |
| `Config/ConfigFile.swift` | `Config/ConfigError.swift` |
| `Layout/Treemap.swift` | `Layout/EntryMap.swift` |
| `Models/StatusSnapshot.swift` | `Parsing/NDJSONParser.swift` |
| `Parsing/MenuParser.swift` | `Parsing/MenuRow.swift`, `Parsing/MenuSnapshot.swift`, `Parsing/MenuItem.swift` |
| `Parsing/PromptDetector.swift` | `Parsing/CLIPrompt.swift` (the enum and its extension; `String.startsWithSpinner` stays) |
| `Parsing/UninstallPlan.swift` | `Parsing/UninstallTargeting.swift` |
| `System/GPUStatistics.swift` | `System/GPUReading.swift` |
| `Terminal/LineAssembler.swift` | `Terminal/AssembledLine.swift` |
| `Terminal/TerminalScreen.swift` | `Terminal/TerminalColor.swift`, `Terminal/CellStyle.swift`, `Terminal/TerminalCell.swift` |

`Safety/` is untouched. No public signature changes, so `BurrowCoreTests` needs no edits.

**Commit.** `Give BurrowCore's public types their own files`

### 5.9 Check the result

```bash
for f in $(git ls-files 'Sources/Burrow/*.swift'); do
  n=$(grep -cE '^(public |private |fileprivate |final |@MainActor |@Observable |@Animatable )*(struct|class|enum|actor) [A-Z]' "$f")
  [ "$n" -gt 1 ] && echo "$n $f"
done
```

Expected output: nothing. Nested types are indented, so they don't count; any file listed is a
missed move. (`BurrowCore` is not checked this way: `CommandRunner.swift` and `PTYSession.swift` keep
their private helpers on purpose.) Then run the full phase verification from rule 6.

---

## Phase 6 — Optional core hygiene (only if asked)

These are safe but touch the process layer, so they need the release suite every time.

### 6.1 `Mutex` instead of `NSLock` + `@unchecked Sendable` for the three simple buffers

`Synchronization.Mutex` (macOS 15+) lets the compiler check what `@unchecked Sendable` only promises.
Apply it only to the three classes whose entire state sits behind one lock:

- the private `OutputBuffer` in `BurrowCore/CLI/CommandRunner.swift`
- `LineOutputBuffer` in the app target
- `NDJSONParser` in `BurrowCore`

Shape:

```swift
import Synchronization

private final class OutputBuffer: Sendable {
    private let data = Mutex(Data())

    func append(_ chunk: Data) {
        data.withLock { $0.append(chunk) }
    }

    var text: String {
        data.withLock { String(decoding: $0, as: UTF8.self) }
    }
}
```

For the two with several fields, put them in a private `struct State` and hold `Mutex<State>`.

**Leave alone:** `ProcessBox`, `ProcessLifecycle`, `ProcessRegistration` (a `weak var` back-reference
plus lock ordering with `killpg`), `PTYSession`, `MasterDescriptor`, `ChildExitWatcher` (queue-confined
by design), `CleanPreviewStream` (FIFO ordering with a synchronous producer needs its serial queue),
and `OperationsLog` (left alone on purpose).

**Commit.** `Let the compiler check the three lock-only buffers`

### 6.2 One helper for C string arrays

`ProcessBox.start` and `PTYSession.init` both build `argv`/`envp` with `strdup`, append `nil`, and
free in a `defer`. A helper in `BurrowCore/CLI/CStringArray.swift`:

```swift
import Darwin

/// NULL-terminated copies of `strings` for a C `argv` or `envp`, freed when `body` returns.
func withCStringArray<Result>(
    _ strings: [String],
    _ body: ([UnsafeMutablePointer<CChar>?]) throws -> Result
) rethrows -> Result {
    var pointers: [UnsafeMutablePointer<CChar>?] = strings.map { strdup($0) }
    pointers.append(nil)
    defer { pointers.forEach { free($0) } }
    return try body(pointers)
}
```

Use it at both sites with the environment mapped to `"\($0.key)=\($0.value)"`. If the nested closures
read worse than the eight lines they replace at either site, drop this step: it is only worth doing
if the call sites get simpler.

**Commit.** `Share the C string array setup for spawning`

### 6.3 One source for the version number

`0.1.0` and build `1` are written in `project.yml`, in the `Info.plist` heredoc of
`scripts/build-app.sh`, and as fallbacks in `AboutView.appVersion`. Make `build-app.sh` read them from
`project.yml`:

```bash
version="$(awk -F'"' '/MARKETING_VERSION:/ { print $2 }' project.yml)"
build="$(awk -F'"' '/CURRENT_PROJECT_VERSION:/ { print $2 }' project.yml)"
[ -n "$version" ] && [ -n "$build" ] || { echo "Couldn't read the version from project.yml" >&2; exit 1; }
```

Change the heredoc delimiter from `<<'PLIST'` to `<<PLIST` and use `$version` / `$build` in the two
keys (nothing else in the heredoc contains `$` or a backtick; check before changing the delimiter).
Leave `AboutView`'s fallbacks, which only apply to `swift run`.

**Verify.** `scripts/build-app.sh release && plutil -p build/Burrow.app/Contents/Info.plist | grep -E "Version"`
shows `0.1.0` and `1`, and `codesign --verify --deep --strict build/Burrow.app` passes.

**Commit.** `Read the bundle version from project.yml`

---

## Phase 7 — Documentation

### 7.1 Record what was done

- `README.md`, "Sources layout" section (around line 196): the one-line descriptions stay true; add
  that each feature folder holds its models and one file per view.
- `docs/simplification.md`: add a dated section at the top, in the file's existing style, listing
  each change, the measurement for 1.3 (54.8 ms → 13.7 ms for 200 rows, formatter microbenchmark),
  the final test counts in debug and release, and what was verified by eye and what wasn't. Add to
  "Decisions": **one type per file for views, modifiers and models; private non-view helpers may stay
  beside their only user**, and **the row checkbox is the app's one closure binding**.
- `docs/design.md`: no change.

**Commit.** `Record the November refactor`

---

## 8. Definition of done

- [ ] `swift build` prints no warnings.
- [ ] `swift test` and `swift test -c release -Xswiftc -enable-testing` both pass, with more tests
      than the 308 baseline (new tests from 1.1, 1.3, 2.1, 3.1–3.4, 4.2).
- [ ] `scripts/build-app.sh release` succeeds and `codesign --verify --deep --strict build/Burrow.app` passes.
- [ ] `grep -rnE "Binding(\(get| \{)" Sources` finds exactly two results: `SelectionCheckbox.swift`
      and `MaintenanceSettings.swift`.
- [ ] `grep -rn "String(format:" Sources` finds only `OperationsLog.swift`.
- [ ] The check in 5.9 lists nothing unexpected.
- [ ] A manual pass in the built app with `BURROW_FORCE_PREVIEW=1`: every sidebar page opens; a
      preview clean runs to its completion screen; Show/Hide Details works; the Terminal toggle draws;
      Uninstall search finds an accented name; Settings → Protected loads; the Go menu shortcuts work.
- [ ] `git log --oneline` shows one commit per step and no merge commits. Nothing was pushed.

---

## 9. Reviewed and deliberately not changed

Do not "fix" these. Each was looked at in this review or is already settled in
`docs/simplification.md`.

**Settled in `docs/simplification.md` (do not reopen):**

- A shared stale-result / latest-task helper for the `loadID = UUID()` pattern in the models.
- A `PageFeature` protocol or any other way of shrinking `AppModel`'s exhaustive `switch`es.
- Unifying the Clean, Optimize, Menu and Uninstall state machines.
- Splitting `AnalyzeModel`, or adding a `RunLog` type.
- Merging `InlineNotice` and `NoticeBar`.
- Touching `TrashGuard` or `OperationsLog` beyond what Mole's source requires.
- An app-icon cache, disk-name caching, manual `Equatable` on rows, moving treemap selection into tiles.

**Reviewed now and left as is:**

- **The process layer's GCD** (`PTYSession`, `ProcessBox`, `ChildExitWatcher`, `CleanPreviewStream`).
  Dispatch sources and serial queues are the right tool for file-descriptor readiness, child exit and
  FIFO ordering from synchronous callbacks. "No GCD" is a rule for app-level concurrency, and the app
  level already follows it.
- **`WindowVisibilityObserver`'s Combine pipeline.** SwiftUI has no occlusion signal on macOS;
  `scenePhase` doesn't report it.
- **`Motion.isReduced` reading `NSWorkspace` instead of `@Environment(\.accessibilityReduceMotion)`.**
  It is the single policy point `docs/design.md` describes.
- **`alert(_:item:)` / `confirmationDialog(_:item:)`.** Apple's reference gives them macOS 27
  availability, and the deployment target is macOS 26. Phase 3's computed `Bool` properties are the
  right shape until the target moves.
- **`MaintenanceSettings.binding(for:)`.** Its setter checks Preview Mode and saves through the store
  in one step; there is no equivalent key-path binding without moving the store into the model. It is
  the second accepted closure binding.
- **`onTapGesture` on `MenuItemRow` and `AppRow`.** `docs/design.md` chose checkboxes with full-row
  clicks; the checkbox carries the accessible action and the keyboard path exists.
- **`GeometryReader` in `LevelBar`, `PointerGlow`, `TreemapStage` and `TreemapLayer`.** Each needs a
  size to compute a fill, a gradient center or a layout.
- **`TreemapStage`'s `if isZoomingIn { … } else { … }` layer ordering.** It changes structural
  identity when the direction flips, but only at the moment a new level arrives, and the zoom is
  visually tuned. Changing it to `zIndex` needs a recording to compare, not a refactor.
- **Fixed font sizes** (`.system(size: 30, …)` and similar). These are display figures on macOS,
  where there is no system Dynamic Type setting for third-party apps.
- **`CLIInfo.hasBundledTools` checking the disk on each read.** Two `stat` calls when a page changes,
  and a test relies on the live check.
- **`.font(.body.weight(.medium))` and `.callout.weight(.semibold)` in `AboutLinkRow`.** A deliberate
  weight, not a stand-in for bold.
- **`AboutPanelController` (an AppKit `NSPanel`).** A SwiftUI `Window` scene would add a Window-menu
  item and change what "last window closed" means for quitting. Worth doing only as a deliberate
  design change.
- **`TestScratch.swift` duplicated in both test targets.** Twelve lines; a shared test-support target
  would cost more than it saves.
- **Main-actor default isolation / upcoming-feature flags in `Package.swift`.** The code is already
  clean under Swift 6 strict concurrency; flipping the default would re-isolate every unannotated
  type in the app target for no gain.

**Out of scope, worth a separate decision by the owner:**

- **Localization.** Every user-facing string is an English `String` passed to `Text` verbatim, so the
  app cannot be translated as written. Moving to a String Catalog and `LocalizedStringResource` is a
  project of its own.
- **CI.** `.github/workflows/` is empty. A workflow running `swift test` in debug and release on a
  macOS 26+ runner would replace the manual checks the README describes.
- **A formatter or linter.** None is configured; adding one is a tooling decision.
