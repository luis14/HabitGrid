import SwiftUI

struct MedsListView: View {

    @Environment(MedicationStore.self) private var medStore
    @State private var showAdd  = false
    @State private var editMed: Medication? = nil
    @State private var logPRNConfirmation: Medication? = nil

    var body: some View {
        NavigationStack {
            Group {
                if medStore.activeMedications.isEmpty && medStore.archivedMedications.isEmpty {
                    emptyState
                } else {
                    medList
                }
            }
            .navigationTitle("Medications")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showAdd = true } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add medication")
                }
            }
        }
        .sheet(isPresented: $showAdd) {
            AddEditMedicationView(
                onSave: { med in
                    try? medStore.addMedication(med)
                    try? medStore.materializeDoses(for: med, through: Date())
                    Task { await NotificationService.shared.schedule(for: med) }
                    showAdd = false
                },
                onCancel: { showAdd = false }
            )
        }
        .sheet(item: $editMed) { med in
            AddEditMedicationView(
                existing: med,
                onSave: { updated in
                    try? medStore.updateMedication(updated)
                    try? medStore.materializeDoses(for: updated, through: Date())
                    Task { await NotificationService.shared.schedule(for: updated) }
                    editMed = nil
                },
                onCancel: { editMed = nil }
            )
        }
        .confirmationDialog(
            logPRNConfirmation.map { "Log dose for \($0.name)?" } ?? "",
            isPresented: Binding(
                get: { logPRNConfirmation != nil },
                set: { if !$0 { logPRNConfirmation = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let med = logPRNConfirmation {
                Button("Log Now") {
                    try? medStore.logPRNDose(for: med)
                    logPRNConfirmation = nil
                }
            }
            Button("Cancel", role: .cancel) { logPRNConfirmation = nil }
        }
    }

    // MARK: - List

    private var medList: some View {
        List {
            if !medStore.activeMedications.isEmpty {
                Section("Active") {
                    ForEach(medStore.activeMedications) { med in
                        NavigationLink {
                            MedStatsView(medication: med)
                        } label: {
                            MedRow(med: med)
                        }
                        .swipeActions(edge: .leading) {
                            if med.scheduleTypeRaw == "asNeeded" {
                                Button {
                                    logPRNConfirmation = med
                                } label: {
                                    Label("Log Dose", systemImage: "plus.circle.fill")
                                }
                                .tint(.green)
                            }
                            Button { editMed = med } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            .tint(.blue)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                // Capture primitives before deletion — the SwiftData
                                // backing data is cleared after context.save()
                                let id = med.id
                                let doseCount = med.dosesPerDay.count
                                try? medStore.deleteMedication(med)
                                Task { await NotificationService.shared.cancelMedication(id: id, doseCount: doseCount) }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            .tint(.red)

                            Button {
                                try? medStore.archiveMedication(med)
                                Task { await NotificationService.shared.cancel(for: med) }
                            } label: {
                                Label("Archive", systemImage: "archivebox")
                            }
                            .tint(.gray)
                        }
                    }
                    .onMove { from, to in
                        var sorted = medStore.activeMedications
                        sorted.move(fromOffsets: from, toOffset: to)
                        try? medStore.reorder(medications: sorted)
                    }
                }
            }

            if !medStore.archivedMedications.isEmpty {
                Section("Archived") {
                    ForEach(medStore.archivedMedications) { med in
                        MedRow(med: med, isArchived: true)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    try? medStore.deleteMedication(med)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }

                                Button {
                                    try? medStore.unarchiveMedication(med)
                                    Task { await NotificationService.shared.schedule(for: med) }
                                } label: {
                                    Label("Unarchive", systemImage: "arrow.uturn.up")
                                }
                                .tint(.blue)
                            }
                    }
                }
            }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "pills.fill")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
                .symbolRenderingMode(.hierarchical)
            Text("No medications")
                .font(.title3.weight(.semibold))
            Text("Tap + to track a prescription or supplement.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Add Medication") { showAdd = true }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

// MARK: - MedRow

struct MedRow: View {
    let med: Medication
    var isArchived: Bool = false

    private var medColor: Color { Color(hex: med.colorHex) }

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(medColor.opacity(isArchived ? 0.08 : 0.14))
                    .frame(width: 40, height: 40)
                Image(systemName: med.emoji)
                    .font(.title3)
                    .foregroundStyle(medColor.opacity(isArchived ? 0.5 : 1.0))
                    .symbolRenderingMode(.monochrome)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(med.name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(isArchived ? .secondary : .primary)
                HStack(spacing: 4) {
                    if !med.strength.isEmpty {
                        Text(med.strength)
                    }
                    Text("·")
                    Text(med.form.displayName)
                    Text("·")
                    Text(med.schedule.displayName)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

                if let count = med.pillCount, !isArchived {
                    HStack(spacing: 3) {
                        Image(systemName: count <= med.lowStockThreshold ? "exclamationmark.circle.fill" : "cross.circle.fill")
                            .font(.caption2)
                        Text("\(count) left")
                            .font(.caption2.weight(.medium))
                    }
                    .foregroundStyle(count <= med.lowStockThreshold ? Color.red : Color.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Previews

#if DEBUG
#Preview {
    MedsListView()
        .environment(MedicationStore(context: MockData.previewContainer.mainContext))
        .modelContainer(MockData.previewContainer)
}
#endif
