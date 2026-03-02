//
//  SessionLibraryView.swift
//  Ilumionate
//
//  Created by Byron Quine on 2/9/26.
//

import SwiftUI

/// Browse and select pre-programmed light sessions
struct SessionLibraryView: View {

    var engine: LightEngine
    @Environment(\.dismiss) private var dismiss

    @State private var sessions: [LightSession] = []
    @State private var selectedSession: LightSession?
    @State private var loadError: String?
    @State private var showingSessionPlayer = false

    var body: some View {
        NavigationStack {
            Group {
                if sessions.isEmpty {
                    emptyView
                } else {
                    sessionListView
                }
            }
            .navigationTitle("Session Library")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                loadBundledSessions()
            }
            .alert("Load Error", isPresented: .constant(loadError != nil)) {
                Button("OK") {
                    loadError = nil
                }
            } message: {
                if let error = loadError {
                    Text(error)
                }
            }
            .sheet(isPresented: $showingSessionPlayer) {
                if let session = selectedSession {
                    SessionPlayerView(session: session, engine: engine)
                }
            }
        }
    }

    // MARK: - Subviews

    private var emptyView: some View {
        ContentUnavailableView(
            "No Sessions Found",
            systemImage: "waveform.circle",
            description: Text("Add JSON session files to your app bundle to see them here.")
        )
    }

    private var sessionListView: some View {
        List(sessions) { session in
            SessionRowView(session: session)
                .contentShape(Rectangle())
                .onTapGesture {
                    selectedSession = session
                    showingSessionPlayer = true
                }
        }
    }

    // MARK: - Loading

    private func loadBundledSessions() {
        sessions = []

        let sessionNames = LightScoreReader.discoverBundledSessions()

        for name in sessionNames {
            do {
                let session = try LightScoreReader.loadSession(named: name)
                sessions.append(session)
            } catch {
                print("Failed to load session '\(name)': \(error)")
            }
        }
    }
}

// MARK: - Session Row

struct SessionRowView: View {
    let session: LightSession

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(session.displayName)
                .font(.headline)

            HStack {
                Label(session.durationFormatted, systemImage: "clock")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer()

                Label("\(session.light_score.count) moments", systemImage: "waveform")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            // Mini timeline preview
            sessionTimelinePreview
        }
        .padding(.vertical, 4)
    }

    private var sessionTimelinePreview: some View {
        GeometryReader { _ in
            Canvas { context, size in
                let width = size.width
                let height: CGFloat = 30
                let duration = session.duration_sec

                // Draw frequency curve
                var path = Path()
                for (index, moment) in session.light_score.enumerated() {
                    let x = CGFloat(moment.time / duration) * width
                    let normalizedFreq = (moment.frequency - 0.5) / 40.0 // 0.5-40 Hz range
                    let y = height - (CGFloat(normalizedFreq) * height)

                    if index == 0 {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }

                context.stroke(
                    path,
                    with: .color(.blue),
                    lineWidth: 2
                )

                // Draw moment dots
                for moment in session.light_score {
                    let x = CGFloat(moment.time / duration) * width
                    let normalizedFreq = (moment.frequency - 0.5) / 40.0
                    let y = height - (CGFloat(normalizedFreq) * height)

                    let circle = Path(ellipseIn: CGRect(
                        x: x - 3,
                        y: y - 3,
                        width: 6,
                        height: 6
                    ))

                    context.fill(circle, with: .color(.blue))
                }
            }
        }
        .frame(height: 30)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(4)
    }
}

// MARK: - Preview

#Preview {
    SessionLibraryView(engine: LightEngine())
}
