//
//  PlaylistPlayerView.swift
//  Ilumionate
//
//  Full-screen immersive playlist player with track navigation and crossfade controls
//

import SwiftUI
import Combine

struct PlaylistPlayerView: View {
    
    let playlist: Playlist
    @Bindable var engine: LightEngine
    @Environment(\.dismiss) private var dismiss
    
    @State private var controller: PlaylistPlayerController?
    @State private var showingControls = true
    @State private var showingTrackList = false
    @State private var displayTime: Double = 0.0
    @State private var displayDuration: Double = 0.0
    @State private var volumePercentage: Int = 100
    @State private var brightnessPercentage: Int = 100
    private let uiUpdateTimer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()
    
    var body: some View {
        ZStack {
            // Background — driven by engine
            SessionView(engine: engine)
            
            // Lock overlay
            SessionLockView {
                controller?.stop()
                dismiss()
            }
            
            // Loading state
            if controller == nil {
                ProgressView("Loading playlist...")
                    .tint(.white)
                    .foregroundStyle(.white)
            }
            
            // Controls overlay
            if showingControls, let controller = controller {
                controlsOverlay(controller: controller)
                    .transition(.opacity)
            }
            
            // Floating controls button
            if !showingControls && controller != nil {
                VStack {
                    HStack {
                        Spacer()
                        Button {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                showingControls = true
                            }
                        } label: {
                            Image(systemName: "slider.horizontal.3")
                                .font(.title3)
                                .foregroundStyle(.white)
                                .padding(12)
                                .background(.ultraThinMaterial)
                                .clipShape(Circle())
                                .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
                        }
                        .padding()
                    }
                    Spacer()
                }
                .transition(.opacity)
            }
        }
        .task {
            let ctrl = PlaylistPlayerController(playlist: playlist, engine: engine)
            controller = ctrl
            await ctrl.startPlayback()
            
            // Auto-hide controls after 3s
            try? await Task.sleep(for: .seconds(3))
            withAnimation(.easeInOut(duration: 0.3)) {
                showingControls = false
            }
        }
        .onDisappear {
            controller?.stop()
        }
        .onReceive(uiUpdateTimer) { _ in
            if let controller = controller {
                displayTime = controller.currentTime
                displayDuration = controller.currentItemDuration
                volumePercentage = Int(controller.volume * 100)
                brightnessPercentage = Int(engine.userBrightnessMultiplier * 100)
            }
        }
        .statusBar(hidden: !showingControls)
        .sheet(isPresented: $showingTrackList) {
            trackListSheet
        }
    }
    
    // MARK: - Controls Overlay
    
    private func controlsOverlay(controller: PlaylistPlayerController) -> some View {
        VStack {
            // Top bar
            HStack {
                Button {
                    controller.stop()
                    dismiss()
                } label: {
                    Image(systemName: "house.fill")
                        .font(.title3)
                        .foregroundStyle(.white)
                }
                
                Spacer()
                
                VStack(alignment: .center, spacing: 2) {
                    Text(playlist.name)
                        .font(.headline)
                    
                    if let item = controller.currentItem {
                        Text("\(controller.currentItemIndex + 1) of \(controller.itemCount) — \(item.filename)")
                            .font(.caption)
                            .lineLimit(1)
                    }
                    
                    Text(controller.formatTime(displayTime) + " / " + controller.formatTime(displayDuration))
                        .font(.caption2)
                        .monospacedDigit()
                }
                
                Spacer()
                
                Button {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        showingControls = false
                    }
                } label: {
                    Image(systemName: "arrow.down.right.and.arrow.up.left")
                        .font(.title3)
                        .foregroundStyle(.white)
                }
            }
            .padding()
            .background(.ultraThinMaterial)
            
            Spacer()
            
            // Bottom controls
            VStack(spacing: 16) {
                // Progress bar for current track
                VStack(spacing: 4) {
                    Slider(value: Binding(
                        get: { displayTime },
                        set: { controller.seek(to: $0) }
                    ), in: 0...max(displayDuration, 1))
                    .tint(.white)
                    
                    HStack {
                        Text(controller.formatTime(displayTime))
                            .font(.caption2)
                            .monospacedDigit()
                        Spacer()
                        Text("-" + controller.formatTime(max(0, displayDuration - displayTime)))
                            .font(.caption2)
                            .monospacedDigit()
                    }
                    .foregroundStyle(.white.opacity(0.6))
                }
                
                // Volume control
                VStack(spacing: 8) {
                    HStack {
                        Image(systemName: "speaker.fill")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                        
                        Slider(value: Binding(
                            get: { Double(controller.volume) },
                            set: { controller.setVolume(Float($0)) }
                        ), in: 0...1)
                        .tint(.white)
                        
                        Image(systemName: "speaker.wave.3.fill")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    
                    Text("Audio: \(volumePercentage)%")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.6))
                }
                .padding(.horizontal)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial)
                .cornerRadius(12)
                
                // Brightness control
                VStack(spacing: 8) {
                    HStack {
                        Image(systemName: "sun.min.fill")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                        
                        Slider(value: $engine.userBrightnessMultiplier, in: 0.1...1.0)
                            .tint(.white)
                        
                        Image(systemName: "sun.max.fill")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    
                    Text("Brightness: \(brightnessPercentage)%")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.6))
                }
                .padding(.horizontal)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial)
                .cornerRadius(12)
                
                // Smart transitions toggle
                HStack {
                    Toggle("Smart Transitions", isOn: Binding(
                        get: { controller.smartTransitions },
                        set: { controller.smartTransitions = $0 }
                    ))
                    .font(.caption)
                    .tint(.blue)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)
                .cornerRadius(12)
                
                // Transport controls
                HStack(spacing: 32) {
                    // Previous
                    Button {
                        Task { await controller.skipPrevious() }
                    } label: {
                        Image(systemName: "backward.fill")
                            .font(.title2)
                    }
                    .disabled(controller.isFirstItem && controller.currentTime < 3)
                    
                    // Play/Pause
                    Button {
                        if controller.isPlaying {
                            controller.pause()
                        } else {
                            controller.play()
                        }
                    } label: {
                        Image(systemName: controller.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 60))
                    }
                    
                    // Next
                    Button {
                        Task { await controller.skipNext() }
                    } label: {
                        Image(systemName: "forward.fill")
                            .font(.title2)
                    }
                    .disabled(controller.isLastItem)
                }
                
                // Track list button
                Button {
                    showingTrackList = true
                } label: {
                    Label("Track List", systemImage: "list.number")
                        .font(.caption)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial)
                        .cornerRadius(20)
                }
                
                Text("Tap screen to exit")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.bottom, 40)
            }
            .padding()
            .background(.ultraThinMaterial)
        }
        .foregroundStyle(.white)
        .onTapGesture {
            // Keep controls visible when tapping the controls area
        }
    }
    
    // MARK: - Track List Sheet
    
    private var trackListSheet: some View {
        NavigationStack {
            List {
                ForEach(Array(playlist.items.enumerated()), id: \.element.id) { index, item in
                    Button {
                        showingTrackList = false
                        Task {
                            await controller?.jumpToItem(at: index)
                        }
                    } label: {
                        HStack {
                            if index == controller?.currentItemIndex {
                                Image(systemName: "speaker.wave.2.fill")
                                    .foregroundStyle(.blue)
                                    .frame(width: 24)
                            } else {
                                Text("\(index + 1)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 24)
                            }
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.filename)
                                    .font(.body)
                                    .foregroundStyle(index == controller?.currentItemIndex ? .blue : .primary)
                                    .lineLimit(1)
                                
                                Text(item.durationFormatted)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            
                            Spacer()
                            
                            if index == controller?.currentItemIndex {
                                Image(systemName: "waveform")
                                    .foregroundStyle(.blue)
                                    .symbolEffect(.variableColor.iterative)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Tracks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showingTrackList = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
