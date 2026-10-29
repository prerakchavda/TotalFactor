import SwiftUI

struct AttributionSettingsView: View {
    var body: some View {
        List {
            Section("Open Data & Licenses") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("USDA FoodData Central")
                        .font(.headline)
                    Text("Whole food nutrition catalogs (Foundation Foods & SR Legacy, ~8,156 foods) are in the public domain (CC0) and operate 100% offline on-device.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Open Food Facts")
                        .font(.headline)
                    Text("Packaged and branded barcode product information is provided via the Open Food Facts crowdsourced database, licensed under the Open Database License (ODbL).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Free Exercise DB")
                        .font(.headline)
                    Text("Exercise photography and anatomy target mappings are sourced from the Free Exercise DB project (Public Domain / Unlicense).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section("Calculations & Philosophy") {
                Text("• Mifflin-St Jeor equation establishes day-1 basal metabolic rate.\n• Dynamic expenditure is derived purely from daily scale weights and food intake.\n• Smartwatch calories and heart rate are displayed for daily context only and never distort your nutritional targets.\n• Adherence-neutral coaching never applies penalties or guilt for eating over or under targets.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Attribution & Science")
        .navigationBarTitleDisplayMode(.inline)
    }
}
