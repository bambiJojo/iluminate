# Hypnosis Analysis Enhancements

## Overview
This document describes the comprehensive enhancements made to improve the app's ability to classify and analyze hypnosis audio files at an expert level.

## Implemented Features

### 1. Enhanced Speech Recognition Vocabulary ✅
**File**: `AudioAnalyzer.swift:79-110`

Added extensive contextual vocabulary for superior speech recognition accuracy:
- **Hypnosis-specific terms**: induction, deepening, trance, suggestions, anchor, subconscious, fractionation, post-hypnotic
- **Hypnotic language patterns**: "deeper and deeper", "letting go", "drifting down", "heavy eyelids"
- **Therapy modalities**: regression, parts therapy, ego state, metaphor, catalepsy, amnesia, analgesia
- **Trance depth indicators**: deep trance, light trance, somnambulism, altered state, theta state
- **Meditation terms**: Retained all original meditation vocabulary for comprehensive coverage

**Impact**: Significantly improves transcription accuracy for hypnosis-specific terminology and phrases.

---

### 2. Comprehensive Metadata Models ✅
**File**: `AudioFile.swift:56-180`

#### Enhanced AnalysisResult
- Added `ContentType` enum: hypnosis, meditation, music, guidedImagery, affirmations, unknown
- Added optional fields for specialized analysis:
  - `hypnosisMetadata: HypnosisMetadata?`
  - `temporalAnalysis: TemporalAnalysis?`
  - `voiceCharacteristics: VoiceCharacteristics?`
  - `classificationConfidence: ClassificationConfidence?`

#### HypnosisMetadata Structure
Captures detailed hypnosis session information:
- **Phases**: Array of phase segments (pre-talk, induction, deepening, therapy, suggestions, emergence)
- **InductionStyle**: progressive, authoritarian, permissive, confusion, rapid, ericksonian, conversational
- **TranceDeph**: light, medium, deep, somnambulism
- **Suggestion density**: Suggestions per minute
- **Language patterns**: Detected patterns like metaphors, embedded commands
- **Detected techniques**: Array of hypnotic techniques with timestamps

#### TemporalAnalysis Structure
Tracks evolution over time:
- **Trance depth curve**: Sampled at regular intervals (0.0-1.0)
- **Receptivity levels**: Suggestion receptivity over time
- **Emotional arc**: Emotional descriptors at intervals
- **Sampling interval**: Time between samples

#### VoiceCharacteristics Structure
Prosody and delivery analysis:
- Average speaking pace (words per minute)
- Pace variation (standard deviation)
- Pause patterns (significant pauses)
- Tonal qualities (soothing, authoritative, rhythmic)
- Volume pattern (steady, gradually quieter, dynamic)

#### ClassificationConfidence Structure
Confidence metrics:
- Overall confidence score (0.0-1.0)
- Boolean flag for definite hypnosis classification
- Ambiguous segments requiring review
- Alternative interpretations
- Detection criteria used

---

### 3. Intelligent Content Detection ✅
**File**: `AIContentAnalyzer.swift:75-113`

Analyzes transcription to determine content type with keyword matching and threshold-based classification.

---

### 4. Specialized Expert Prompts ✅
**File**: `AIContentAnalyzer.swift:307-380`

#### Hypnosis Expert Instructions
- **Role**: Expert in clinical hypnosis, Ericksonian hypnotherapy, neuroscience
- **Analysis focus**: Phase identification, induction style, trance depth, language patterns
- **Light therapy recommendations**: Beta → Alpha → Theta progression, synchronized pulsing
- **Brainwave guidance**: Beta (12-30Hz), Alpha (8-12Hz), Theta (4-8Hz), Delta (0.5-4Hz)

---

### 5. Multi-Pass Analysis System ✅
**File**: `AIContentAnalyzer.swift:382-444`

Two-stage analysis for hypnosis:
- **Pass 1**: Structural analysis (phases, techniques, confidence)
- **Pass 2**: Therapeutic analysis (temporal curves, voice, recommendations)
- Combined into comprehensive result

---

### 6. Structured AI Response Types ✅
**File**: `AIContentAnalyzer.swift:326-527`

All structures use `@Generable` and `@Guide` for type-safe AI responses.

---

## Benefits

### For Hypnosis Content
- Expert-level understanding of hypnotic processes
- Phase-by-phase breakdown with precise timing
- Trance depth tracking over time
- Technique identification with light sync recommendations
- Language pattern analysis
- Voice prosody insights
- Confidence metrics for classification

### For All Content
- Automatic content type detection
- Specialized analysis based on content type
- Backward compatible with existing analysis
- Extensible architecture

---

## Build Status

✅ **All changes successfully compiled and built**
✅ **No errors or warnings**
✅ **Ready for testing**

---

## Classification Guide Integration ✅

### 7. Professional Hypnosis Classification Taxonomy
**File**: `HYPNOSIS_CLASSIFICATION_GUIDE.md`

Integrated a comprehensive classification guide that provides:

#### Phase Taxonomy (Phases 0-5)
- **Phase 0 - Pre-Talk**: Safety, authority, expectation setting
- **Phase 1 - Induction**: Narrow attention, enter trance
- **Phase 2 - Deepening**: Intensify absorption, amplify depth
- **Phase 3 - Utilization/Therapeutic**: Use trance to produce change
- **Phase 4 - Conditioning**: Post-hypnotic structuring and future pacing
- **Phase 5 - Emergence**: Safe return to baseline consciousness
- **Transitional States**: Support for blended phases (induction→deepening)

#### Classification Rules
- Classify by GOAL and INTENT, not technique name
- One passage = one dominant phase
- Handle Ericksonian conversational trance
- Confidence levels: High / Medium / Low with rationale

#### Enhanced Phase Structure
Added to `HypnosisMetadata.Phase`:
- `.conditioning` phase for post-hypnotic work
- `.transitional` phase for blended states
- `displayName` computed property
- `ConfidenceLevel` enum (high/medium/low)

#### Linguistic Marker System
**File**: `AudioFile.swift` - `LinguisticMarker` structure

40+ specific marker types organized by phase:
- **Pre-Talk markers**: normalization, expectation setting, rapport building, suggestibility testing
- **Induction markers**: eye fixation, breathing focus, progressive relaxation, sensory narrowing
- **Deepening markers**: counting down, descending imagery, fractionation, heaviness/lightness
- **Therapeutic markers**: direct/indirect suggestions, metaphors, embedded commands, ego strengthening
- **Conditioning markers**: future pacing, anchoring, trigger installation, cause-effect framing
- **Emergence markers**: counting up, eye opening, physical re-engagement, temporal orientation
- **Ericksonian markers**: pacing/leading, ambiguous language, conversational trance, utilization

Each marker includes:
- Type classification
- Timestamp
- Optional text snippet
- Strength indicator (0.0-1.0)

#### Enhanced PhaseSegment Structure
Now includes:
- `linguisticMarkers: [LinguisticMarker]` - Detected markers in this phase
- `confidenceLevel: ConfidenceLevel` - High/Medium/Low classification confidence
- `confidenceRationale: String?` - Explanation of why this phase was classified
- `transitionTarget: Phase?` - For transitional phases, what phase is it transitioning to

#### Updated Expert Prompt
**File**: `AIContentAnalyzer.swift` - `getHypnosisExpertInstructions()`

Comprehensive 80+ line expert prompt including:
- Core principle: "Hypnosis is a PROCESS"
- Complete phase taxonomy with goals and markers
- Classification rules from the guide
- Transitional phase handling
- Ericksonian special cases
- Confidence level guidelines
- Required output format with rationale

#### Enhanced Structural Analysis
**File**: `AIContentAnalyzer.swift` - `buildHypnosisStructuralPrompt()`

Requests detailed analysis:
- Phase classification with confidence and rationale
- Specific linguistic markers for each phase
- Trance depth estimation based on evidence
- Induction style classification
- Hypnotic technique identification
- Language pattern detection
- Overall confidence with criteria

#### Intelligent Marker Parsing
**File**: `AIContentAnalyzer.swift` - `parseLinguisticMarker()`

Maps natural language descriptions to marker types:
- Handles variations ("eye closure" → `.eyeFixation`)
- Partial matching for flexibility
- 40+ marker type mappings
- Extensible architecture

---

## Files Modified

1. ✅ `AudioAnalyzer.swift` - Enhanced contextual vocabulary
2. ✅ `AudioFile.swift` - Comprehensive metadata models + linguistic markers
3. ✅ `AIContentAnalyzer.swift` - Content detection, specialized prompts, multi-pass analysis, classification guide integration
4. ✅ `HYPNOSIS_CLASSIFICATION_GUIDE.md` - Professional taxonomy reference

**Total lines added**: ~800+ lines of expert-level hypnosis analysis code

---

## Key Improvements from Classification Guide

### More Precise Analysis
- **Goal-based classification** instead of technique-based
- **Transitional phase support** for realistic hypnosis sessions
- **Ericksonian pattern recognition** for naturalistic trance
- **Confidence rationales** explain why each classification was made

### Better AI Understanding
- Clear taxonomy prevents hallucination
- "Do NOT assume depth equals effectiveness" prevents over-interpretation
- "Classify by intent, not format" handles diverse styles
- Explicit rules prevent false positives

### Enhanced Data Quality
- Each phase includes detected linguistic markers
- Confidence levels guide users on reliability
- Rationales make AI reasoning transparent
- Transitional phases capture real-world complexity

### Professional Standards
- Based on clinical hypnosis principles
- Recognizes authoritarian, permissive, Ericksonian styles
- Supports all phases from pre-talk through emergence
- Handles post-hypnotic conditioning explicitly

---

## Usage Example with New Features

```swift
// Analyze hypnosis file
let result = try await analyzer.analyzeContent(
    transcription: transcription,
    audioFile: audioFile
)

if let hypnosis = result.hypnosisMetadata {
    for phase in hypnosis.phases {
        print("\(phase.phase.displayName): \(phase.startTime)s - \(phase.endTime)s")
        print("Confidence: \(phase.confidenceLevel.rawValue)")
        print("Rationale: \(phase.confidenceRationale ?? "N/A")")

        // Check for transitional phase
        if phase.phase == .transitional, let target = phase.transitionTarget {
            print("Transitioning to: \(target.displayName)")
        }

        // Show detected linguistic markers
        print("Markers detected:")
        for marker in phase.linguisticMarkers {
            print("  - \(marker.type) (strength: \(marker.strength))")
        }
    }
}
```
