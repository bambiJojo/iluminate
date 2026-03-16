//
//  SettingsView+ProfileSection.swift
//  LumeSync
//
//  Profile section and editor sheet for SettingsView.
//

import SwiftUI

extension SettingsView {

    // MARK: - Profile Section

    var profileSection: some View {
        GlassCard(label: "Profile") {
            HStack(spacing: TranceSpacing.card) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.roseGold, .bwTheta],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 60, height: 60)
                    Text(profileInitials)
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(profileName.isEmpty ? "Your Name" : profileName)
                        .font(TranceTypography.sectionTitle)
                        .foregroundStyle(profileName.isEmpty ? Color.textLight : Color.textPrimary)
                    Text(profileGoal.isEmpty ? "Set your wellness goal…" : profileGoal)
                        .font(TranceTypography.caption)
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(2)
                }

                Spacer()

                Button("Edit Profile", systemImage: "pencil.circle.fill") {
                    TranceHaptics.shared.light()
                    draftName = profileName
                    draftGoal = profileGoal
                    isEditingProfile = true
                }
                .labelStyle(.iconOnly)
                .font(.system(size: 26))
                .foregroundStyle(Color.roseGold)
            }
        }
    }

    private var profileInitials: String {
        let words = profileName.split(separator: " ").prefix(2)
        let joined = words.map { String($0.prefix(1)).uppercased() }.joined()
        return joined.isEmpty ? "?" : joined
    }

    // MARK: - Profile Editor Sheet

    var profileEditor: some View {
        NavigationStack {
            ZStack {
                Color.bgPrimary.ignoresSafeArea()

                VStack(spacing: TranceSpacing.cardMargin) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [.roseGold, .bwTheta],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 90, height: 90)

                        let preview: String = {
                            let words = draftName.split(separator: " ").prefix(2)
                            let result = words.map { String($0.prefix(1)).uppercased() }.joined()
                            return result.isEmpty ? "?" : result
                        }()
                        Text(preview)
                            .font(.system(size: 34, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                    }
                    .padding(.top, TranceSpacing.content)

                    GlassCard(label: "Your Info") {
                        VStack(spacing: TranceSpacing.list) {
                            HStack {
                                Image(systemName: "person.fill")
                                    .foregroundStyle(Color.roseGold)
                                    .frame(width: 24)
                                TextField("Name", text: $draftName)
                                    .font(TranceTypography.body)
                                    .foregroundStyle(Color.textPrimary)
                            }
                            Divider().background(Color.glassBorder)
                            HStack(alignment: .top) {
                                Image(systemName: "heart.fill")
                                    .foregroundStyle(Color.roseGold)
                                    .frame(width: 24)
                                    .padding(.top, 2)
                                TextField(
                                    "Wellness goal (e.g. reduce anxiety)",
                                    text: $draftGoal,
                                    axis: .vertical
                                )
                                .font(TranceTypography.body)
                                .foregroundStyle(Color.textPrimary)
                                .lineLimit(3)
                            }
                        }
                    }
                    .padding(.horizontal, TranceSpacing.screen)

                    Spacer()
                }
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isEditingProfile = false }
                        .foregroundStyle(Color.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        TranceHaptics.shared.medium()
                        profileName = draftName
                        profileGoal = draftGoal
                        isEditingProfile = false
                    }
                    .foregroundStyle(Color.roseGold)
                    .bold()
                }
            }
        }
    }
}
