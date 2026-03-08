# 🚀 TestFlight Release Checklist

## Pre-Build Checklist

### ✅ Version Management
- [x] **Marketing Version**: Updated to 1.0.0 (semantic versioning)
- [x] **Build Number**: Set to 1001 (TestFlight requires unique build numbers)
- [x] **Bundle Identifier**: com.byronquine.Ilumionate (verify matches App Store Connect)
- [x] **Development Team**: Set to your Apple Developer Team ID

### ✅ App Configuration
- [x] **Target iOS Version**: Currently set to iOS 26.0 (will need to be lowered to iOS 16.0+ for wider compatibility)
- [x] **Device Support**: iPhone and iPad (Universal)
- [x] **Code Signing**: Automatic (ensure valid certificates)
- [x] **App Icon**: Verify all required sizes are included

### ✅ Privacy & Permissions
- [x] **Microphone Permission**: Only requested if user chooses to record audio
- [x] **File Access**: For importing audio files from user's library
- [x] **Privacy Policy**: Created and ready for App Store Connect
- [x] **Data Collection**: Minimal - all processing on-device

### ✅ Content & Compliance
- [x] **Session Files**: All 12 sessions + welcome_introduction.json included in bundle
- [x] **Content Rating**: 4+ (suitable for all ages)
- [x] **Export Compliance**: No encryption beyond standard iOS - exempt
- [x] **Medical Disclaimer**: Included in privacy policy and app

## Build Process

### 🏗️ Archive Creation
1. **Clean Build Folder**
   ```bash
   xcodebuild clean -project Ilumionate.xcodeproj -scheme Ilumionate
   ```

2. **Create Release Archive**
   ```bash
   xcodebuild archive \
     -project Ilumionate.xcodeproj \
     -scheme Ilumionate \
     -configuration Release \
     -destination "generic/platform=iOS" \
     -archivePath "./Ilumionate.xcarchive"
   ```

3. **Export for TestFlight**
   ```bash
   xcodebuild -exportArchive \
     -archivePath "./Ilumionate.xcarchive" \
     -exportPath "./TestFlightBuild" \
     -exportOptionsPlist ExportOptions.plist
   ```

### 📋 Export Options (ExportOptions.plist)
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>app-store</string>
    <key>destination</key>
    <string>upload</string>
    <key>uploadBitcode</key>
    <false/>
    <key>uploadSymbols</key>
    <true/>
    <key>compileBitcode</key>
    <false/>
</dict>
</plist>
```

## App Store Connect Setup

### 📱 App Information
- **Name**: Ilumionate
- **Subtitle**: Light Therapy & Photoentrainment
- **Category**: Health & Fitness (Primary), Medical (Secondary)
- **Content Rating**: 4+ (No Restricted Content)

### 📝 App Description
```
Discover the power of light therapy with Ilumionate - an innovative app that uses photoentrainment to promote relaxation, enhance focus, and improve well-being.

KEY FEATURES:
• 12 expertly crafted light therapy sessions
• AI-powered custom session generation from your audio
• Bilateral stimulation for enhanced therapeutic effects
• Beautiful, calming user interface
• Complete onboarding with guided introduction
• Playlist management for personalized experiences

WHAT IS PHOTOENTRAINMENT?
Light therapy uses gentle, rhythmic light patterns to guide your brainwaves into desired states. This natural process can help with relaxation, meditation, focus, and overall well-being.

PRIVACY FIRST:
• All AI analysis happens on your device
• No data transmitted to external servers
• Your audio files remain private and secure

Start your light therapy journey today with Ilumionate.
```

### 🏷️ Keywords
```
light therapy, photoentrainment, meditation, relaxation, focus, wellness, brainwave, bilateral, therapy, mindfulness
```

### 📸 App Store Assets
**Screenshots Needed** (prepare these):
- iPhone 15 Pro Max: 6.7" (1290 x 2796)
- iPhone 15: 6.1" (1179 x 2556)
- iPad Pro 12.9": (2048 x 2732)

**App Preview Videos** (optional but recommended):
- 30-second demo of onboarding
- Light session demonstration
- Audio import and custom session creation

### ⚠️ Age Rating Questionnaire
- **17+ Rating**: NO (no mature content)
- **Made for Kids**: NO
- **Simulated Gambling**: NO
- **Contests**: NO
- **Unrestricted Web Access**: NO
- **Shares Location**: NO

## TestFlight Configuration

### 🧪 Beta App Information
**Beta App Name**: Ilumionate Beta
**Beta App Description**:
```
Welcome to the Ilumionate beta!

Help us perfect this innovative light therapy app. Test features including:
• Complete onboarding experience
• Pre-built light therapy sessions
• Custom audio analysis and session generation
• Playlist management
• Performance and stability

Please review the Beta Release Notes and Testing Guide for detailed instructions.

Your feedback is invaluable - thank you for being part of the journey!
```

### 👥 Beta Groups
1. **Internal Testing**: Development team and close contacts (max 100)
2. **External Testing**: Public beta testers (max 1000)

### 📧 Beta Tester Communications
**Welcome Email Template**:
```
Subject: Welcome to Ilumionate Beta! 🌟

Thank you for joining the Ilumionate beta program!

WHAT YOU'LL NEED:
• TestFlight app installed
• iOS 18+ device (iPhone 12+ or iPad 9th gen+)
• 30 minutes for initial testing

GETTING STARTED:
1. Download from the TestFlight link below
2. Complete the onboarding flow
3. Try the welcome session (3 minutes)
4. Explore the session library

IMPORTANT DOCUMENTS:
• Beta Release Notes: [Link]
• Tester Guide: [Link]
• Privacy Policy: [Link]

We're excited to hear your feedback!
```

## Pre-Upload Verification

### ✅ Final Testing
- [ ] Archive builds successfully
- [ ] App launches without crashes on test device
- [ ] Onboarding flow works end-to-end
- [ ] Core sessions play successfully
- [ ] Audio import/analysis works
- [ ] No debug code or test data in release build

### ✅ Compliance Check
- [ ] All debug logging removed or disabled in release
- [ ] No development/test URLs or keys
- [ ] Privacy strings appropriate for App Store review
- [ ] Export compliance declaration ready
- [ ] Content rating accurately reflects app content

### ✅ Documentation Ready
- [ ] Beta Release Notes uploaded to TestFlight
- [ ] Testing Guide shared with beta testers
- [ ] Privacy Policy accessible via app or website
- [ ] Support contact information current

## Upload Process

### 🚀 Upload Steps
1. **Upload via Xcode**
   - Archive → Distribute App → App Store Connect
   - Select "Upload" (not "Export")
   - Include symbols and debug info

2. **Upload via Transporter**
   - Export .ipa from Xcode
   - Use Transporter app for upload
   - Monitor upload progress

3. **Upload via Command Line**
   ```bash
   xcrun altool --upload-app \
     --type ios \
     --file "Ilumionate.ipa" \
     --username "your-apple-id" \
     --password "@keychain:APP_SPECIFIC_PASSWORD"
   ```

### ⏰ Processing Time
- **Upload**: 5-30 minutes depending on file size
- **Processing**: 30-60 minutes for App Store Connect processing
- **TestFlight Availability**: 10-30 minutes after processing
- **Review for External Testing**: 24-48 hours (Apple review)

## Post-Upload Checklist

### ✅ App Store Connect Verification
- [ ] Build appears in App Store Connect
- [ ] Build status shows "Ready for Beta Testing"
- [ ] All required metadata complete
- [ ] Screenshots and descriptions uploaded
- [ ] Pricing and availability configured

### ✅ TestFlight Setup
- [ ] Add build to beta groups
- [ ] Upload beta release notes
- [ ] Configure external testing (if ready)
- [ ] Send invitations to internal testers

### ✅ Communication
- [ ] Notify beta testers of new build
- [ ] Share testing guides and documentation
- [ ] Set up feedback monitoring
- [ ] Establish regular update schedule

## Monitoring & Feedback

### 📊 Key Metrics to Track
- **Adoption**: Download and installation rates
- **Usage**: Session completion rates, feature usage
- **Stability**: Crash rates, performance metrics
- **Feedback**: Star ratings, written feedback quality

### 🔍 Common Issues to Watch For
- Memory usage on older devices
- Battery drain during sessions
- Audio sync problems
- UI/UX confusion points
- Onboarding drop-off rates

### 📈 Success Criteria
- [ ] <1% crash rate across all devices
- [ ] >80% onboarding completion rate
- [ ] >4.0 average beta rating
- [ ] <2 second app launch time
- [ ] Positive feedback on core features

---

**Ready for TestFlight**: Once this checklist is complete, your app is ready for beta testing! 🎉

*Last Updated: March 5, 2026*