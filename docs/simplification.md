# Simplification log

What has been simplified, what was measured, and what was deliberately left alone. Keep this current as work continues, so that the same ideas don't get tried twice.

## Refactor follow-up implementation

- **P1 Uninstall approval.** A disposable PTY reproduced both raw Return and a native Yes response reaching the child before validation. Guarded runs now show read-only Terminal output and validate the current request, full app plan and prompt count at approval. The launcher owns the default Trash mode and rejects option-like app names. All 23 focused Uninstall, targeting and Run Controller tests passed on macOS 27.3.
- **P1 Menu selection.** A fixture swapped two marks while leaving the selection count unchanged. The original driver accepted the selection. The driver now verifies live marks, paths when available, the visible rows and the final screen revision before Enter. The focused menu run reported 21 tests with eight host-only skips.
- **P1 CLI replacement.** A two-executable fixture showed that a stale Clean review could launch the replacement CLI. Accepted replacements now invalidate old reviews and inventory. Failed custom choices preserve the working CLI. Clean, Optimize and Uninstall check the review's source at launch. All 22 focused app coordination and confirmation tests passed.
- **P2 Pipe completion.** A command waits for its admitted output callbacks before returning. A descendant holding the pipe open yields an incomplete-output error after the drain deadline. All 16 focused process tests passed, including the slow callback and inherited-writer fixtures.
- **P2 Status stream.** Each attempt drains sample events in order before accounting for retries. Live status now expires when the current source goes quiet. The parser rejects unrecognized and oversized records and recovers at the next line. All 18 focused status and app coordination tests passed.

## Core hygiene follow-up — 12 November 2026

- **6.1. Checked sendability for three buffers.** Command output, assembled
  lines and status JSON each put their mutable state behind a
  `Synchronization.Mutex`. Debug and release each reported 320 tests, and the
  release bundle passed strict signature verification.
- **6.2. Shared spawn arguments.** The piped and PTY spawners use one helper
  to build and free their C argument and environment arrays. Debug and release
  each reported 320 tests, and the release bundle passed strict signature
  verification.
- **6.3. Bundle version from the project.** The bundle script reads the
  marketing and build versions from `project.yml`. A temporary fixture with
  a missing build number failed before compilation. Debug and release each
  reported 320 tests, and the signed release bundle reported version 0.1.0
  and build 1.

All three steps built without warnings and passed the debug and release
suites, with nine host-only tests skipped per run.

## November refactor — 12 November 2026

Implemented the required steps in [the refactor plan](refactor-plan.md) on
`refactor/review-2026-11`, starting from `d9dce44`. Each implementation step
has its own commit. The optional Phase 6 follow-up is recorded above.

- **Search, formatting and allocation.** Uninstall matches case and accents in
  app names and bundle IDs. Status numbers use locale-aware formatting. History
  shares its date parsers and display formatter. The review's optimized formatter
  microbenchmark for 200 rows went from 54.8 ms to 13.7 ms. A separate run with
  the committed code produced identical output. Whitelist defaults load on
  demand, and Terminal measures its cells and builds its palette once. Removed
  two placeholder About tests and made the planned API and style updates.
- **Shared presentation rules.** History uses Screen's command-to-page mapping
  and shares its work filter with Overview. Screen supplies the Overview tiles
  and Go shortcuts. The four relative bars use the same part-of-whole
  initializer. Both selectable lists use one checkbox. Path names and item counts
  share formatting, and the app's line-assembling buffer is named
  `LineOutputBuffer`.
- **Model-owned state and actions.** Disk Explorer and external-volume
  confirmations and Skip the Trash use model bindings. Protected settings has a
  tested model for loading and guarded edits. External volume discovery lives
  beside the Clean model.
- **View boundaries.** Run panel content, the completion hero and banner, and
  About's document buttons are separate views. Completion animation state lives
  on the hero. Tests cover completion text for success, failure and cancellation.
- **File layout.** Split the app shell, design system, Run panel, Status cards,
  Disk Explorer, remaining features and public core types. The arrival effect
  shares its wave limit with `ArrivalState`, disk thresholds live in
  `StatusTint`, and the History Files list uses a deletion row.
- **Test fixture.** A menu test intermittently read its result after the shell
  created the file and before it wrote the contents. The test now waits for the
  fixture command to exit before reading.

Debug and release each reported 320 tests across 39 app and 32 core suites
(134 app and 186 core), with nine host-only cases skipped by default. The build
was warning-free. The release bundle passed strict signature verification.
The file-move comparison accounted for every declaration and the planned small
edits. The source checks found only the two documented closure bindings and
the two locale-independent format calls in `OperationsLog`.

In the release app with `BURROW_FORCE_PREVIEW=1` and a disposable Mole fixture,
all ten pages opened and Command-1 through Command-9 reached their Go menu
destinations. A preview clean reached its result with the checkmark drawing and
the byte count rising to 12.3 MB. Show Details and Hide Details switched
layouts, Terminal showed the styled output and cursor, `cafe` matched Café, and
Protected loaded its defaults with edits disabled. Bounce and ripple timing
received source review. The check used macOS 27.3 and a fixture CLI.

Rapid accessibility and screenshot reads around completion intermittently
left the progress view visible after the command exited. The same symptom
reproduced on the pre-refactor release, and the ordinary Preview Mode workflow
completed on both builds. The refactor carries no speculative change for this
finding.

### Clean completion follow-up

Reproduced the stale progress pane on `main` at `162e1e4` with a disposable
Preview Mode command and rapid accessibility and screenshot reads. The toolbar
showed Done while the pane still showed “Previewing Cleanup 100%”. A separate
run showed the result while the toolbar still showed Cancel.

The controller now flushes the final output without animating it and publishes
the finished phase after the summary, progress and prompt state are ready.
The completion view still animates its result when it appears. Twelve runs
under polling reached both the result and Done. Show Details and Hide Details
worked, and the debug and release suites each reported 320 tests with nine
host-only skips.

## Follow-up review — 6 November 2026

Started from `5e9e7ad` with a clean working tree. The baseline passed all 278 tests
(107 app tests and 171 core tests), including the real CLI fixtures. Parallel reviews
covered the core engine, feature models and coordination, views and design system,
and packaging. The state-machine and safety decisions below still apply.

- **Menu path waits now propagate cancellation.** Swallowing sleep cancellation
  could busy-spin on the main actor until the 1.5-second path deadline, then return
  a successful read. The new fake-menu regression failed on the original code
  (1.29 seconds after cancellation and no cancellation error) and passes with the
  fix. It also checks that the cancelled read sends no selection or confirmation.
- **Terminal updates rebuild accessibility text once.** Assigning the terminal
  already refreshes its diagnostics; the representable no longer repeats the same
  screen-to-text conversion. The existing accessibility, selection, copy, and
  hidden-input regression passes.
- **Uninstall reload uses one sort.** Prior positions take precedence, with the
  existing name/ID comparator ordering new rows. Tests cover duplicate names,
  preserved positions, and the final size sort. In an optimized standalone
  benchmark with 80% of rows retained, sorting 200 apps fell from 1.208 ms to
  0.414 ms; 2,000 apps fell from 17.019 ms to 5.811 ms. These are medians of 17
  alternating samples with identical output IDs, measuring sorting only. Initial
  loads with no prior order improved about 6%; no whole-app speedup is claimed.
- **The bundle builder owns one temporary directory.** Both icon intermediates
  now share an `EXIT` cleanup, including the previously leaked asset-catalog
  plist. Shell syntax validation and a real debug bundle build passed; both icon
  formats, license files, plist validation, signature verification, and removal of
  the temporary directory were checked.
- **Menu errors describe reachable outcomes.** Removed the unused `commandExited`
  case: a command finishing before showing a menu is already reported by
  `waitForMenu` returning nil. The full debug suite passes, including real CLI
  menu tests.
- **Terminal styles are parsed once.** SGR sequences now go straight to their
  existing style parser after the prefix/intermediate-byte guards. Two bounded,
  alternating optimized benchmark runs improved a 6.12 MB styled stream by about
  10% (confirmation medians: 0.599 s to 0.539 s). Plain-text control medians were
  within 1.2% with overlapping ranges, so no plain-text speedup is claimed. Cell,
  style, cursor, and response digests matched across whole, 7-byte and single-byte
  chunks. The full debug suite, including terminal grammar regressions, passes.

Final validation on arm64 macOS 27.3, Swift 6.4.2, and Homebrew Mole 1.69.0:

- `swift test`: 281 tests passed (109 app, 172 core).
- `swift test -c release -Xswiftc -enable-testing`: the same 281 tests passed.
- `scripts/build-app.sh debug` and `scripts/build-app.sh release`: both passed.
  The final release bundle's signature, plist, icon assets, license files, and
  temporary-directory cleanup were verified.
- `git diff --check` passed. An independent review found no actionable regressions.
- Corrected the README's CI claim: this checkout contains no GitHub Actions
  workflow, so these checks were run locally.

The measurements above are isolated algorithm/parser benchmarks, not end-to-end
UI profiles. This pass did not repeat a manual UI/VoiceOver walkthrough or run on
the minimum supported macOS version. The three view candidates identified at that
stage were evaluated in the runtime follow-up below. The existing safety and
ownership rules remain in place.

## Runtime and boundary follow-up — 6 November 2026

Continued from `1dc98ed`, retaining the original simplification scope. This pass
tests the remaining view-update hypotheses and checks core boundary behavior.

- **Uninstall target matching normalizes names once.** The same candidate order,
  ambiguity checks, identity checks, and fallback spellings remain. With 600
  installed apps, optimized median matching time for 100 selected apps fell from
  100.6 ms to 2.3 ms; selecting all 600 fell from 597.9 ms to 10.1 ms. Selecting
  one app stayed about 1 ms. Eight alternating samples and differential fixtures
  covered case, Unicode, missing paths, collisions, duplicate identities, and
  repeated selections. The focused targeting regressions pass.
- **Log size rounding stays within integer bounds.** GB formatting and rounded-up
  KiB deletion sizes now use quotient/remainder arithmetic. Both original formulas
  trapped in standalone optimized probes at `Int64.max`; the replacement retains
  ordinary Mole-compatible formatting and supports saturated totals. New boundary
  tests cover negatives, rounding ties/carry, exact multiples, and maximum sizes.
  All 17 OperationsLog and targeting tests pass together in debug.
- **Status parser errors belong to the chunk that produced them.** The status
  store now consumes rejected-line counts after every feed, including a chunk
  containing a valid sample. Previously, that count could survive and report a
  spurious error during the next valid partial JSON line. A new observation-based
  regression detects the transient error on the original code and passes with
  the fix. The full debug suite passes all 287 tests.
- **Uninstall rows own their actions.** Rows receive stable model/focus inputs;
  the size column owns retry, and keyboard/row selection share the same model
  mutation. No manual `Equatable` rule or icon cache is needed. In an optimized
  instrumented 120-app fixture with a fixed largest size, row body evaluations
  during measurements fell from 14,400 to 239 and size-column evaluations from
  1,920 to 31. When every new result increased the maximum, relative size bars
  still updated across the list. Both final fixtures passed actual row, keyboard,
  hover, retry, search, and sort callback checks. The existing model test also
  verifies that selection keeps measurements from reordering rows underneath it.
- **Clean cards own their bindings and protection actions.** Each card receives
  stable model/CLI inputs and derives its expansion binding locally. With ten
  groups and 30 updates to one group, card and header body evaluations each fell
  from 300 to 30; the final report stayed identical. Final optimized fixtures
  exercised the rendered expand/collapse/reopen callbacks, protection against a
  temporary whitelist, and forced Preview's disabled protection/unchanged file.
  Both fixtures passed. Animation still reads Reduce Motion when the header is
  activated. No manual equality or additional cached report state was introduced.

These UI results count instrumented view-body evaluations, not frames or total
app speed. An Instruments trace pair contained no SwiftUI events and gave process
CPU averages of 58.8% and 60.4%; it does not establish a whole-app CPU improvement.
Native pointer/keyboard routing checks could not run because the Mac was locked;
the callback probes do not claim to replace them.

Final follow-up validation on the same arm64 macOS 27.3 / Swift 6.4.2 host:

- `swift test`: 287 tests passed (110 app, 177 core), including real CLI fixtures.
- `swift test -c release -Xswiftc -enable-testing`: the same 287 tests passed.
  Neither final test run reported compiler warnings or errors.
- `scripts/build-app.sh release` passed. Strict signature and plist validation,
  both icon formats, license files, and temporary-directory removal passed.
- Independent review found no actionable regressions. The production source and
  tests contain no temporary profiling hooks; all task-owned profiling apps exited.
- `git diff --check` passed. Each of the five follow-up improvements has its own
  focused commit, with this final validation recorded separately.

The follow-up evaluated all three remaining view candidates: Uninstall row inputs
and Clean card inputs improved measured update work; disk-name caching had no
demonstrated application benefit. The additional NDJSON experiment was also
discarded. Existing safety gates, state-machine boundaries, CLI compatibility,
and minimum deployment target remain unchanged. Native input/VoiceOver and the
minimum supported macOS version were not exercised in this follow-up. Further
implementation needs a new concrete finding rather than a speculative rewrite.

## Additional boundary and stream review — 6 November 2026

Continued from `3cc510b` with a clean working tree, checking the consumers of
saturated sizes and the remaining parsing and cancellation paths.

- **History owns its deletion-size conversion.** The view now reads an optional
  byte count from `HistoryReport.Deletion`, with checked multiplication preserving
  missing, ordinary, and signed values while saturating overflow. The old view
  trapped for the exact KiB value written when `OperationsLog` records
  `Int64.max`. A standalone optimized probe reproduced that crash, and regressions
  now cover the real log-to-history round trip and both signed bounds. The JSON
  decoding regressions pass.
- **The animated byte counter handles saturated totals.** Converting
  `Int64.max` to `Double` rounds up beyond the integer range. The counter now
  checks that endpoint before conversion, using the same bound as the size
  parser. An optimized probe reproduced the original trap; an ImageRenderer
  regression verifies the maximum-size rendering and preserves fractional
  truncation during animation. Both motion-rendering tests pass.
- **Line assembly decodes only control parameters it uses.** Erase and private
  mode sequences retain their exact parsing; ignored sequences such as SGR styles
  no longer create a discarded string. Two optimized runs, each with twelve
  alternating sample pairs, reduced line assembly for a 3.96 MB styled stream by
  about 11% (confirmation medians: 24.00 ms to 21.28 ms). Plain-text medians were
  within 0.5%, with overlapping ranges. Fifteen whole/fragmented differential
  fixtures matched lines, partial text, and alternate-screen state; the existing
  terminal regression suites pass. No end-to-end app speedup is claimed.
- **Cancellation ends native prompt presentation immediately.** The controller
  cancels its pending prompt check and refuses new prompts once cancelled, even
  while the child is still exiting. A harmless PTY fixture that ignores the first
  interrupt reproduced both a pending prompt and a previously visible prompt
  returning after Cancel. The regression controls child exit with a release file
  and schedules the pending debounce synchronously; both cases fail before the
  fix and pass after it. Eight prompt/controller tests pass. Process cancellation
  grace, escalation, and command output handling remain unchanged.
- **Shared config I/O preserves broken links and unreadable files.** A missing
  read now distinguishes a dangling file or parent link from an absent config;
  writes recheck readability before replacement. The original whitelist flow
  loaded defaults and replaced a broken link, whereas the installed Mole CLI
  refused it. Temporary-home probes and all 15 config tests now verify refused
  default/legacy fallback, preserved links and invalid UTF-8, ordinary writes,
  and creation under a valid linked directory. This is a preflight recheck, not
  an atomic guarantee against external filesystem changes. A separate bounded
  FIFO read probe returned an immediate Foundation refusal, so no additional
  file-type validation layer was added.

Final validation for these five focused improvements:

- `swift test`: 295 tests passed (112 app, 183 core), including real CLI fixtures.
- `swift test -c release -Xswiftc -enable-testing`: the same 295 tests passed.
  Both final runs completed without compiler warnings or errors.
- `scripts/build-app.sh release` passed. The release signature, plist, both icon
  formats, license files, and temporary-directory cleanup were verified.
- Independent review found no actionable regressions. `git diff --check` passed,
  and no task-owned probe or cancellation-fixture processes remained.

The rendering regressions use ImageRenderer and the cancellation regressions use
real temporary PTY commands; this pass did not repeat native pointer/keyboard or
VoiceOver walkthroughs, or test the minimum supported macOS version. The changes
add no dependencies or caches and retain the existing state-machine boundaries.

## Ownership and hot-path follow-up — 6 November 2026

Continued from `0f2108e` with a clean working tree.

- **Delayed checks no longer own completed processes.** Command timeouts and
  terminal cancellation grace checks now capture their owners weakly. Active
  process registrations still retain those owners until reap. Two regressions
  reproduced retention after completion with 60-second deadlines; no-timeout and
  zero-grace controls already released normally. Both now release promptly, and
  all 17 process/lifecycle tests pass, including timeout escalation, coordinated
  shutdown, 2,000 quick piped commands, and 200 quick terminals. This removes
  unnecessary retained state without changing timer deadlines or process signals.
- **Protection edits check policy when they execute.** Clean's model now checks
  its injected policy before writing; Settings' shared add action owns its edit
  check, and remove/Purge-save actions recheck their current eligibility. The
  redundant typed-add check was removed. Captured actions and a chooser returning
  after Preview was enabled previously wrote configuration despite the disabled
  UI. Live/forced Clean regressions fail before the fix and pass after it; all six
  related model tests pass. An extracted-action harness using real temporary
  config stores passes 11 checks for late Preview changes, failed loads, preserved
  typed input, and ordinary writes. Its UI/chooser shims do not test native event
  routing.
- **Log icons use one direct classification.** A first-character switch replaces
  the icon table and repeated prefix checks, keeping the existing trimming and
  title/detail parsing. Two optimized runs with ten alternating pairs each
  reduced construction time for 20,000 mixed-icon rows by about 9% (confirmation
  medians: 70.80 ms to 64.64 ms). Other row fixtures showed smaller, more variable
  gains. All 2,184 differential fixtures matched every parsed field, including
  variation selectors and combining marks. The full debug suite passes.
- **Terminal placement reuses the ASCII width it already knows.** Printable
  ASCII passes a width of one to the existing cell-placement routine; multibyte
  text still uses the same Unicode width calculation. This removes repeated
  Unicode inspection without adding a second renderer. Eight alternating
  optimized pairs and a four-pair confirmation reduced terminal parsing time by
  about 43% for styled output and 64% for plain output. Confirmation medians were
  0.535 s to 0.307 s for 6.12 MB styled, and 0.364 s to 0.131 s for 4.32 MB plain.
  A Unicode-heavy fixture containing ASCII also improved; Unicode width lookup
  itself is unchanged. Cell/style/cursor/reply digests matched for every timed
  stream and grammar fixtures split into whole, seven-byte, and single-byte
  chunks. The full debug suite passes. These are parser timings, not frame-rate
  or whole-app throughput measurements.
- **Backpressure tests wait for the state they verify.** The first full release
  run found an existing fixed-delay assumption: after 500 ms, the producer had
  buffered 63,496 of the expected 64,000 bytes. The test now waits for the limit
  with a five-second bound, retains both size assertions, and checks that the
  buffer then stays unchanged. A deferred stop also covers early test failure.
  No product backpressure behavior changed. The 19 related optimized process
  tests pass; weak-capture predicates keep the ownership regressions warning-free
  without requiring newer immutable-weak syntax.

Final validation after the test repair, on arm64 macOS 27.3 / Swift 6.4.2:

- `swift test`: 298 tests passed (113 app, 185 core), including real CLI fixtures.
- `swift test -c release -Xswiftc -enable-testing`: the same 298 tests passed.
  Both final confirmation runs completed without compiler warnings or errors.
- `scripts/build-app.sh release` passed. Strict signature and plist validation,
  both icon formats, license files, and temporary-directory cleanup passed.
- Independent review found no actionable regressions. `git diff --check` passed,
  and task-owned benchmark, rendering-fixture, and test commands had exited.

Native pointer/keyboard and VoiceOver walkthroughs, and the minimum supported
macOS version, were not exercised in this follow-up. No dependencies, caches,
new rendering paths, or deployment-target changes were introduced.

## Continuous simplification and optimization pass — 6 November 2026

Continued from `3504989` with a clean working tree.

- **Uninstall target matching resolves unique candidates in O(1).** Replaced the
  nested candidate-by-matcher filter with a single-pass occurrence map over all
  installed apps. Candidate names and folder names now perform O(1) dictionary
  lookups rather than rescanning all candidates across the entire app list.
  Exact ambiguity detection, duplicate identity handling, and folder fallback
  behavior are preserved. All 7 targeting unit tests and the CLI integration tests pass.
- **Prompt and locator regexes are compiled once.** Replaced `NSRegularExpression`
  runtime compilation and string bridging in `PromptDetector` with static Swift
  regex literals (`sudoPassword`, `yesNoPattern`, `confirmPattern`,
  `enterConfirmTrailing`), eliminating repeated pattern compilation during high-frequency
  terminal chunk processing. `TouchIDStatus` now classifies prefix status icons
  directly from its first character without regular expressions, and `CLILocator`
  precompiles its wrapper script regex. All 35 parsing and CLI integration tests pass.
- **Line assembly inspects byte parameters directly.** CSI erase sequences
  (`\e[K`, `\e[J`) are emitted frequently during command execution and progress
  updates. `LineAssembler.finishCSI` now checks byte parameters directly, avoiding
  UTF-8 string heap allocation on every clear sequence. Private mode toggles (`h`, `l`)
  guard on the `?` prefix byte before string decoding. All LineAssembler and
  shared escape grammar tests pass.
- **Path components in trash risk checks avoid string allocations.** Path
  classification in `TrashRisk` now operates directly on `Substring` slices from
  `split(separator: "/")` rather than allocating arrays of intermediate `String`
  objects for every component of every checked path. All 33 unit test cases pass.
- **Version components are extracted in a single pass.** `CLICompatibility.components`
  now extracts integer components in a single pass, avoiding multiple array maps,
  intermediate optional boxing, and separate emptiness/nil scans. All compatibility
  tests pass.
- **Optimize preview avoids redundant line assembly and memory buffering.**
  `OutputBuffer` now records assembled lines incrementally as stream chunks arrive.
  When the stream completes, completed lines are consumed directly without retaining
  raw `Data` in memory or performing a second full `LineAssembler` pass over the
  entire stream.

Final validation on arm64 macOS 27.3 / Swift 6.4.2:

- `swift test`: 185 tests in 32 suites passed (including real CLI fixtures).
- `swift test -c release -Xswiftc -enable-testing`: 185 tests in 32 suites passed.
- `scripts/build-app.sh debug` and `scripts/build-app.sh release`: both passed.
- Strict code signature verification (`codesign -vvv --deep --strict build/Burrow.app`) passed.
- `git diff --check` passed.

## How to measure

Optimized builds behave differently from debug ones, so measure with one that still has the scripted driver:

```bash
swift build -c release -Xswiftc -DDEBUG --scratch-path /tmp/burrow-perf --product Burrow
```

Point `BURROW_CLI` at a stand-in script that prints the output you want to test, run the app with `BURROW_FORCE_PREVIEW=1`, a throwaway `HOME` and `BURROW_STEPS`, then attach Time Profiler:

```bash
xcrun xctrace record --template "Time Profiler" --attach <pid> --time-limit 10s --output run.trace
```

Compare alternating runs of old and new, because other work on the Mac moves single runs by 20% or more.

## Measured results

Long command run, with the window visible. Times are until the command is reported finished.

| Lines printed | Before | After |
|---|---|---|
| 30,000 | 14–16 s | 3.5 s |
| 120,000 | More than 4 minutes, not finished | About 20 s |

| Operation | Before | After |
|---|---|---|
| Treemap layout | About 3,500 ms per benchmark | About 350 ms |
| Trim one output line | 2,300 ns | 38 ns |
| Read a 400-row menu screen | 2.5 ms | 0.33 ms |
| Assemble 2 MB of output into lines | 14.7 ms | 13.3 ms |
| Parse 2 MB of output into the screen | 161 ms | 161 ms |

Startup to a working page is about 0.45 s, and an idle window uses no measurable CPU. Neither needed work.

## What made the difference

- **Regex literals in functions are compiled on every call.** A literal such as `line.firstMatch(of: /…/)` builds and compiles the regex each time it runs. In code that runs per line, keep it in a `static let`.
- **`RunSummary` scanned every line on the main thread** when a command ended, which froze the app. It now reads closing lines only.
- **Long logs were mostly a regex problem, not a rendering one.** Animating scrolls less and combining terminal reads made no measurable difference, so neither was kept.
- **Walking `Data` byte by byte is slow.** `withUnsafeBytes` more than paid for the shared escape parser.

## Decisions

- **Use one type per file for views, modifiers and models.** Private non-view helpers may stay beside their only user.
- **The shared row checkbox is the only closure binding in a selectable row.** Maintenance Settings keeps the other closure binding to save through its Preview Mode guard.
- **`EntryMap` owns which entries get tiles.** The map and the zoom origin both use it, so they can't disagree.
- **`EscapeTokenizer` owns the escape grammar.** `TerminalScreen` and `LineAssembler` stay separate, because a cell grid and a stream of lines are different jobs, but they read the same sequences the same way.
- **`ChildExitWatcher` owns exit detection,** including why the system's exit event can't be relied on alone. Don't remove its timer: without it, about 1 in 100 quick commands is never noticed to have ended.
- **`AnalyzePresentation` is Disk Explorer's only copy of a folder,** and a log line carries its own raw text, so neither has a parallel store to keep in step.
- **Confirmation flags belong to the model they confirm,** and menu flows describe themselves in `MenuFlowConfiguration`.
- **CLI wording lives in `BurrowCore`.** Parsers and the text they match sit together, where tests can check them without a view model.
- **`AppModel` switches stay exhaustive.** Adding a page should be a compile error until it's handled everywhere.
- **Terminal parsing stays on the main actor.** `MenuDriver` verifies each key against the screen, and that depends on reading it in step.

## Left alone on purpose

- **The Clean, Optimize, Menu and Uninstall state machines.** They look alike but differ in substance: a coalesced stream, a menu driver, a plan check and size measurement.
- **A shared stale-result helper.** It would cost more lines than it saves, and every guard would remain.
- **`InlineNotice` and `NoticeBar`.** An uncapped notice pinned to a page edge blanks the window, so the height cap has to stay on one of them.
- **`TrashGuard` and `OperationsLog`.** Staying close to Mole's source makes them easier to compare against it.
- **The log row's rise animation.** Sharing `ContentMotionEffect` would add a `scaleEffect` to every row.
- **Reading Preview only from `ExecutionPolicy`.** Models and callers both check it, which looks redundant, but these gates guard destructive paths, and changing it would make a command preview rather than refuse if Preview flips while a question is open.
- **A `RunLog` type.** Removing `rawLines` got most of the benefit without adding a type. `RunController`'s prompts read terminal state directly, so splitting them would only add callbacks.
- **Splitting `AnalyzeModel`.** Trash and undo are tied into selection, the cache, loading and notices, so extracting them needs callbacks.
- **A `PageFeature` protocol.** It moves `AppModel`'s routing around without shrinking it. Exhaustive switches already catch a missed page.

## Measurements that did not justify more code

- **Changing only Clean's expansion binding.** A key-path binding alone still
  evaluated all ten cards on every streamed update. Stable card inputs were also
  needed, so the final change removes the changing action inputs too.
- **Manual equality for Uninstall rows.** An `Equatable` experiment reduced body
  evaluations but requires maintaining an equality contract around callbacks.
  Stable inputs achieve the needed isolation without that contract.
- **Disk-name caching.** On this Mac's only visible mounted volume (`/`), warmed
  `displayName(atPath:)` calls took 0.068–0.102 ms. First calls in fresh standalone
  processes took 52–70 ms, which also includes framework/service initialization.
  No hung, removable, or network volume was available to test. No cache or rename
  invalidation machinery was added without an observed app stall.
- **Discarding status JSON input once per chunk.** A cursor-based NDJSON parser
  matched chunk-boundary behavior, but eight alternating optimized samples showed
  less than 2% difference, with overlapping ranges, for bursts, individual lines,
  and fragmented lines. The existing parser stays unchanged.
- **Scanning scalars to test for an empty output line.** The replacement matched
  414 Unicode and chunk-boundary fixtures but did not improve styled output and
  was slower on plain output. Line assembly retains its existing whitespace trim.
- **Moving Treemap selection observation into each tile.** An optimized fixture
  with 96 entries and 32 rendered tiles exercised 40 actual selection callbacks.
  Those changes caused zero layout rebuilds and 79 tile-body evaluations (one
  initially, then the two changed tiles), with correct selected states throughout.
  SwiftUI already isolates those reads inside the existing `ForEach`, so no
  production rendering change was made.

Further changes should start from a new measurement or a concrete behavior problem.
