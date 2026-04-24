import SwiftUI

// MARK: - Habits list

struct HabitsListView: View {

    @Environment(HabitStore.self) private var store
    @State private var showAdd         = false
    @State private var editingHabit: Habit?  = nil
    @State private var showArchived    = false
    @State private var searchText      = ""
    @State private var filterComplete  = false
    @State private var graphEntries: [UUID: [Date: ContributionEntry]] = [:]
    @State private var streaks: [UUID: Int] = [:]
    @State private var todayCompletions: [UUID: Int] = [:]
    @State private var deleteTarget: Habit? = nil
    @State private var showDeleteAlert = false
    @State private var selectedHabit: Habit? = nil

    // MARK: Filtered list

    private var filteredHabits: [Habit] {
        var habits = store.activeHabits
        if !searchText.isEmpty {
            habits = habits.filter {
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                $0.emoji.contains(searchText)
            }
        }
        if filterComplete {
            let today = Calendar.current.startOfDay(for: Date())
            habits = habits.filter {
                $0.schedule.isDue(on: today) &&
                (todayCompletions[$0.id] ?? 0) < $0.targetCount
            }
        }
        return habits
    }

    var body: some View {
        NavigationStack {
            List {
                // Filter bar
                filterBar
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))

                // Active habits
                if filteredHabits.isEmpty {
                    emptySearch
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                } else {
                    ForEach(filteredHabits) { habit in
                        InteractiveHabitRow(
                            habit: habit,
                            entries: graphEntries[habit.id] ?? [:],
                            streak: streaks[habit.id] ?? 0,
                            completionCount: todayCompletions[habit.id] ?? 0,
                            onComplete: { toggleComplete(habit: habit) },
                            onEdit:     { editingHabit = habit },
                            onArchive:  {
                                try? store.archiveHabit(habit)
                                Task { await NotificationService.shared.cancel(for: habit) }
                            },
                            onDelete:   { deleteTarget = habit; showDeleteAlert = true }
                        )
                        // Tap anywhere on the row (outside the completion button) navigates.
                        // onTapGesture has lower priority than inner Buttons, so the
                        // completion circle still works independently.
                        .contentShape(Rectangle())
                        .onTapGesture { selectedHabit = habit }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                deleteTarget = habit; showDeleteAlert = true
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            .tint(.red)
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            Button { editingHabit = habit } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            .tint(.blue)
                        }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                    }
                }

                // Archived section
                if !store.archivedHabits.isEmpty {
                    Button {
                        withAnimation(.easeInOut(duration: 0.22)) { showArchived.toggle() }
                    } label: {
                        HStack {
                            Image(systemName: showArchived ? "chevron.down" : "chevron.right")
                                .imageScale(.small)
                                .foregroundStyle(.secondary)
                            Text("Archived (\(store.archivedHabits.count))")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 16, leading: 20, bottom: 4, trailing: 20))

                    if showArchived {
                        ForEach(store.archivedHabits) { habit in
                            ArchivedHabitRow(habit: habit) {
                                try? store.unarchiveHabit(habit)
                                Task { await refreshData() }
                            } onDelete: {
                                deleteTarget = habit; showDeleteAlert = true
                            }
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .navigationTitle("Habits")
            .navigationDestination(item: $selectedHabit) { habit in
                HabitStatsView(habit: habit)
            }
            .searchable(text: $searchText,
                        placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Search habits")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showAdd = true } label: {
                        Image(systemName: "plus")
                            .fontWeight(.semibold)
                    }
                }
            }
        }
        .sheet(isPresented: $showAdd)     { addSheet }
        .sheet(item: $editingHabit)       { habit in editSheet(for: habit) }
        .alert("Delete Habit?", isPresented: $showDeleteAlert, presenting: deleteTarget) { habit in
            Button("Delete", role: .destructive) {
                try? store.deleteHabit(habit)
                Task { await refreshData() }
            }
            Button("Cancel", role: .cancel) {}
        } message: { habit in
            Text("\"\(habit.name)\" and all its history will be permanently removed.")
        }
        .task { await refreshData() }
    }

    // MARK: - Filter bar

    private var filterBar: some View {
        HStack(spacing: 8) {
            FilterChip(
                label: "Incomplete today",
                icon: "circle",
                isOn: $filterComplete
            )
            Spacer()
            Text("\(store.activeHabits.count) habit\(store.activeHabits.count == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Empty search

    private var emptySearch: some View {
        VStack(spacing: 12) {
            Image(systemName: filterComplete ? "checkmark.circle" : "magnifyingglass")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
                .symbolRenderingMode(.hierarchical)
            Text(filterComplete ? "All caught up!" : "No results for \"\(searchText)\"")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    // MARK: - Sheets

    private var addSheet: some View {
        AddEditHabitView(
            onSave: { habit in
                try? store.addHabit(habit)
                showAdd = false
                Task {
                    await NotificationService.shared.requestPermission()
                    await NotificationService.shared.schedule(for: habit)
                    await refreshData()
                }
            },
            onCancel: { showAdd = false }
        )
    }

    private func editSheet(for habit: Habit) -> some View {
        AddEditHabitView(
            existingHabit: habit,
            onSave: { updated in
                try? store.updateHabit(updated)
                editingHabit = nil
                Task {
                    await NotificationService.shared.schedule(for: updated)
                    await refreshData()
                }
            },
            onCancel: { editingHabit = nil }
        )
    }

    // MARK: - Quick complete

    private func toggleComplete(habit: Habit) {
        let count = todayCompletions[habit.id] ?? 0
        do {
            if habit.targetCount == 1 {
                try store.setCompletion(habit: habit, on: Date(), count: count > 0 ? 0 : 1)
            } else {
                try store.setCompletion(habit: habit, on: Date(),
                                        count: count >= habit.targetCount ? 0 : count + 1)
            }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        } catch {}
        todayCompletions[habit.id] = (try? store.completion(for: habit, on: Date()))?.count ?? 0
    }

    // MARK: - Data loading

    private func refreshData() async {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let miniStart = cal.date(byAdding: .day, value: -83, to: today) ?? today

        var entries: [UUID: [Date: ContributionEntry]] = [:]
        var stks: [UUID: Int] = [:]
        var comps: [UUID: Int] = [:]

        for habit in store.activeHabits {
            let cs = (try? store.completions(for: habit, from: miniStart, to: today)) ?? []
            var map: [Date: ContributionEntry] = [:]
            for c in cs {
                map[c.date] = ContributionEntry(
                    intensity: HabitStore.intensityBucket(count: c.count, targetCount: habit.targetCount),
                    count: c.count
                )
            }
            entries[habit.id] = map
            stks[habit.id]    = (try? store.currentStreak(for: habit)) ?? 0
            comps[habit.id]   = (try? store.completion(for: habit, on: today))?.count ?? 0
        }

        graphEntries      = entries
        streaks           = stks
        todayCompletions  = comps
    }
}

// MARK: - Interactive habit row

private struct InteractiveHabitRow: View {

    let habit: Habit
    let entries: [Date: ContributionEntry]
    let streak: Int
    let completionCount: Int
    let onComplete: () -> Void
    let onEdit:     () -> Void
    let onArchive:  () -> Void
    let onDelete:   () -> Void

    @State private var pressed = false
    @Environment(\.colorScheme) private var scheme

    private var isDueToday: Bool {
        habit.schedule.isDue(on: Calendar.current.startOfDay(for: Date()))
    }
    private var isComplete: Bool { completionCount >= habit.targetCount }
    private var color: Color { Color(hex: habit.colorHex) }

    var body: some View {
        HStack(spacing: 12) {
            // Icon badge
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(color.opacity(isComplete ? 0.22 : 0.13))
                    .frame(width: 46, height: 46)
                HabitSymbolView(habit.emoji, color: color, size: .title3)
                    .opacity(isComplete ? 0.7 : 1.0)
            }

            // Name + meta
            VStack(alignment: .leading, spacing: 3) {
                Text(habit.name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(isComplete ? .secondary : .primary)
                    .strikethrough(isComplete, color: .secondary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    if streak > 1 {
                        Label("\(streak)", systemImage: "flame.fill")
                            .foregroundStyle(.orange)
                    }
                    if habit.targetCount > 1 && isDueToday {
                        Text("\(completionCount)/\(habit.targetCount)")
                            .foregroundStyle(isComplete ? color : .secondary)
                            .monospacedDigit()
                    } else {
                        Text(habit.schedule.displayName)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .font(.caption)
            }

            Spacer(minLength: 0)

            // Mini contribution graph
            MiniContributionGraph(
                entries: entries,
                colorHex: habit.colorHex,
                cellSize: 6,
                cellSpacing: 1.2,
                weeks: 10
            )
            .frame(width: 10 * 6 + 9 * 1.2)
            .accessibilityHidden(true)

            // Quick-complete button
            if isDueToday {
                Button(action: onComplete) {
                    ZStack {
                        Circle()
                            .fill(isComplete ? color : Color(UIColor.systemGray5))
                            .frame(width: 32, height: 32)
                        if isComplete {
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .animation(.spring(response: 0.28, dampingFraction: 0.6), value: isComplete)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isComplete ? "Mark incomplete" : "Mark complete")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(
            isComplete
                ? color.opacity(scheme == .dark ? 0.10 : 0.06)
                : Color(UIColor.secondarySystemBackground),
            in: RoundedRectangle(cornerRadius: 16)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(isComplete ? color.opacity(0.3) : Color.clear, lineWidth: 1)
        )
        .scaleEffect(pressed ? 0.97 : 1.0)
        .animation(.spring(response: 0.25), value: isComplete)
        .contextMenu {
            Button { onEdit()    } label: { Label("Edit",    systemImage: "pencil") }
            Button { onArchive() } label: { Label("Archive", systemImage: "archivebox") }
            Divider()
            Button(role: .destructive) { onDelete() } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity,
                            pressing: { p in withAnimation(.spring(response: 0.2)) { pressed = p } },
                            perform: {})
    }
}

// MARK: - Archived habit row

private struct ArchivedHabitRow: View {
    let habit: Habit
    let onRestore: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(hex: habit.colorHex).opacity(0.10))
                    .frame(width: 40, height: 40)
                HabitSymbolView(habit.emoji, color: Color(hex: habit.colorHex), size: .body)
                    .opacity(0.55)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(habit.name).font(.subheadline).foregroundStyle(.secondary)
                if let d = habit.archivedAt {
                    Text("Archived \(d.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
            Spacer()
            Button { onRestore() } label: {
                Text("Restore").font(.caption.weight(.medium))
            }
            .buttonStyle(.bordered)
            .tint(Color(hex: habit.colorHex))
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(UIColor.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        .opacity(0.7)
        .contextMenu {
            Button(role: .destructive) { onDelete() } label: {
                Label("Delete permanently", systemImage: "trash")
            }
        }
    }
}

// MARK: - Filter chip

private struct FilterChip: View {
    let label: String
    let icon: String
    @Binding var isOn: Bool

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.25)) { isOn.toggle() }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            Label(label, systemImage: isOn ? "checkmark.circle.fill" : icon)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    isOn ? Color.accentColor.opacity(0.15) : Color(UIColor.secondarySystemBackground),
                    in: Capsule()
                )
                .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
                .overlay(Capsule().strokeBorder(isOn ? Color.accentColor.opacity(0.4) : Color.clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    HabitsListView()
        .environment(HabitStore(context: MockData.previewContainer.mainContext))
        .modelContainer(MockData.previewContainer)
}
#endif
