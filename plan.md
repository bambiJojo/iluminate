# Ilumionate UI Refresh - "Trance" Design Implementation Plan

## Executive Summary

This plan implements the complete "Trance" design specification with pink/rose-gold theme, glass morphism, and premium aesthetic. The new design replaces the current design philosophy with a cohesive, elegant light therapy experience.

---

## PHASE 1: Foundation & Design System (Week 1)

### 1.1 Enhanced Design System Core
**Priority: CRITICAL**
- [x] **Replace IlluminateDesignSystem.swift** with new Trance color palette
- [x] **Create Color+Hex extension** for hex color support
- [x] **Implement GlassBackground ViewModifier** with ultraThinMaterial
- [x] **Create shadow system** with standardized shadow styles
- [x] **Establish spacing constants** (4, 6, 8, 10, 12, 14, 16, 20, 22, 28)
- [x] **Define corner radius system** (10, 14, 16, 18, 20, 26, 48)

### 1.2 Core Reusable Components
**Priority: CRITICAL**
- [x] **GlassCard component** - Primary container with optional labels
- [x] **CategoryIcon component** - Circular icons with halo effects
- [x] **CTAButton component** - Gradient buttons with press animations
- [x] **PhasePill component** - Capsule labels for phases
- [x] **ProgressRingView component** - Circular progress indicators
- [x] **AudioScrubber component** - Progress slider for audio
- [x] **SyncToggle component** - Custom toggle with rose styling

### 1.3 Advanced Visual Components
**Priority: HIGH**
- [x] **WaveformView component** - Audio waveform visualization
- [x] **IntensityDial component** - Circular intensity control
- [x] **PulseOrb component** - Breathing animation orb
- [x] **MandalaVisualizer component** - Concentric pulsing rings
- [x] **FlashView component** - Full-screen flash mode
- [x] **BilateralFlashView component** - Split-screen bilateral mode

---

## PHASE 2: Navigation & Tab System (Week 1-2)

### 2.1 New Navigation Architecture
**Priority: CRITICAL**
- [x] **Create TranceTab enum** with Home, Library, Machine, Store, Profile
- [x] **Implement TranceTabBar component** with glass morphism
- [x] **Update ContentView.swift** with new tab structure
- [x] **Configure NavigationStack** for each tab
- [x] **Implement tab animations** with 0.25s crossfade

### 2.2 Navigation Flow Setup
**Priority: HIGH**
- [x] **Setup NavigationLink flows** between screens
- [x] **Implement fullScreenCover** for Player and Flash modes
- [x] **Configure sheet presentations** for settings/analyzer
- [x] **Add transition animations** (0.3s spring for pushes)

---

## PHASE 3: Home Dashboard Redesign (Week 2)

### 3.1 Home Screen Layout
**Priority: CRITICAL**
- [x] **Replace ContentView.swift** with new Home dashboard
- [x] **Implement greeting section** with dynamic time-based messages
- [x] **Create category icon grid** (Sleep, Focus, Energy, Relax, Trance)
- [x] **Add Continue Session card** with waveform and progress
- [x] **Implement Quick Start section** with mini-cards
- [x] **Create Your Library horizontal scroll** with thumbnails

### 3.2 Home Screen Components
**Priority: HIGH**
- [x] **SessionContinueCard component** - Resume previous session
- [x] **QuickStartCard component** - Alpha/Theta quick access
- [x] **LibraryThumbnail component** - 72×72 gradient thumbnails
- [x] **Implement staggered animations** for card entrance
- [x] **Add pull-to-refresh** functionality

---

## PHASE 4: Audio Player Redesign (Week 2-3)

### 4.1 Player Layout
**Priority: CRITICAL**
- [x] **Redesign SessionPlayerView.swift** with new layout
- [x] **Implement MandalaVisualizer** center piece
- [x] **Create player controls layout** with gradient play button
- [x] **Add phase indicator** with PhasePill
- [x] **Implement audio scrubber** with rose-gold styling

### 4.2 Player Features
**Priority: HIGH**
- [x] **Add SyncToggle** for Mind Machine sync
- [x] **Create Up Next section** with GlassCard
- [x] **Implement navigation controls** (back, next, shuffle, repeat)
- [x] **Add time display** (current/remaining)
- [ ] **Configure player animations** (mandala pulse, button press)

---

## PHASE 5: Mind Machine Interface (Week 3)

### 5.1 Mind Machine Layout
**Priority: CRITICAL**
- [x] **Create new MindMachineView.swift** following spec
- [x] **Implement LightVisualization area** with PulseOrb
- [x] **Add Frequency card** with custom slider
- [x] **Create Color Temperature selector** with dot grid
- [x] **Implement Pattern cards** horizontal scroll
- [x] **Add Intensity card** with IntensityDial

### 5.2 Mind Machine Features
**Priority: HIGH**
- [x] **Custom frequency slider** with brainwave zone labels
- [x] **Color temperature dots** with selection animation
- [x] **Pattern selection cards** with gradient backgrounds
- [x] **Intensity dial gesture** handling
- [x] **Start Session CTA** with gradient and shadow

### 5.3 Flash Mode Implementation
**Priority: HIGH**
- [x] **Full-screen flash view** with frequency control
- [x] **Bilateral drift mode** with left/right split
- [x] **Screen brightness control** (set to 1.0 during flash, restored on stop)
- [x] **Accessibility check** for reduce motion
- [x] **Safety warnings** for photosensitive users

---

## PHASE 6: Library & Content Management (Week 3-4)

### 6.1 Audio Library Redesign
**Priority: MEDIUM**
- [x] **Redesign AudioLibraryView.swift** with glass cards
- [x] **Implement import options** (files, URL, in-app browser — surfaced in empty state + toolbar)
- [x] **Create audio file grid** with waveform previews (deterministic per-file waveform thumbnail)
- [x] **Add analysis status indicators** with phase colors (Trance phase color system)
- [x] **Implement batch operations** UI (selection mode with delete + analyze all)

### 6.2 Session Library
**Priority: MEDIUM**
- [x] **Redesign SessionLibraryView.swift** with new layout
- [x] **Create session cards** with metadata
- [x] **Implement filtering/search** functionality
- [x] **Add session thumbnails** with gradient backgrounds
- [ ] **Configure session selection** flow

---

## PHASE 7: Audio Analyzer & Generation (Week 4)

### 7.1 Analyzer Interface
**Priority: MEDIUM**
- [x] **Create AudioAnalyzerView.swift** following spec layout
- [x] **Implement Waveform Analysis card** with phase zones
- [x] **Add Detected Phases card** with phase rows
- [x] **Create Light Script Preview** with gradient
- [x] **Add Customize Script options** with parameter controls

### 7.2 Session Generation
**Priority: MEDIUM**
- [x] **Enhance SessionGenerationView.swift** with new design
- [x] **Implement phase detection visualization**
- [x] **Add customization controls** for frequency/intensity
- [x] **Create generation CTA** with special gradient
- [ ] **Configure preview functionality**

---

## PHASE 8: Settings & Profile (Week 4-5)

### 8.1 Settings Redesign
**Priority: LOW**
- [x] **Redesign SettingsView.swift** with glass cards (split into 3 files for SwiftLint compliance)
- [x] **Implement notification settings** with SyncToggle style (Session Notifications toggle)
- [ ] **Add accessibility options** (reduce motion, etc.)
- [x] **Create data export options** (Export Session Data via share sheet)
- [x] **Configure app preferences** (intensity, duration, bilateral, frequency scale, history toggle)

### 8.2 Profile Features
**Priority: LOW**
- [x] **Create ProfileView.swift** with user stats
- [x] **Implement wellness tracking** visualization (weekly activity bar chart)
- [x] **Add session history** with completion status and listen time
- [ ] **Create achievements/milestones** section

### 8.3 Features.json Audit (2026-03-15)
Comprehensive audit of all features.json items; implementation of 3 MISSING + 8 PARTIAL items:
- [x] **Listening history opt-in toggle** — `listeningHistoryEnabled` AppStorage key, `false` by default; `SessionHistoryManager.record()` respects it; toggle in Settings → Privacy
- [x] **Frequency multiplier** — `userFrequencyMultiplier` in `LightEngine` (applied in phase accumulation); 0.5×–2.0× slider in Settings → Session Defaults; synced from `ContentView`
- [x] **Countdown start screen** — 3-2-1 animated overlay in `SessionPlayerView` before each session begins; haptic feedback at each count; controls auto-hide after playback starts
- [x] **Color pulse visual mode** — `ColorPulseView` with `TimelineView`-based hue-cycling brightness pulse at therapeutic frequency; visual mode selector (Flash / Color / Bilateral) in `MindMachineView`; safety warning shown before entering
- [x] **SettingsView SwiftLint compliance** — split into `SettingsView.swift` + `SettingsView+ProfileSection.swift` + `SettingsView+Sections.swift` (all under 400 lines)
- [x] **LightEngine SwiftLint compliance** — `tick()` function refactored into `updatePerformanceCounters`, `updateBilateralTransition`, `applySessionState`, `advanceFrequency`, `evaluateOscillator` helpers; cyclomatic complexity reduced from 22 → 3 in main tick

---

## PHASE 9: Advanced Features & Polish (Week 5)

### 9.1 Animations & Micro-interactions
**Priority: MEDIUM**
- [ ] **Implement all transition animations** per spec
- [ ] **Add haptic feedback** for interactions
- [ ] **Create loading states** with pulse animations
- [ ] **Add success/error states** with appropriate colors
- [ ] **Implement gesture recognizers** for advanced controls

### 9.2 Accessibility & Performance
**Priority: HIGH**
- [x] **Add VoiceOver labels** to all interactive elements
- [ ] **Implement Dynamic Type** support
- [ ] **Add reduce motion** alternatives
- [x] **Test color contrast ratios** per WCAG guidelines
- [ ] **Optimize rendering performance** for animations

### 9.3 Final Polish
**Priority: MEDIUM**
- [ ] **Create app icon** with rose-gold mandala design
- [x] **Update launch screen** with bgPrimary/roseGold
- [ ] **Add sound effects** for key interactions
- [x] **Implement onboarding flow** with new design
- [ ] **Create contextual help** system

---

## Technical Architecture Changes

### Design System Files
```
Ilumionate/
├── DesignSystem/
│   ├── TranceDesignSystem.swift (replaces IlluminateDesignSystem)
│   ├── Color+Extensions.swift (hex support)
│   ├── ViewModifiers/
│   │   ├── GlassBackground.swift
│   │   └── ShadowStyles.swift
│   └── Components/
│       ├── GlassCard.swift
│       ├── CategoryIcon.swift
│       ├── CTAButton.swift
│       ├── PhasePill.swift
│       ├── ProgressRingView.swift
│       ├── AudioScrubber.swift
│       ├── WaveformView.swift
│       ├── IntensityDial.swift
│       ├── PulseOrb.swift
│       ├── MandalaVisualizer.swift
│       └── FlashViews.swift
```

### Navigation Structure
```
├── Navigation/
│   ├── TranceTab.swift
│   ├── TranceTabBar.swift
│   └── ContentView.swift (redesigned)
├── Screens/
│   ├── Home/
│   │   ├── HomeView.swift (new)
│   │   └── Components/
│   ├── Player/
│   │   └── SessionPlayerView.swift (redesigned)
│   ├── MindMachine/
│   │   ├── MindMachineView.swift (redesigned)
│   │   └── FlashModeView.swift
│   ├── Library/
│   │   ├── AudioLibraryView.swift (redesigned)
│   │   └── SessionLibraryView.swift (redesigned)
│   └── Settings/
│       └── SettingsView.swift (redesigned)
```

---

## Migration Strategy

### Phase-by-Phase Implementation
1. **Week 1**: Foundation components and design system
2. **Week 2**: Home dashboard and navigation
3. **Week 3**: Player and Mind Machine interfaces
4. **Week 4**: Library and analyzer views
5. **Week 5**: Settings, profile, and final polish

### Backward Compatibility
- **Keep existing functionality** during redesign
- **Gradual replacement** of UI components
- **Maintain data persistence** and session compatibility
- **Test on all supported devices** throughout implementation

### Quality Assurance
- **Daily builds** with new components
- **Weekly design reviews** against specification
- **Accessibility testing** at each phase
- **Performance monitoring** for animations and rendering

---

## Success Metrics

### User Experience Goals
- **Visual Consistency**: All screens follow Trance design language
- **Smooth Performance**: 60fps animations, <100ms response times
- **Accessibility**: Full VoiceOver support, contrast compliance
- **Intuitive Navigation**: Clear information hierarchy and flow

### Technical Goals
- **Clean Architecture**: Modular, reusable components
- **Maintainable Code**: Well-documented, testable implementations
- **Performance**: Optimized for battery life during sessions
- **Compatibility**: iOS 17+, all device sizes and orientations

---

## File Organization Plan

### Files to Replace
- `DESIGN_PHILOSOPHY.md` → Delete (replaced by `app_design_spec.md`)
- `IlluminateDesignSystem.swift` → Replace with `TranceDesignSystem.swift`
- `ContentView.swift` → Complete redesign
- `SessionPlayerView.swift` → Complete redesign
- `AudioLibraryView.swift` → Complete redesign
- `SessionLibraryView.swift` → Complete redesign
- `SettingsView.swift` → Complete redesign

### New Files to Create
- `TranceDesignSystem.swift` - Complete design tokens
- `Color+Extensions.swift` - Hex color support
- `TranceTab.swift` - New navigation enum
- `TranceTabBar.swift` - Custom tab bar
- `HomeView.swift` - New dashboard
- All component files listed in architecture section

This comprehensive plan transforms Ilumionate into a premium light therapy app with world-class design, following the complete Trance specification while maintaining all existing functionality.