import SwiftUI

struct UpdateLogRelease: Codable, Identifiable {
    var id: String { "\(version)-\(build)" }
    let version: String
    let build: String
    let date: String
    let headline: String
    let sections: [UpdateLogSection]
}

struct UpdateLogSection: Codable, Identifiable {
    var id: String { title }
    let title: String
    let icon: String
    let items: [String]
}

enum AppVersionInfo {
    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.4.0"
    }

    static var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "7"
    }

    static var displayBadge: String {
        "v\(version) (Build \(build))"
    }
}

enum UpdateLogStore {
    static let releases: [UpdateLogRelease] = {
        guard let url = Bundle.main.url(forResource: "UpdateLog", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([UpdateLogRelease].self, from: data) else {
            return []
        }
        return decoded
    }()
}

struct UpdateLogView: View {
    private let releases = UpdateLogStore.releases

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                installedBuildBanner

                ForEach(releases) { release in
                    releaseCard(release)
                }
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Update Log")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var installedBuildBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.title2)
                .foregroundStyle(Color.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text("Installed on This iPhone")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("Total Factor \(AppVersionInfo.displayBadge)")
                    .font(.headline)
            }

            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private func releaseCard(_ release: UpdateLogRelease) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("v\(release.version)")
                    .font(.title3.weight(.bold))
                Text("Build \(release.build)")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                    .foregroundStyle(Color.accentColor)
                Spacer()
                Text(release.date)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Text(release.headline)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            Divider()

            ForEach(release.sections) { section in
                VStack(alignment: .leading, spacing: 8) {
                    Label(section.title, systemImage: section.icon)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)

                    ForEach(Array(section.items.enumerated()), id: \.offset) { _, item in
                        HStack(alignment: .top, spacing: 8) {
                            Circle()
                                .fill(Color.accentColor)
                                .frame(width: 5, height: 5)
                                .padding(.top, 6)
                            Text(item)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }
}
