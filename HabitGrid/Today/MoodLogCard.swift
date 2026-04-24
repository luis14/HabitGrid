import SwiftUI
import SwiftData

// MARK: - Sheet mode

private enum MoodSheetMode: Identifiable {
    case create(MoodLevel)
    case edit(MoodEntry)
    var id: String {
        switch self {
        case .create(let m): return "new-\(m.rawValue)"
        case .edit(let e):   return e.id.uuidString
        }
    }
}

// MARK: - Mood log card (shown on the Today tab)

struct MoodLogCard: View {

    @Environment(\.modelContext) private var modelContext
    @State private var todayEntries: [MoodEntry] = []
    @State private var sheetMode: MoodSheetMode?

    private var averageLevel: MoodLevel? {
        guard !todayEntries.isEmpty else { return nil }
        let sum = todayEntries.map(\.levelRaw).reduce(0, +)
        let avg = Int((Double(sum) / Double(todayEntries.count)).rounded(.toNearestOrAwayFromZero))
        return MoodLevel(rawValue: max(1, min(5, avg)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Mood", systemImage: "sun.and.horizon.fill")
                .font(.headline)
                .foregroundStyle(.primary)
                .symbolRenderingMode(.hierarchical)

            moodPickerRow

            if !todayEntries.isEmpty {
                Divider().padding(.vertical, 2)
                todayLogsSection
            }
        }
        .padding(16)
        .background(Color(UIColor.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
        .onAppear { loadToday() }
        .sheet(item: $sheetMode) { mode in
            switch mode {
            case .create(let mood):
                MoodEntrySheet(
                    initialMood: mood,
                    onSave: { level, note in
                        insert(level: level, note: note)
                        sheetMode = nil
                    },
                    onCancel: { sheetMode = nil }
                )
            case .edit(let entry):
                MoodEntrySheet(
                    initialMood: entry.level,
                    initialNote: entry.note ?? "",
                    onSave: { level, note in
                        entry.level = level
                        entry.note  = note.isEmpty ? nil : note
                        try? modelContext.save()
                        loadToday()
                        sheetMode = nil
                    },
                    onDelete: {
                        modelContext.delete(entry)
                        try? modelContext.save()
                        loadToday()
                        sheetMode = nil
                    },
                    onCancel: { sheetMode = nil }
                )
            }
        }
    }

    // MARK: - Mood picker (always visible)

    private var moodPickerRow: some View {
        HStack(spacing: 6) {
            ForEach(MoodLevel.allCases) { mood in
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    sheetMode = .create(mood)
                } label: {
                    VStack(spacing: 6) {
                        ZStack {
                            Circle()
                                .fill(mood.color.opacity(0.14))
                                .frame(width: 48, height: 48)
                            moodIcon(mood, size: 20)
                        }
                        Text(mood.label)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Today's logs

    private var todayLogsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let avg = averageLevel {
                HStack(spacing: 6) {
                    moodIcon(avg, size: 13)
                    Text(todayEntries.count == 1
                         ? "Feeling \(avg.label.lowercased()) today"
                         : "Daily avg: \(avg.label.lowercased())")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(avg.color)
                    Text("· \(todayEntries.count) log\(todayEntries.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
            }

            ForEach(todayEntries) { entry in
                entryRow(entry)
            }
        }
    }

    private func entryRow(_ entry: MoodEntry) -> some View {
        Button { sheetMode = .edit(entry) } label: {
            HStack(spacing: 8) {
                moodIcon(entry.level, size: 12)
                    .frame(width: 18)
                Text(entry.level.label)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(entry.level.iconColor)
                if let note = entry.note, !note.isEmpty {
                    Text("· \(note)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Text(entry.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Image(systemName: "pencil")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Icon helper

    func moodIcon(_ mood: MoodLevel, size: CGFloat) -> some View {
        Image(systemName: mood.sfSymbol)
            .font(.system(size: size, weight: .medium))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(mood.iconColor)
    }

    // MARK: - Data

    private func loadToday() {
        let day = Calendar.current.startOfDay(for: Date())
        let descriptor = FetchDescriptor<MoodEntry>(
            predicate: #Predicate { $0.date == day },
            sortBy: [SortDescriptor(\.timestamp)]
        )
        todayEntries = (try? modelContext.fetch(descriptor)) ?? []
    }

    private func insert(level: MoodLevel, note: String?) {
        modelContext.insert(MoodEntry(date: Date(), level: level, note: note))
        try? modelContext.save()
        loadToday()
    }
}

// MARK: - Unified mood entry sheet (create + edit)

private struct MoodEntrySheet: View {
    @State private var selectedMood: MoodLevel
    @State private var note: String
    let onSave: (MoodLevel, String) -> Void
    let onDelete: (() -> Void)?
    let onCancel: () -> Void
    @FocusState private var focused: Bool
    @State private var showDeleteConfirm = false
    private let isEditing: Bool

    init(initialMood: MoodLevel,
         initialNote: String = "",
         onSave: @escaping (MoodLevel, String) -> Void,
         onDelete: (() -> Void)? = nil,
         onCancel: @escaping () -> Void) {
        _selectedMood = State(initialValue: initialMood)
        _note         = State(initialValue: initialNote)
        self.onSave   = onSave
        self.onDelete = onDelete
        self.onCancel = onCancel
        self.isEditing = onDelete != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("How are you feeling?") {
                    HStack(spacing: 0) {
                        ForEach(MoodLevel.allCases) { mood in
                            moodButton(mood)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Note (optional)") {
                    TextField("What's on your mind?", text: $note, axis: .vertical)
                        .lineLimit(4...10)
                        .focused($focused)
                }

                if isEditing {
                    Section {
                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            HStack {
                                Spacer()
                                Label("Delete Entry", systemImage: "trash")
                                Spacer()
                            }
                        }
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Entry" : "Log Mood")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave(selectedMood, note) }
                        .fontWeight(.semibold)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
            }
            .onAppear { if !isEditing { focused = true } }
            .confirmationDialog("Delete this mood entry?",
                                isPresented: $showDeleteConfirm,
                                titleVisibility: .visible) {
                Button("Delete", role: .destructive) { onDelete?() }
                Button("Cancel", role: .cancel) {}
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func moodButton(_ mood: MoodLevel) -> some View {
        Button {
            withAnimation(.spring(response: 0.25)) { selectedMood = mood }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            VStack(spacing: 4) {
                ZStack {
                    Circle()
                        .fill(mood == selectedMood
                              ? mood.color.opacity(0.18)
                              : Color(UIColor.tertiarySystemBackground))
                        .frame(width: 44, height: 44)
                        .overlay(
                            Circle().strokeBorder(
                                mood == selectedMood ? mood.color.opacity(0.5) : Color.clear,
                                lineWidth: 1.5
                            )
                        )
                    Image(systemName: mood.sfSymbol)
                        .font(.system(size: 18, weight: .medium))
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(mood.iconColor)
                }
                Text(mood.label)
                    .font(.system(size: 9, weight: mood == selectedMood ? .semibold : .regular))
                    .foregroundStyle(mood == selectedMood ? mood.color : .secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    MoodLogCard()
        .padding()
        .modelContainer(MockData.previewContainer)
}
#endif
