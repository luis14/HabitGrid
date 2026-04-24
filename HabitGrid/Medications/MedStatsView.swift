import SwiftUI
import SwiftData

struct MedStatsView: View {

    let medication: Medication
    @Environment(MedicationStore.self) private var medStore
    @Environment(\.modelContext) private var modelContext

    @State private var entries:    [Date: ContributionEntry] = [:]
    @State private var streak:     Int    = 0
    @State private var longest:    Int    = 0
    @State private var adherence:  Double = 0
    @State private var totalTaken: Int    = 0
    @State private var todayDoses: [MedicationDose] = []
    @State private var doseToLog: MedicationDose?
    @State private var errorMessage: String?

    private var medColor: Color { Color(hex: medication.colorHex) }
    private var isPRN: Bool { medication.scheduleTypeRaw == "asNeeded" }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                headerCard
                todaySection
                graphSection
                statsRow
                detailsSection
            }
            .padding(.bottom, 32)
        }
        .navigationTitle(medication.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 8) {
                    Image(systemName: medication.emoji)
                        .font(.headline)
                        .foregroundStyle(medColor)
                        .symbolRenderingMode(.monochrome)
                    Text(medication.name).font(.headline)
                }
            }
        }
        .task { await loadStats() }
        .alert("Could not update dose", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .sheet(item: $doseToLog) { dose in
            LogTakenSheet(
                medName: medication.name,
                scheduledAt: dose.scheduledAt,
                onLog: { time in
                    do {
                        try medStore.markTaken(dose, at: time)
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                    doseToLog = nil
                    Task { @MainActor in await loadStats() }
                },
                onCancel: { doseToLog = nil }
            )
        }
    }

    // MARK: - Today section

    private var todaySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Today")
                .font(.headline)
                .padding(.horizontal, 16)

            if isPRN {
                prnLogButton
            } else if todayDoses.isEmpty {
                Text("No doses scheduled for today.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
            } else {
                VStack(spacing: 10) {
                    ForEach(todayDoses) { dose in
                        doseRow(dose)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private var prnLogButton: some View {
        Button {
            try? medStore.logPRNDose(for: medication)
            Task { @MainActor in await loadStats() }
        } label: {
            Label("Log Dose Now", systemImage: "plus.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(medColor, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
    }

    private func doseRow(_ dose: MedicationDose) -> some View {
        HStack(spacing: 14) {
            // Status icon
            Image(systemName: dose.status.sfSymbol)
                .font(.title3)
                .foregroundStyle(dose.status.tintColor)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(Self.timeFmt.string(from: dose.scheduledAt))
                    .font(.body.weight(.medium))
                if dose.status == .taken, let takenAt = dose.takenAt {
                    Text("Taken at \(Self.timeFmt.string(from: takenAt))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(dose.status.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if dose.status == .pending {
                HStack(spacing: 10) {
                    Button {
                        do { try medStore.markSkipped(dose) } catch { errorMessage = error.localizedDescription }
                        refreshToday()
                        Task { @MainActor in await loadStats() }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.title2)
                            .foregroundStyle(Color(UIColor.systemGray3))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Skip")

                    Button {
                        doseToLog = dose
                    } label: {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(medColor)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Mark taken")
                }
            } else {
                Button {
                    do { try medStore.resetToPending(dose) } catch { errorMessage = error.localizedDescription }
                    refreshToday()
                    Task { @MainActor in await loadStats() }
                } label: {
                    Image(systemName: "arrow.uturn.backward.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Color(UIColor.systemGray3))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Undo")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color(UIColor.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(
                    dose.status == .taken ? medColor.opacity(0.35) :
                    dose.status == .skipped ? Color.gray.opacity(0.2) :
                    medColor.opacity(0.15),
                    lineWidth: 1
                )
        )
    }

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter(); f.timeStyle = .short; return f
    }()

    private func refreshToday() {
        let today = Calendar.current.startOfDay(for: Date())
        let all = (try? medStore.doses(for: medication, from: today, to: today)) ?? []
        todayDoses = all.sorted { $0.scheduledAt < $1.scheduledAt }
    }

    // MARK: - Header card

    private var headerCard: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(medColor.opacity(0.15))
                    .frame(width: 64, height: 64)
                Image(systemName: medication.emoji)
                    .font(.title)
                    .foregroundStyle(medColor)
                    .symbolRenderingMode(.monochrome)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(medication.name)
                    .font(.title3.weight(.semibold))
                if !medication.strength.isEmpty {
                    Text("\(medication.strength) · \(medication.form.displayName)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Text(medication.schedule.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(16)
        .background(medColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: - Contribution graph

    private var graphSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Adherence — past year")
                .font(.headline)
                .padding(.horizontal, 16)

            ContributionGraph(entries: entries, colorHex: medication.colorHex)
                .padding(.vertical, 6)
                .background(Color(UIColor.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 16)
        }
    }

    // MARK: - Stats row

    private var statsRow: some View {
        HStack(spacing: 12) {
            statCard(value: "\(streak)", label: "Current Streak", symbol: "flame.fill", color: .orange)
            statCard(value: "\(Int(adherence * 100))%", label: "30-day Adherence", symbol: "checkmark.circle.fill", color: medColor)
            statCard(value: "\(totalTaken)", label: "Total Taken", symbol: "pill.fill", color: .green)
        }
        .padding(.horizontal, 16)
    }

    private func statCard(value: String, label: String, symbol: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(color)
                .symbolRenderingMode(.monochrome)
            Text(value)
                .font(.title2.weight(.bold))
                .monospacedDigit()
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color(UIColor.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Details section

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Details")
                .font(.headline)
                .padding(.horizontal, 16)

            VStack(spacing: 0) {
                detailRow(label: "Schedule", value: medication.schedule.displayName)
                Divider().padding(.leading, 16)
                detailRow(label: "Form", value: medication.form.displayName)
                if !medication.strength.isEmpty {
                    Divider().padding(.leading, 16)
                    detailRow(label: "Strength", value: medication.strength)
                }
                if let prescriber = medication.prescriber, !prescriber.isEmpty {
                    Divider().padding(.leading, 16)
                    detailRow(label: "Prescriber", value: prescriber)
                }
                Divider().padding(.leading, 16)
                detailRow(label: "Started", value: dateString(medication.startDate))
                if let end = medication.endDate {
                    Divider().padding(.leading, 16)
                    detailRow(label: "Ends", value: dateString(end))
                }
                if longest > 0 {
                    Divider().padding(.leading, 16)
                    detailRow(label: "Longest Streak", value: "\(longest) days")
                }
            }
            .background(Color(UIColor.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 16)

            if let notes = medication.notes, !notes.isEmpty {
                Text(notes)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(UIColor.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal, 16)
            }
        }
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).fontWeight(.medium)
        }
        .font(.subheadline)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Data loading

    private func loadStats() async {
        refreshToday()
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let start365 = cal.date(byAdding: .day, value: -364, to: today) ?? today

        // Bulk-fetch all doses in the 365-day window — one query, O(n) processing
        let allDoses = (try? medStore.doses(for: medication, from: start365, to: today)) ?? []

        var byDate: [Date: [MedicationDose]] = [:]
        var taken = 0
        for dose in allDoses {
            byDate[dose.date, default: []].append(dose)
            if dose.status == .taken { taken += 1 }
        }
        totalTaken = taken

        var newEntries: [Date: ContributionEntry] = [:]
        for (date, dayDoses) in byDate {
            let dayTaken = dayDoses.filter { $0.status == .taken }.count
            let intensity = MedicationStore.intensityBucket(taken: dayTaken, total: dayDoses.count)
            if intensity > 0 {
                newEntries[date] = ContributionEntry(intensity: intensity, count: dayTaken)
            }
        }
        entries   = newEntries
        streak    = (try? medStore.currentAdherenceStreak(for: medication)) ?? 0
        longest   = (try? medStore.longestAdherenceStreak(for: medication)) ?? 0
        adherence = (try? medStore.adherenceRate(for: medication, days: 30)) ?? 0
    }

    // MARK: - Helpers

    private static let dateFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f
    }()

    private func dateString(_ date: Date) -> String {
        Self.dateFmt.string(from: date)
    }
}

// MARK: - Previews

#if DEBUG
#Preview {
    NavigationStack {
        MedStatsView(
            medication: MockData.medications[0]
        )
    }
    .environment(MedicationStore(context: MockData.previewContainer.mainContext))
    .modelContainer(MockData.previewContainer)
}
#endif
