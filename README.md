# HabitGrid

A native iOS app for tracking habits, medications, and daily mood — with GitHub-style contribution heatmaps for every metric.

## Features

**Habits**
- Binary and multi-count habits (e.g. "drink 8 glasses of water")
- Daily, weekdays, custom-day, and N×/week schedules
- Per-habit color and SF Symbol icon
- Streak tracking (current + longest)
- GitHub-style contribution graph — past year at a glance
- Long-press to log a partial count or add a note
- Drag-to-reorder, archive, and swipe-to-delete

**Medications**
- Scheduled doses (daily, weekdays, custom days) and as-needed (PRN)
- Multiple dose times per day
- Log exact time taken, skip, or undo a logged dose
- Inventory tracking with low-stock alerts
- Follow-up push notifications every 15 min (up to 2 hours) until a dose is acted on
- Tapping a medication notification opens the app directly to the LogTaken sheet
- Adherence rate, current streak, and contribution graph per medication

**Mood**
- One mood log per day (Rough → Great), with an optional note
- 7-day mood bar chart on the Today screen
- Mood history in Stats

**Stats**
- Combined contribution heatmap across all active habits
- Per-habit stats: streaks, 30/90/365-day completion rate, weekday breakdown, bar chart
- Per-medication stats: adherence rate, streak, heatmap

**Widgets**
- Small: completion ring showing habits done vs. total today
- Medium (checklist): ring + done/pending status for each of today's habits
- Medium (grid): 2-habit contribution grid for the last 14 days
- Large (grid): 4-habit contribution grid for the last 28 days
- Extra-large (grid): 6-habit contribution grid for the last 28 days (iPad)

**Settings**
- Light / Dark / System theme
- Week start day (Sunday or Monday)
- Notification permission management and reschedule-all shortcut
- Export to JSON / Import from JSON (habits + completions + medications)
- Reset all data

## Requirements

| Tool | Version |
|------|---------|
| Xcode | 16.4+ |
| iOS deployment target | 17.0 |
| macOS build machine | 15 (Sequoia)+ |
| Swift | 6.0 |

## Getting started

```bash
# 1. Clone and enter the directory
cd HabitGrid

# 2. (Optional) regenerate the Xcode project from project.yml
brew install xcodegen && xcodegen generate

# 3. Open in Xcode
open HabitGrid.xcodeproj
```

Select an iOS 17 simulator in the scheme menu and press **⌘R**.

On first launch in **DEBUG** mode the app auto-seeds habits, medications, and mood entries with realistic mock data so all graphs render immediately.

> **Schema migration:** If Xcode reports a `loadIssueModelContainer` crash after pulling new model changes, delete the app from the simulator (long-press → Delete App), clean the build folder (**⇧⌘K**), and run again. The DEBUG build automatically wipes and recreates the local store if migration fails.

## Architecture

```
HabitGrid/
├── App/
│   ├── HabitGridApp.swift      @main, ModelContainer setup, onboarding gate
│   ├── ContentView.swift       TabView (Today / Habits / Meds / Stats / Settings)
│   └── NotificationRouter.swift  @Observable router + UNUserNotificationCenterDelegate
│
├── Models/                     SwiftData @Model classes
│   ├── Habit.swift
│   ├── HabitCompletion.swift
│   ├── HabitSchedule.swift     Codable enum — decomposed to primitives for SwiftData
│   ├── Medication.swift
│   ├── MedicationDose.swift
│   ├── MedicationSchedule.swift
│   └── MoodEntry.swift
│
├── Services/
│   ├── HabitStore.swift        @Observable — all habit CRUD and analytics
│   ├── MedicationStore.swift   @Observable — all medication/dose CRUD and analytics
│   ├── NotificationService.swift  actor — local notification scheduling
│   └── MockData.swift          DEBUG seed data
│
├── Components/
│   ├── ContributionGraph.swift      Single-habit and multi-habit year heatmaps
│   ├── MiniContributionGraph.swift  Compact 12-week inline graph
│   ├── HabitCard.swift              Today-screen habit row
│   └── Color+Hex.swift             Color(hex:) initializer
│
├── Today/
│   ├── TodayView.swift
│   ├── TodayViewModel.swift
│   ├── MedicationTodaySection.swift  Pending/acted-on doses with take/skip/undo
│   └── MoodLogCard.swift
│
├── Habits/
│   ├── HabitsListView.swift
│   └── AddEditHabitView.swift
│
├── Medications/
│   ├── MedsListView.swift
│   ├── AddEditMedicationView.swift
│   ├── MedStatsView.swift
│   └── LogTakenSheet.swift     Time-picker sheet for logging exact taken time
│
├── Stats/
│   ├── StatsView.swift         Combined overview
│   └── HabitStatsView.swift
│
├── Settings/
│   └── SettingsView.swift
│
├── Info/
│   └── InfoView.swift
│
└── Onboarding/
    └── OnboardingView.swift

HabitGridWidget/
├── HabitGridWidget.swift       WidgetBundle — small, medium, large/XL grid views
└── WidgetDataProvider.swift    Reads shared App Group SwiftData store; WidgetSnapshot DTO
```

**Pattern:** MVVM-lite with `@Observable` stores. SwiftData is accessed only through `HabitStore` and `MedicationStore` — views hold no `@Query` references. This keeps previews simple and isolates persistence logic.

## Key design decisions

### Schedule enum decomposition
SwiftData cannot persist Codable enums with associated values (it inspects the property graph and crashes). `HabitSchedule` and `MedicationSchedule` are decomposed into plain scalar stored properties (`scheduleTypeRaw: String`, `scheduleCustomDays: [Int]`, etc.) and reconstructed via a computed `schedule` property so all call-sites remain unchanged.

### Notification budget
iOS allows 64 pending notification requests per app.

| Schedule | Requests per habit |
|----------|--------------------|
| `.daily` / `.timesPerWeek` | 1 |
| `.weekdays` | 5 |
| `.customDays(n)` | n (max 7) |

Medication follow-ups add 8 one-shot requests per pending dose (every 15 min for 2 hours). With many custom-day habits and multiple pending medication doses the cap can be reached; remaining requests are silently dropped.

### Notification deep-link routing
Tapping a medication notification navigates straight to the `LogTaken` sheet:

1. `NotificationService` embeds `medicationID` (and `doseID` for follow-up reminders) in `content.userInfo` when scheduling.
2. `AppNotificationDelegate` (`UNUserNotificationCenterDelegate`) is initialised as a **static property** of `HabitGridApp` so `UNUserNotificationCenter.current().delegate` is set before the first runloop tick — this is required for cold-launch notification taps to be delivered.
3. On tap, the delegate writes `medicationID` to `NotificationRouter` (an `@Observable` singleton in the SwiftUI environment).
4. `ContentView` observes the router and switches to the Today tab; `MedicationTodaySection` reacts and opens `LogTakenSheet` for the matching pending dose.

### Actor isolation and SwiftData safety
- `NotificationService` is an `actor`; all public methods are `async`.
- Model objects are never captured in unstructured `Task` closures after `context.save()`. Where notification cancellation requires dose identifiers post-save, UUIDs are extracted before the save and passed to primitive-based overloads (e.g. `cancelFollowUps(medicationID:doseID:)`).
- Unstructured tasks that need to access model properties are marked `@MainActor` to stay on the same thread as the `ModelContext`.

## ContributionGraph API

```swift
// Single-habit year graph
ContributionGraph(
    entries: [Date: ContributionEntry],   // intensity (0–4) + count per day
    colorHex: String,                     // 6-char hex, e.g. "34C759"
    cellSize: CGFloat = 11,
    cellSpacing: CGFloat = 2,
    cornerRadius: CGFloat = 2,
    weekStartsOnSunday: Bool = true
)

// Multi-habit blended year overview
MultiHabitContributionGraph(
    layers: [MultiHabitContributionGraph.Layer],   // [(colorHex, entries)]
    cellSize: CGFloat = 11,
    cellSpacing: CGFloat = 2,
    cornerRadius: CGFloat = 2,
    weekStartsOnSunday: Bool = true
)

// 12-week compact inline graph (used in list rows)
MiniContributionGraph(
    entries: [Date: ContributionEntry],
    colorHex: String,
    cellSize: CGFloat = 8,
    weeks: Int = 12
)
```

### Intensity buckets

| Bucket | Meaning |
|--------|---------|
| 0 | No activity |
| 1 | < 25 % of target |
| 2 | 25–49 % |
| 3 | 50–74 % |
| 4 | ≥ 75 % (full for binary habits) |

## HabitStore API

```swift
@Environment(HabitStore.self) private var store

// CRUD
store.addHabit(_:)
store.updateHabit(_:)
store.archiveHabit(_:)  /  store.unarchiveHabit(_:)
store.deleteHabit(_:)        // cascades to HabitCompletion records
store.reorder(habits:)

// Completions
store.markComplete(habit:on:count:note:)   // increments
store.setCompletion(habit:on:count:note:)  // overwrites; count 0 deletes record
store.deleteCompletion(habit:on:)

// Queries
store.completions(for:from:to:)  → [HabitCompletion]
store.completion(for:on:)        → HabitCompletion?

// Analytics
store.currentStreak(for:)         → Int
store.longestStreak(for:)         → Int
store.completionRate(for:days:)   → Double   // 0…1
store.weekdayBreakdown(for:days:) → [Int]    // index 0 = Sun … 6 = Sat
store.intensity(for:on:)          → Int      // 0…4

// Static — safe for previews, no context required
HabitStore.intensityBucket(count:targetCount:) → Int
```

## MedicationStore API

```swift
@Environment(MedicationStore.self) private var medStore

// CRUD
medStore.addMedication(_:)
medStore.updateMedication(_:)
medStore.archiveMedication(_:)  /  medStore.unarchiveMedication(_:)
medStore.deleteMedication(_:)        // cascades to MedicationDose records
medStore.reorder(medications:)

// Dose materialization (idempotent)
medStore.materializeDoses(for:through:)   // creates MedicationDose records up to a date

// Dose actions
medStore.markTaken(_:at:)         // records exact time, decrements inventory
medStore.markSkipped(_:)
medStore.resetToPending(_:)       // re-increments inventory if was taken
medStore.logPRNDose(for:at:)      // logs an as-needed dose

// Queries
medStore.doses(for:from:to:)   → [MedicationDose]
medStore.doses(on:)            → [MedicationDose]   // all statuses for a day
medStore.dosesDue(on:)         → [MedicationDose]   // pending only

// Analytics
medStore.adherenceRate(for:days:)             → Double   // 0…1
medStore.currentAdherenceStreak(for:)         → Int
medStore.longestAdherenceStreak(for:)         → Int
medStore.intensity(for:on:)                   → Int      // 0…4
medStore.overallIntensity(on:)                → Int      // across all active meds

// Maintenance
medStore.sweepMissed(asOf:)   // marks overdue pending doses as missed

// Static
MedicationStore.intensityBucket(taken:total:) → Int
```

## Localization

The app ships with English (`en`) and Spanish (`es`) string tables in `HabitGrid/en.lproj/` and `HabitGrid/es.lproj/`. All user-visible strings are keyed through `Localizable.strings`.

## Running tests

**⌘U** or _Product → Test_ in Xcode.

`HabitGridTests` uses an in-memory `ModelContainer` and covers:

- Intensity bucketing (binary + multi-count, all 5 buckets)
- Daily streak: consecutive, missed day, today grace period, weekday/custom-day schedules
- Longest streak vs. current streak
- Archived habit streak capped at archive date
- Weekly streak (`timesPerWeek`) met and broken
- Completion accumulation, overwrite, and count-0 delete
- Completion rate (100 % and 50 %)
- Cascade delete: removing a habit deletes its completions

## Known limitations

- **Notification cap:** With many custom-day habits and multiple pending medication doses, the iOS 64-request limit can be reached. Remaining requests are silently dropped.
- **iCloud sync is opt-in:** A toggle in Settings stores the preference, but the sync only takes effect after adding an active iCloud/CloudKit entitlement and restarting the app. Without an entitlement the app always uses a local SwiftData store.
- **Portrait only on iPhone:** The app is locked to portrait on iPhone. iPad supports all orientations.
- **No Apple Watch companion:** Habit and medication logging is iPhone-only.
