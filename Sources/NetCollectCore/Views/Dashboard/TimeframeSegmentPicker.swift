import SwiftUI

/// Compact period selector for the menu bar panel.
public struct TimeframeSegmentPicker: View {
    @Binding var selected: TimeframeFilter

    public init(selected: Binding<TimeframeFilter>) {
        _selected = selected
    }

    public var body: some View {
        Picker("Usage period", selection: $selected) {
            ForEach(TimeframeFilter.allCases) { timeframe in
                Text(timeframe.title).tag(timeframe)
            }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
    }
}
