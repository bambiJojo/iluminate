# Session Loading Troubleshooting Guide

## Issue: No Sessions Appearing

If you see "No Sessions Found" in the app, here's how to fix it:

## ✅ Step 1: Check Console Output

Look for these messages in Xcode console:

```
🔍 Discovering bundled sessions...
📦 Found 0 session files: []
```

If it says "Found 0", your JSON files aren't in the bundle.

## ✅ Step 2: Verify JSON Files Are Added

### Check Target Membership

1. In Xcode, select a JSON file (e.g., `deep_relaxation_session.json`)
2. Open **File Inspector** (right sidebar, first tab)
3. Under "Target Membership", ensure your app target is **checked** ✅

**If unchecked:**
- Click the checkbox to enable it
- Rebuild the app

### Verify File Location

Your JSON files should be in your Xcode project:
```
YourProject/
  ├── deep_relaxation_session.json  ✅
  ├── focused_trance_session.json   ✅
  ├── hypnagogic_drift_session.json ✅
  └── ...
```

**NOT** in a subfolder unless you update the code.

## ✅ Step 3: Verify JSON Format

Each session file must be **valid JSON**:

```json
{
  "session_name": "Deep Relaxation",
  "duration_sec": 720,
  "light_score": [
    {
      "time": 0,
      "frequency": 10.0,
      "intensity": 0.2,
      "waveform": "sine"
    }
  ]
}
```

### Common JSON Errors:
- ❌ Missing comma between objects
- ❌ Trailing comma after last item
- ❌ Unquoted keys
- ❌ Wrong file extension (must be `.json`)

**Validate JSON:** Use [jsonlint.com](https://jsonlint.com)

## ✅ Step 4: Check File Names

Files should have `.json` extension:
- ✅ `deep_relaxation_session.json`
- ❌ `deep_relaxation_session.txt`
- ❌ `deep_relaxation_session`

## ✅ Step 5: Clean Build

If files are correct but still not loading:

1. **Product** → **Clean Build Folder** (⇧⌘K)
2. **Product** → **Build** (⌘B)
3. Run the app again

## ✅ Step 6: Check Console for Errors

If sessions are discovered but fail to load:

```
📦 Found 3 session files: ["deep_relaxation_session", ...]
📖 Loading session: deep_relaxation_session
❌ Failed to load session 'deep_relaxation_session': Invalid JSON...
```

This means:
- File was found ✅
- JSON parsing failed ❌
- Check JSON syntax

## 🔧 Quick Test: Create Minimal Session

Create a test file `test_session.json`:

```json
{
  "session_name": "Test Session",
  "duration_sec": 60,
  "light_score": [
    {
      "time": 0,
      "frequency": 10.0,
      "intensity": 0.5,
      "waveform": "sine"
    },
    {
      "time": 60,
      "frequency": 8.0,
      "intensity": 0.7,
      "waveform": "sine"
    }
  ]
}
```

**Add to project → Enable target membership → Run**

If this works, your setup is correct!

## 📋 Expected Console Output (Success)

```
🔍 Discovering bundled sessions...
📦 Found 3 session files: ["deep_relaxation_session", "focused_trance_session", "hypnagogic_drift_session"]
📖 Loading session: deep_relaxation_session
✅ Loaded: Deep Relaxation
📖 Loading session: focused_trance_session
✅ Loaded: Focused Trance
📖 Loading session: hypnagogic_drift_session
✅ Loaded: Hypnagogic Drift
🎉 Successfully loaded 3 sessions
```

## 🐛 Common Issues

### Issue 1: Files in wrong location
**Symptom:** Found 0 files
**Fix:** Drag JSON files into Xcode project (not just Finder)

### Issue 2: Target membership not set
**Symptom:** Found 0 files
**Fix:** Check target membership in File Inspector

### Issue 3: Invalid JSON syntax
**Symptom:** Found N files, but failed to load
**Fix:** Validate JSON at jsonlint.com

### Issue 4: Wrong file extension
**Symptom:** Found 0 files
**Fix:** Ensure files end with `.json`

### Issue 5: Duplicate SessionLockView_new.swift
**Symptom:** Build errors
**Fix:** Delete SessionLockView_new.swift from project

## ✅ Verification Checklist

Before running:
- [ ] JSON files are in Xcode project
- [ ] Target membership is enabled for each file
- [ ] Files have `.json` extension
- [ ] JSON syntax is valid
- [ ] Project builds without errors
- [ ] Console shows session discovery logs

## 🎯 Quick Fix: Bundle All Sessions

Make sure these files are in your bundle:

1. `deep_relaxation_session.json`
2. `focused_trance_session.json`
3. `hypnagogic_drift_session.json`
4. `bilateral_wave_pattern.json` (if you created it)
5. `evening_wind_down.json` (if you created it)
6. `morning_energizer.json` (if you created it)

**Each one needs:**
- ✅ Added to Xcode project
- ✅ Target membership checked
- ✅ Valid JSON syntax
- ✅ `.json` extension

## 💡 Tip: Start Simple

If overwhelmed, start with just **one** session file:

1. Create `test_session.json` (see minimal example above)
2. Add to Xcode
3. Enable target membership
4. Run app
5. See if it appears

Once one works, add the rest!

## 🆘 Still Not Working?

Check the console output and look for:
- How many files were found?
- What are their names?
- Are there any error messages?

The console logs will tell you exactly what's wrong! 🔍
