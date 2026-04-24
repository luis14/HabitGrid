import SwiftUI

/// A compact sheet that lets the user pick the exact time a dose was taken
/// before committing to storage.
struct LogTakenSheet: View {

    let medName: String
    let scheduledAt: Date
    let onLog: (Date) -> Void
    let onCancel: () -> Void

    @State private var takenAt: Date = Date()

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter(); f.timeStyle = .short; return f
    }()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Text("When did you take \(medName)?")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)

                DatePicker(
                    "",
                    selection: $takenAt,
                    in: ...Date(),
                    displayedComponents: .hourAndMinute
                )
                .datePickerStyle(.wheel)
                .labelsHidden()

                Text("Scheduled for \(Self.timeFmt.string(from: scheduledAt))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 8)
            }
            .navigationTitle("Log Dose")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Log") { onLog(min(takenAt, Date())) }
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.height(300)])
        .presentationDragIndicator(.visible)
    }
}
