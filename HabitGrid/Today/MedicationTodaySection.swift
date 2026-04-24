import SwiftUI

// MARK: - Section

struct MedicationTodaySection: View {

    @Environment(MedicationStore.self) private var medStore
    @State private var pairs: [(med: Medication, dose: MedicationDose)] = []
    @State private var logEntry: (med: Medication, dose: MedicationDose)?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if !pairs.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Medications", systemImage: "pill.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 2)

                    ForEach(pairs, id: \.dose.id) { item in
                        DoseCard(
                            med: item.med,
                            dose: item.dose,
                            onTake: { logEntry = item },
                            onSkip: {
                                do {
                                    try medStore.markSkipped(item.dose)
                                    refresh()
                                } catch {
                                    errorMessage = error.localizedDescription
                                }
                            },
                            onUndo: {
                                do {
                                    try medStore.resetToPending(item.dose)
                                    refresh()
                                } catch {
                                    errorMessage = error.localizedDescription
                                }
                            }
                        )
                    }
                }
            }
        }
        .onAppear { refresh() }
        .alert("Could not update dose", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .sheet(isPresented: Binding(
            get: { logEntry != nil },
            set: { if !$0 { logEntry = nil } }
        )) {
            if let entry = logEntry {
                LogTakenSheet(
                    medName: entry.med.name,
                    scheduledAt: entry.dose.scheduledAt,
                    onLog: { time in
                        do {
                            try medStore.markTaken(entry.dose, at: time)
                            logEntry = nil
                            refresh()
                        } catch {
                            errorMessage = error.localizedDescription
                            logEntry = nil
                        }
                    },
                    onCancel: { logEntry = nil }
                )
            }
        }
    }

    private func refresh() {
        try? medStore.sweepMissed()
        let today = Calendar.current.startOfDay(for: Date())
        let map = Dictionary(uniqueKeysWithValues: medStore.activeMedications.map { ($0.id, $0) })
        // Show all of today's doses (pending + acted-on) so the user can undo mistakes
        let allToday = (try? medStore.doses(on: today)) ?? []
        pairs = allToday
            .compactMap { dose -> (med: Medication, dose: MedicationDose)? in
                guard let med = map[dose.medicationID] else { return nil }
                return (med: med, dose: dose)
            }
            .sorted { $0.dose.scheduledAt < $1.dose.scheduledAt }
    }
}

// MARK: - Dose card

private struct DoseCard: View {

    let med:    Medication
    let dose:   MedicationDose
    let onTake: () -> Void
    let onSkip: () -> Void
    let onUndo: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var medColor: Color { Color(hex: med.colorHex) }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        return f
    }()

    private var timeFmt: String { Self.timeFormatter.string(from: dose.scheduledAt) }

    var body: some View {
        HStack(spacing: 14) {
            // Icon badge
            ZStack {
                Circle()
                    .fill(medColor.opacity(0.14))
                    .frame(width: 44, height: 44)
                Image(systemName: med.emoji)
                    .font(.title3)
                    .foregroundStyle(medColor)
                    .symbolRenderingMode(.monochrome)
            }

            // Name + time
            VStack(alignment: .leading, spacing: 3) {
                Text(med.name)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                HStack(spacing: 4) {
                    if !med.strength.isEmpty {
                        Text(med.strength)
                        Text("·")
                    }
                    if dose.status == .taken, let takenAt = dose.takenAt {
                        Text("Taken at \(Self.timeFormatter.string(from: takenAt))")
                    } else {
                        Text(timeFmt)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if let count = med.pillCount {
                    HStack(spacing: 3) {
                        Image(systemName: count <= med.lowStockThreshold ? "exclamationmark.circle.fill" : "cross.circle.fill")
                            .font(.caption2)
                        Text("\(count) left")
                            .font(.caption2.weight(.medium))
                    }
                    .foregroundStyle(count <= med.lowStockThreshold ? Color.red : Color.secondary)
                }
            }

            Spacer(minLength: 0)

            // Action buttons
            if dose.status == .pending {
                HStack(spacing: 8) {
                    Button(action: onSkip) {
                        Image(systemName: "minus.circle.fill")
                            .font(.title2)
                            .foregroundStyle(Color(UIColor.systemGray3))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Skip")

                    Button(action: onTake) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(medColor)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Mark taken")
                }
            } else {
                HStack(spacing: 6) {
                    Image(systemName: dose.status.sfSymbol)
                        .font(.body)
                        .foregroundStyle(dose.status.tintColor)
                    Button(action: onUndo) {
                        Image(systemName: "arrow.uturn.backward.circle.fill")
                            .font(.title2)
                            .foregroundStyle(Color(UIColor.systemGray3))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Undo")
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color(UIColor.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(medColor.opacity(0.18), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(med.name), \(dose.status.label) at \(timeFmt)")
    }
}

// MARK: - Previews

#if DEBUG
#Preview {
    MedicationTodaySection()
        .environment(MedicationStore(context: MockData.previewContainer.mainContext))
        .modelContainer(MockData.previewContainer)
        .padding()
}
#endif
