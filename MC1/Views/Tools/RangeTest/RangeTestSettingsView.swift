import SwiftUI

struct RangeTestSettingsView: View {
    @Bindable var viewModel: RangeTestViewModel
    @Environment(\.dismiss) private var dismiss

    private static let distanceOptions: [Double] = [5, 10, 25, 50, 100, 250, 500, 1000, 2000]
    private static let intervalOptions: [Double] = [5, 10, 15, 30, 60, 120, 300, 600, 900]

    @State private var minDistance: Double
    @State private var minInterval: Double
    @State private var messageTemplate: String

    init(viewModel: RangeTestViewModel) {
        self.viewModel = viewModel
        _minDistance = State(initialValue: Self.nearest(viewModel.settings.minimumDistanceMeters, in: Self.distanceOptions))
        _minInterval = State(initialValue: Self.nearest(viewModel.settings.minimumIntervalSeconds, in: Self.intervalOptions))
        _messageTemplate = State(initialValue: viewModel.settings.messageTemplate)
    }

    private static func nearest(_ value: Double, in options: [Double]) -> Double {
        options.min(by: { abs($0 - value) < abs($1 - value) }) ?? options[0]
    }

    private static func intervalLabel(_ seconds: Double) -> String {
        seconds >= 60 ? "\(Int(seconds / 60)) min" : "\(Int(seconds)) sec"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    RangeTestTemplateEditor(template: $messageTemplate)

                    Button("Reset to default") {
                        messageTemplate = RangeTestSettings.defaultMessageTemplate
                    }
                } header: {
                    Text("Beacon Message")
                } footer: {
                    Text("Tap a token pill to insert it at the cursor. Valid tokens are highlighted in blue; unknown tokens appear in red.")
                }
                
                Section {
                    Picker("Distance", selection: $minDistance) {
                        ForEach(Self.distanceOptions, id: \.self) { d in
                            Text("\(Int(d)) m").tag(d)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(height: 120)
                } header: {
                    Text("Location Threshold")
                } footer: {
                    Text("Minimum distance between background GPS measurements.")
                }

                Section {
                    Picker("Interval", selection: $minInterval) {
                        ForEach(Self.intervalOptions, id: \.self) { s in
                            Text(Self.intervalLabel(s)).tag(s)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(height: 120)
                } header: {
                    Text("Time Gate")
                } footer: {
                    Text("Minimum time that must elapse between the last & new radio beacon transmissions.")
                }

            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        viewModel.settings.minimumDistanceMeters = minDistance
                        viewModel.settings.minimumIntervalSeconds = minInterval
                        viewModel.settings.messageTemplate = messageTemplate
                        dismiss()
                    }
                }
            }
        }
    }
}
