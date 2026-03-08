# 🎯 Accessibility & Contrast Guidelines for Ilumionate

## Critical Principle: Text MUST Be Readable

**Before implementing ANY text in the UI, you MUST verify adequate contrast for readability.**

## Text Contrast Standards (WCAG 2.1)

### Minimum Contrast Ratios
- **Normal Text**: 4.5:1 contrast ratio minimum
- **Large Text** (18pt+ or 14pt+ bold): 3:1 contrast ratio minimum
- **Enhanced (AAA)**: 7:1 for normal, 4.5:1 for large text

### Quick Reference for Common Backgrounds

#### Light Backgrounds
**✅ USE:**
- `.primary` (adapts to dark text automatically)
- `.secondary` (adapts to medium-dark text automatically)
- `Color.black` (maximum contrast)
- `Color(.label)` (system adaptive)
- `Color(.systemGray)` for secondary text

**❌ NEVER USE on light backgrounds:**
- `TherapeuticColors.primaryText` (#F0E8FF - very light lavender)
- `TherapeuticColors.secondaryText` (light purple with low opacity)
- White or very light colors
- Colors with insufficient contrast

#### Dark Backgrounds
**✅ USE:**
- `.primary` (adapts to light text automatically)
- `Color.white` (maximum contrast)
- `Color(.label)` (system adaptive)
- Light colors with sufficient contrast

**❌ NEVER USE on dark backgrounds:**
- Very dark colors
- Colors with insufficient contrast

## Implementation Rules

### 1. Always Use Semantic Colors When Possible
```swift
// ✅ GOOD - Adapts automatically to light/dark mode
Text("Welcome")
    .foregroundStyle(.primary)

Text("Subtitle")
    .foregroundStyle(.secondary)
```

### 2. Test Against Your Background
Before implementing custom colors:
```swift
// ❌ BAD - Don't assume colors work
Text("Title")
    .foregroundStyle(TherapeuticColors.primaryText) // This is light purple!

// ✅ GOOD - Use system adaptive colors
Text("Title")
    .foregroundStyle(.primary)
```

### 3. High-Contrast Custom Colors
When you must use custom colors, ensure proper contrast:
```swift
// For light backgrounds - use dark colors
struct HighContrastColors {
    static let darkText = Color(red: 0.1, green: 0.1, blue: 0.2)     // Very dark blue
    static let mediumText = Color(red: 0.3, green: 0.3, blue: 0.4)   // Medium gray
}

// For dark backgrounds - use light colors
struct HighContrastLightColors {
    static let lightText = Color(red: 0.95, green: 0.95, blue: 1.0)  // Off-white
    static let mediumLightText = Color(red: 0.8, green: 0.8, blue: 0.9) // Light gray
}
```

## Background Considerations

### Light Backgrounds That Need Dark Text
- `TherapeuticColors.luminousWhite`
- `LightMeshBackground()`
- Light gradients with white/very light colors
- Any background with light appearance

### Gradient Backgrounds
**Special Attention Required:**
```swift
// ❌ PROBLEMATIC - Text may be unreadable over parts of gradient
LinearGradient(colors: [.white, .purple], ...)

// ✅ SOLUTION - Use solid overlay or ensure text area has consistent contrast
ZStack {
    LinearGradient(colors: [.white, .purple], ...)

    // Option 1: Solid background for text area
    VStack {
        Text("Title")
            .foregroundStyle(.primary)
            .padding()
            .background(.regularMaterial) // Provides consistent background
    }

    // Option 2: Strong shadow/outline for text visibility
    Text("Title")
        .foregroundStyle(.primary)
        .shadow(color: .black.opacity(0.8), radius: 2, x: 1, y: 1)
}
```

## Testing Methods

### 1. Visual Testing
- Test on actual devices in various lighting conditions
- Check both light and dark mode
- Test with different accessibility text sizes

### 2. Accessibility Inspector
- Use Xcode's Accessibility Inspector
- Verify contrast ratios meet standards
- Test with VoiceOver enabled

### 3. Color Blindness Testing
- Test with color vision simulation
- Ensure text is readable for all color vision types

## Common Mistakes to Avoid

### ❌ Don't Do This
```swift
// Light text on light background - ILLEGIBLE
VStack {
    Text("Welcome")
        .foregroundStyle(TherapeuticColors.primaryText) // Light lavender
}
.background(TherapeuticColors.luminousWhite) // White background

// Colored text without contrast consideration
Text("Important")
    .foregroundStyle(TherapeuticColors.violet) // May not have enough contrast

// Assuming dark mode colors work in light mode
Text("Title")
    .foregroundStyle(Color(hex: "#F0E8FF")) // Light purple - invisible on light bg
```

### ✅ Do This Instead
```swift
// System adaptive colors
VStack {
    Text("Welcome")
        .foregroundStyle(.primary) // Automatically adapts

    Text("Subtitle")
        .foregroundStyle(.secondary) // Automatically adapts
}
.background(TherapeuticColors.luminousWhite)

// High contrast custom colors when needed
Text("Important")
    .foregroundStyle(.primary) // or custom dark color with verified contrast

// Proper contrast verification
Text("Title")
    .foregroundStyle(Color(.label)) // System label color
```

## Specific App Guidelines

### OnboardingView Fixed ✅
- Replaced all `TherapeuticColors.primaryText` with `.primary`
- Replaced all `TherapeuticColors.secondaryText` with `.secondary`
- Now fully readable on light backgrounds

### For Future Development
1. **Always start with semantic colors** (`.primary`, `.secondary`)
2. **Test immediately** - build and visually verify text readability
3. **Use contrast checkers** when implementing custom colors
4. **Consider accessibility settings** (large text, high contrast)

## Tools for Contrast Checking

### Online Tools
- WebAIM Contrast Checker
- Colour Contrast Analyser
- Stark (Figma/Sketch plugin)

### iOS Development
- Accessibility Inspector in Xcode
- iOS Simulator accessibility features
- VoiceOver testing

### Design Handoff
When receiving designs:
1. Verify all text meets contrast standards
2. Request accessible alternatives for low-contrast text
3. Document any accessibility concerns before implementation

## Emergency Fixes

If you discover poor contrast in production:

### Quick Fix Pattern
```swift
// Replace problematic text colors immediately
.foregroundStyle(TherapeuticColors.primaryText)
// ↓ Change to ↓
.foregroundStyle(.primary)

// For light backgrounds, use:
.foregroundStyle(.primary)        // Dark adaptive
.foregroundStyle(.secondary)      // Medium adaptive
.foregroundStyle(Color.black)     // Maximum contrast

// For dark backgrounds, use:
.foregroundStyle(.primary)        // Light adaptive
.foregroundStyle(Color.white)     // Maximum contrast
```

## Compliance Checklist

Before shipping any UI with text:

- [ ] All text has minimum 4.5:1 contrast ratio (3:1 for large text)
- [ ] Text is readable in both light and dark mode (if supported)
- [ ] Text remains readable with largest accessibility text size
- [ ] Color is not the only way information is conveyed
- [ ] High contrast mode is respected
- [ ] VoiceOver reads all text correctly

---

## Key Takeaway

**Text contrast is not optional - it's essential for accessibility and usability. Always verify readability before implementing any text styling.**

*Last Updated: March 5, 2026 - After OnboardingView contrast fixes*