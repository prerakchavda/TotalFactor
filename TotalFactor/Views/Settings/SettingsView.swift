import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(HealthKitService.self) private var healthService

    @Query private var profiles: [UserProfile]
    @Query private var goals: [Goal]
    @Query private var customNutrientTargets: [NutrientTarget]
    @Query private var gymProfiles: [GymProfile]

    @State private var showingOnboardingSheet: Bool = false

    private var profile: UserProfile {
        profiles.first ?? CoachingCoordinator.fetchOrCreateProfile(context: modelContext)
    }

    private var goal: Goal {
        goals.first(where: \.isActive) ?? CoachingCoordinator.fetchOrCreateGoal(profile: profile, context: modelContext)
    }

    private var weekdayName: String {
        switch profile.checkInWeekday {
        case 1: return "Sunday"
        case 2: return "Monday"
        case 3: return "Tuesday"
        case 4: return "Wednesday"
        case 5: return "Thursday"
        case 6: return "Friday"
        case 7: return "Saturday"
        default: return "Monday"
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    profileProgramCard
                }

                Section("Coaching & Nutrition") {
                    NavigationLink {
                        GoalStrategySettingsView()
                    } label: {
                        settingsRow(
                            icon: "target",
                            color: .orange,
                            title: "Goals & Target Rates",
                            subtitle: "\(goal.type.displayName) • \(String(format: "%.2f%% BW/wk", goal.ratePercentPerWeek))"
                        )
                    }

                    NavigationLink {
                        FastingSettingsView()
                    } label: {
                        settingsRow(
                            icon: "timer",
                            color: .indigo,
                            title: "Intermittent Fasting",
                            subtitle: profile.enableIntermittentFasting
                                ? "\(profile.fastingProtocol.displayName) (Active)"
                                : "Disabled"
                        )
                    }

                    NavigationLink {
                        NutrientTargetsEditorView()
                    } label: {
                        settingsRow(
                            icon: "slider.horizontal.3",
                            color: .cyan,
                            title: "Custom Nutrient Targets",
                            subtitle: customNutrientTargets.isEmpty
                                ? "Using scientific baseline floors"
                                : "\(customNutrientTargets.count) custom floors & ceilings"
                        )
                    }
                }

                Section("Workouts & Training") {
                    NavigationLink {
                        WorkoutPreferencesSettingsView()
                    } label: {
                        settingsRow(
                            icon: "figure.strengthtraining.traditional",
                            color: .green,
                            title: "Workout & Rest Preferences",
                            subtitle: "Rest timers, Apple Watch haptics, gym setups"
                        )
                    }

                    NavigationLink {
                        GymProfileEditorView()
                    } label: {
                        settingsRow(
                            icon: "dumbbell.fill",
                            color: .teal,
                            title: "Gym Equipment Profiles",
                            subtitle: "\(gymProfiles.count) saved profiles"
                        )
                    }
                }

                Section("Preferences & Schedule") {
                    NavigationLink {
                        UnitsScheduleSettingsView()
                    } label: {
                        settingsRow(
                            icon: "gearshape.fill",
                            color: .blue,
                            title: "Units & Schedule",
                            subtitle: "\(profile.unitSystem.displayName) • Check-in on \(weekdayName)s"
                        )
                    }

                    NavigationLink {
                        NotificationsSettingsView()
                    } label: {
                        settingsRow(
                            icon: "bell.badge.fill",
                            color: .pink,
                            title: "Reminders & Notifications",
                            subtitle: "Weigh-in alarms, meal reminders, gym alerts"
                        )
                    }
                }

                Section("Integrations & Cloud") {
                    NavigationLink {
                        AppleHealthSettingsView()
                    } label: {
                        settingsRow(
                            icon: "heart.text.square.fill",
                            color: .pink,
                            title: "Apple Health Bi-Directional Sync",
                            subtitle: healthService.lastSyncDate != nil
                                ? "Last synced \(healthService.lastSyncDate!.formatted(date: .abbreviated, time: .shortened))"
                                : "Two-way food, weight & workout sync"
                        )
                    }

                    NavigationLink {
                        AIDatabaseSettingsView()
                    } label: {
                        settingsRow(
                            icon: "sparkles",
                            color: .purple,
                            title: "AI & Food Databases",
                            subtitle: "USDA FoodData Central & Google Gemini AI"
                        )
                    }
                }

                Section("Data Management & Backup") {
                    NavigationLink {
                        DataManagementSettingsView()
                    } label: {
                        settingsRow(
                            icon: "square.and.arrow.up.on.square.fill",
                            color: .mint,
                            title: "Data Management & Exports",
                            subtitle: "MacroFactor CSV import, universal package, CSVs"
                        )
                    }
                }

                Section("About Total Factor") {
                    NavigationLink {
                        UpdateLogView()
                    } label: {
                        HStack {
                            Image(systemName: "sparkles.rectangle.stack.fill")
                                .font(.title3)
                                .foregroundStyle(Color.accentColor)
                                .frame(width: 32, height: 32)
                                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                            VStack(alignment: .leading, spacing: 2) {
                                Text("What's New & Update Log")
                                    .font(.subheadline.weight(.semibold))
                                Text("Detailed running release history")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Text(AppVersionInfo.displayBadge)
                                .font(.caption.weight(.semibold).monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }

                    NavigationLink {
                        AttributionSettingsView()
                    } label: {
                        settingsRow(
                            icon: "info.circle.fill",
                            color: .secondary,
                            title: "Data Attribution & Science",
                            subtitle: "USDA, Open Food Facts, Free Exercise DB"
                        )
                    }
                }
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showingOnboardingSheet) {
                OnboardingFlowView(profile: profile)
            }
        }
    }

    // MARK: - Components

    private var profileProgramCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "bolt.heart.fill")
                    .font(.title)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 48, height: 48)
                    .background(Color.accentColor.opacity(0.14), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("Active Program")
                            .font(.headline)

                        Text(goal.type.displayName)
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.14), in: Capsule())
                            .foregroundStyle(Color.accentColor)
                    }

                    let weightDisp = UnitsFormatter.formatWeight(profile.startingWeightKg, system: profile.unitSystem)
                    Text("\(profile.biologicalSex.displayName) • \(profile.ageYears) yrs • \(weightDisp)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            Divider()

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Check-In Day")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    Text("\(weekdayName)s")
                        .font(.subheadline.weight(.semibold))
                }

                Spacer()

                Button {
                    showingOnboardingSheet = true
                } label: {
                    Label("Rerun Setup", systemImage: "arrow.counterclockwise")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }

    private func settingsRow(icon: String, color: Color, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundStyle(color)
                .frame(width: 32, height: 32)
                .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}
