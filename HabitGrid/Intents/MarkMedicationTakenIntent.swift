import AppIntents
import SwiftData
import Foundation

struct MarkMedicationTakenIntent: AppIntent {

    static let title: LocalizedStringResource = "Mark Medication Taken"
    static let description = IntentDescription("Record that you've taken a scheduled medication dose.")

    @Parameter(title: "Medication Name", requestValueDialog: IntentDialog("Which medication did you take?"))
    var medicationName: String

    @MainActor
    func perform() async throws -> some ProvidesDialog {
        let container = try IntentModelContainer.make()
        let context = ModelContext(container)

        var medDescriptor = FetchDescriptor<Medication>(
            predicate: #Predicate { $0.archivedAt == nil }
        )
        medDescriptor.fetchLimit = 200
        let medications = try context.fetch(medDescriptor)

        guard let med = medications.first(where: {
            $0.name.localizedCaseInsensitiveCompare(medicationName) == .orderedSame
        }) else {
            throw IntentError.noMedicationFound(medicationName)
        }

        let medID = med.id
        let startOfDay = Calendar.current.startOfDay(for: Date())
        guard let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay) else {
            throw IntentError.noPendingDose(medicationName)
        }

        var doseDescriptor = FetchDescriptor<MedicationDose>(
            predicate: #Predicate { dose in
                dose.medicationID == medID &&
                dose.scheduledAt >= startOfDay &&
                dose.scheduledAt < endOfDay &&
                dose.statusRaw == "pending"
            },
            sortBy: [SortDescriptor(\.scheduledAt)]
        )
        doseDescriptor.fetchLimit = 1
        let doses = try context.fetch(doseDescriptor)

        guard let dose = doses.first else {
            throw IntentError.noPendingDose(medicationName)
        }

        dose.statusRaw = "taken"
        dose.takenAt   = Date()

        if med.pillCount != nil {
            let pills = med.pillsPerDose
            med.pillCount = max(0, (med.pillCount ?? 0) - pills)
        }

        try context.save()

        return .result(dialog: "Marked \(med.name) as taken.")
    }
}
