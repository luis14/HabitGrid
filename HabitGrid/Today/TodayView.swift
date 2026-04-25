import SwiftUI

// MARK: - Today View

struct TodayView: View {

    @Environment(HabitStore.self) private var store
    @State private var viewModel: TodayViewModel?
    @State private var sheet: SheetHabit? = nil

    var body: some View {
        NavigationStack {
            Group {
                if let vm = viewModel {
                    content(vm: vm)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("Today")
            .navigationBarTitleDisplayMode(.large)
            .toolbar { toolbarItems }
        }
        .alert("Could not save", isPresented: Binding(
            get: { viewModel?.error != nil },
            set: { if !$0 { viewModel?.error = nil } }
        )) {
            Button("OK", role: .cancel) { viewModel?.error = nil }
        } message: {
            Text(viewModel?.error ?? "")
        }
        // Sheet lives outside NavigationStack on a stable single-view anchor
        .sheet(item: $sheet) { item in
            CompletionSheet(
                habit: item.habit,
                initialCount: item.initialCount,
                initialNote: item.initialNote,
                onSave: { count, note in
                    viewModel?.save(habit: item.habit, count: count, note: note)
                    sheet = nil
                },
                onCancel: { sheet = nil }
            )
        }
        .onAppear {
            if viewModel == nil {
                viewModel = TodayViewModel(store: store)
            } else {
                viewModel?.refresh()
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private func content(vm: TodayViewModel) -> some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                if vm.totalToday > 0 {
                    progressHeader(vm: vm)
                }
                MoodLogCard()
                MedicationTodaySection()
                if vm.totalToday == 0 {
                    noHabitsNote
                } else {
                    habitList(vm: vm)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Progress header

    private func progressHeader(vm: TodayViewModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(dateString)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Group {
                        if vm.allDone {
                            Label("All done!", systemImage: "checkmark.seal.fill")
                                .foregroundStyle(.green)
                        } else {
                            Text("\(vm.completedToday) of \(vm.totalToday) habits")
                        }
                    }
                    .font(.headline)
                }
                Spacer()
                // Completion ring
                ZStack {
                    Circle()
                        .stroke(Color(UIColor.systemGray5), lineWidth: 5)
                    Circle()
                        .trim(from: 0, to: vm.progress)
                        .stroke(ringColor(vm: vm), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: vm.progress)
                    Text("\(Int(vm.progress * 100))%")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                }
                .frame(width: 50, height: 50)
            }

            // Linear progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(UIColor.systemGray5)).frame(height: 6)
                    Capsule()
                        .fill(barGradient(vm: vm))
                        .frame(width: geo.size.width * vm.progress, height: 6)
                        .animation(.spring(response: 0.5, dampingFraction: 0.75), value: vm.progress)
                }
            }
            .frame(height: 6)
        }
        .padding(16)
        .background(Color(UIColor.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
        .padding(.top, 8)
    }

    // MARK: - Habit list

    private func habitList(vm: TodayViewModel) -> some View {
        ForEach(vm.habitsForToday) { habit in
            HabitCard(
                habit: habit,
                completionCount: vm.currentCount(for: habit),
                streak: vm.streak(for: habit),
                onTap: {
                    vm.tap(habit: habit)
                },
                onLongPress: {
                    sheet = SheetHabit(
                        habit: habit,
                        initialCount: vm.currentCount(for: habit),
                        initialNote: ""
                    )
                }
            )
        }
    }

    // MARK: - No habits note (shown inline when nothing is due)

    private var noHabitsNote: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.seal")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("No habits due today")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            Text("Head to the Habits tab to add some.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 32)
    }

    // MARK: - Toolbar

    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                viewModel?.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .accessibilityLabel("Refresh")
        }
    }

    // MARK: - Helpers

    private static let dateFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMM d"
        return f
    }()

    private var dateString: String {
        Self.dateFmt.string(from: Date())
    }

    private func ringColor(vm: TodayViewModel) -> Color {
        vm.allDone ? .green : .accentColor
    }

    private func barGradient(vm: TodayViewModel) -> LinearGradient {
        LinearGradient(
            colors: vm.allDone ? [.green, .mint] : [.accentColor, .accentColor.opacity(0.7)],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

// MARK: - SheetHabit (sheet identification helper)

private struct SheetHabit: Identifiable {
    let id = UUID()
    let habit: Habit
    let initialCount: Int
    let initialNote: String
}

// MARK: - Completion Sheet (long-press)

private struct CompletionSheet: View {

    let habit: Habit
    let initialCount: Int
    let initialNote: String
    let onSave: (Int, String) -> Void
    let onCancel: () -> Void

    @State private var count: Int
    @State private var note: String
    @FocusState private var noteFocused: Bool

    init(habit: Habit, initialCount: Int, initialNote: String,
         onSave: @escaping (Int, String) -> Void, onCancel: @escaping () -> Void) {
        self.habit = habit
        self.initialCount = initialCount
        self.initialNote = initialNote
        self.onSave = onSave
        self.onCancel = onCancel
        _count = State(initialValue: initialCount)
        _note = State(initialValue: initialNote)
    }

    private var habitColor: Color { Color(hex: habit.colorHex) }

    var body: some View {
        NavigationStack {
            Form {
                // Habit header
                Section {
                    HStack(spacing: 12) {
                        HabitSymbolView(habit.emoji, color: Color(hex: habit.colorHex), size: .largeTitle)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(habit.name).font(.headline)
                            Text(habit.schedule.displayName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                // Count control
                Section {
                    if habit.targetCount > 1 {
                        Stepper(
                            value: $count,
                            in: 0 ... (habit.targetCount * 3),
                            step: 1
                        ) {
                            HStack {
                                Text("Count")
                                Spacer()
                                Text("\(count) / \(habit.targetCount)")
                                    .foregroundStyle(count >= habit.targetCount ? habitColor : .primary)
                                    .fontWeight(count >= habit.targetCount ? .semibold : .regular)
                                    .monospacedDigit()
                            }
                        }

                        // Inline mini progress bar
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color(UIColor.systemGray5)).frame(height: 5)
                                Capsule()
                                    .fill(habitColor)
                                    .frame(
                                        width: geo.size.width * min(1, Double(count) / Double(habit.targetCount)),
                                        height: 5
                                    )
                                    .animation(.spring(response: 0.3), value: count)
                            }
                        }
                        .frame(height: 5)
                        .listRowSeparator(.hidden)

                    } else {
                        Toggle("Completed", isOn: Binding(
                            get: { count > 0 },
                            set: { count = $0 ? 1 : 0 }
                        ))
                        .tint(habitColor)
                    }
                } header: {
                    Text("Completion")
                }

                // Note
                Section {
                    TextField("How did it go?", text: $note, axis: .vertical)
                        .lineLimit(3...8)
                        .focused($noteFocused)
                } header: {
                    Text("Note (optional)")
                }
            }
            .navigationTitle("Log Completion")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave(count, note) }
                        .fontWeight(.semibold)
                        .disabled(count == initialCount && note == initialNote)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Today tab — with habits") {
    TodayView()
        .environment(HabitStore(context: MockData.previewContainer.mainContext))
        .environment(MedicationStore(context: MockData.previewContainer.mainContext))
        .modelContainer(MockData.previewContainer)
}

#Preview("Today tab — all done") {
    let container = MockData.previewContainer
    let store = HabitStore(context: container.mainContext)
    let today = Date()
    for habit in store.activeHabits where habit.schedule.isDue(on: today) {
        try? store.markComplete(habit: habit, on: today, count: habit.targetCount)
    }
    return TodayView()
        .environment(store)
        .environment(MedicationStore(context: container.mainContext))
        .modelContainer(container)
}

#Preview("Completion sheet — multi-count") {
    let habit = Habit(name: "Water", emoji: "💧", colorHex: "5AC8FA",
                      schedule: .daily, targetCount: 8)
    return CompletionSheet(
        habit: habit,
        initialCount: 3,
        initialNote: "",
        onSave: { _, _ in },
        onCancel: {}
    )
}
#endif
