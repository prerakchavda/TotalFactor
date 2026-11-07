import SwiftUI

/// A section switcher shown at the top of a main tab (e.g. Workouts → Train / Recovery / History / Exercises),
/// so each screen shows one focused section instead of one long scroll.
struct SubTabBar<Tab: Hashable & Identifiable>: View {
    let tabs: [Tab]
    @Binding var selection: Tab
    let title: (Tab) -> String

    var body: some View {
        Picker("Section", selection: $selection) {
            ForEach(tabs) { tab in
                Text(title(tab)).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 8)
        .sensoryFeedback(.selection, trigger: selection)
    }
}
