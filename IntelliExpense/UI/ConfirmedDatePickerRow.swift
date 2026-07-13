import SwiftUI

struct ConfirmedDatePickerRow: View {
    let title: LocalizedStringKey
    let accessibilityIdentifier: String

    @Binding private var date: Date
    @State private var draftDate: Date
    @State private var isShowingPicker = false

    init(
        _ title: LocalizedStringKey,
        selection: Binding<Date>,
        accessibilityIdentifier: String
    ) {
        self.title = title
        self.accessibilityIdentifier = accessibilityIdentifier
        _date = selection
        _draftDate = State(initialValue: selection.wrappedValue)
    }

    var body: some View {
        Button {
            draftDate = date
            isShowingPicker = true
        } label: {
            HStack {
                Text(title)
                Spacer()
                Text(ExpenseFormatters.date(date))
                    .foregroundStyle(.secondary)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("\(accessibilityIdentifier).row")
        .sheet(isPresented: $isShowingPicker) {
            NavigationStack {
                DatePicker(title, selection: $draftDate, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .padding(16)
                    .navigationTitle(title)
                    #if os(iOS)
                    .navigationBarTitleDisplayMode(.inline)
                    #endif
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("common.cancel") {
                                isShowingPicker = false
                            }
                            .accessibilityIdentifier("\(accessibilityIdentifier).cancel")
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("common.done") {
                                date = draftDate
                                isShowingPicker = false
                            }
                            .accessibilityIdentifier("\(accessibilityIdentifier).done")
                        }
                    }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }
}
