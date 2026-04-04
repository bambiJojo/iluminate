//
//  StreamingSettingsView.swift
//  Ilumionate
//
//  Settings for configuring SoundCloud streaming service
//

import SwiftUI

struct StreamingSettingsView: View {
    let manager: StreamingManager
    @Environment(\.dismiss) private var dismiss

    @State private var soundCloudClientId = ""
    @State private var soundCloudSecret = ""
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            Form {
                instructionsSection
                soundCloudSection
                actionsSection
            }
            .navigationTitle("SoundCloud Setup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveAndConnect() }
                        .disabled(soundCloudClientId.isEmpty && soundCloudSecret.isEmpty)
                }
            }
            .onAppear(perform: loadStoredCredentials)
        }
    }

    // MARK: - Instructions Section

    private var instructionsSection: some View {
        Section {
            VStack(alignment: .leading, spacing: TranceSpacing.card) {
                Text("Connect to SoundCloud to access thousands of full-length meditation, therapy, and ambient tracks perfect for light therapy sessions.")
                    .font(TranceTypography.body)
                    .foregroundStyle(.textSecondary)

                Text("Register a developer application at SoundCloud to get API credentials.")
                    .font(TranceTypography.caption)
                    .foregroundStyle(.textLight)
            }
        }
    }

    // MARK: - SoundCloud Section

    private var soundCloudSection: some View {
        Section {
            VStack(alignment: .leading, spacing: TranceSpacing.inner) {
                HStack {
                    Image(systemName: "cloud.fill")
                        .foregroundStyle(StreamingServiceType.soundcloud.color)
                    Text("SoundCloud")
                        .font(TranceTypography.sectionTitle)
                        .fontWeight(.semibold)
                }

                Button("Register at: soundcloud.com/you/apps/new") {
                    if let url = URL(string: "https://soundcloud.com/you/apps/new") {
                        UIApplication.shared.open(url)
                    }
                }
                .font(TranceTypography.caption)
                .foregroundStyle(.blue)
                .buttonStyle(.plain)

                TextField("Client ID", text: $soundCloudClientId)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.username)

                SecureField("Client Secret", text: $soundCloudSecret)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.password)

                if manager.soundCloudService?.isAuthenticated == true {
                    Label("Connected", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(TranceTypography.caption)
                }
            }
        } header: {
            Text("SoundCloud Configuration")
        } footer: {
            Text("SoundCloud provides access to full-length tracks including meditation, ambient, and therapy content - perfect for light therapy sessions.")
        }
    }

    // MARK: - Actions Section

    private var actionsSection: some View {
        Section {
            if isLoading {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Connecting...")
                        .font(TranceTypography.body)
                        .foregroundStyle(.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
            } else {
                Button("Test Connection") {
                    testConnection()
                }
                .disabled(soundCloudClientId.isEmpty || soundCloudSecret.isEmpty)

                Button("Clear Data", role: .destructive) {
                    clearData()
                }
            }
        } header: {
            Text("Actions")
        }
    }

    // MARK: - Actions

    private func loadStoredCredentials() {
        soundCloudClientId = UserDefaults.standard.string(forKey: "SoundCloud_ClientId") ?? ""
        soundCloudSecret = UserDefaults.standard.string(forKey: "SoundCloud_Secret") ?? ""
    }

    private func saveAndConnect() {
        saveCredentials()
        configureManager()
        Task {
            isLoading = true
            await manager.authenticateAll()
            isLoading = false
            dismiss()
        }
    }

    private func testConnection() {
        saveCredentials()
        configureManager()
        Task {
            isLoading = true
            await manager.authenticateAll()
            isLoading = false
        }
    }

    private func saveCredentials() {
        UserDefaults.standard.set(soundCloudClientId, forKey: "SoundCloud_ClientId")
        UserDefaults.standard.set(soundCloudSecret, forKey: "SoundCloud_Secret")
    }

    private func configureManager() {
        manager.configure(
            soundCloudClientId: soundCloudClientId.isEmpty ? nil : soundCloudClientId,
            soundCloudSecret: soundCloudSecret.isEmpty ? nil : soundCloudSecret
        )
    }

    private func clearData() {
        // Clear credentials
        UserDefaults.standard.removeObject(forKey: "SoundCloud_ClientId")
        UserDefaults.standard.removeObject(forKey: "SoundCloud_Secret")

        // Clear tokens
        UserDefaults.standard.removeObject(forKey: "SoundCloud_AccessToken")

        // Clear form
        soundCloudClientId = ""
        soundCloudSecret = ""

        // Reconfigure manager
        manager.configure()
    }
}

#Preview {
    StreamingSettingsView(manager: StreamingManager())
}