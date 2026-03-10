# Archive Configuration Guide

## How to Check if Archive is Debug or Release

### Method 1: Check the Archive Path
The configuration is in the filename/path when built:
```bash
# Release archive will be in:
build/RoomPlanSimple_YYYYMMDD_HHMMSS.xcarchive

# The script shows configuration in the build output:
Configuration: Release  ← or Debug
```

### Method 2: Check with xcodebuild
```bash
xcodebuild -showBuildSettings -scheme RoomPlanSimple -configuration Release | grep "CONFIGURATION ="
# Output: CONFIGURATION = Release
```

### Method 3: Check Archive in Xcode Organizer
1. Open Xcode Organizer: `Window → Organizer`
2. Select your archive
3. Look at the right panel - it shows the configuration

### Method 4: Inspect Build Settings in Archive
```bash
# Check the build directory name in DerivedData
ls ~/Library/Developer/Xcode/DerivedData/RoomPlanSimple-*/Build/Products/
# Will show: Release-iphoneos/ or Debug-iphoneos/
```

## Which Configuration for Beta Testing?

### ✅ For TestFlight / App Store Beta Testing:
**Use: RELEASE**

```bash
./scripts/build_archive.sh Release
# or simply:
./scripts/build_archive.sh
```

**Why Release?**
- ✅ Optimized code (smaller, faster)
- ✅ No debug symbols visible to users
- ✅ Matches production environment
- ✅ Required by App Store Connect
- ✅ Better battery life
- ✅ Smaller download size

**Characteristics:**
- Size: ~30-50 MB (archive), ~20-40 MB (IPA)
- Optimizations: Enabled
- Debug Info: Minimal (dSYM separate)
- Logging: Reduced
- Assertions: Disabled

### 🔧 For Internal Testing / Development:
**Use: DEBUG**

```bash
./scripts/build_archive.sh Debug
```

**Why Debug?**
- ✅ Full debug symbols
- ✅ Easier to diagnose crashes
- ✅ More logging output
- ✅ Assertions enabled
- ❌ Larger file size
- ❌ Slower performance
- ❌ NOT accepted by App Store Connect

**Characteristics:**
- Size: ~50-80 MB (archive), ~30-60 MB (IPA)
- Optimizations: Disabled
- Debug Info: Full
- Logging: Verbose
- Assertions: Enabled

## Quick Reference Table

| Use Case | Configuration | Command |
|----------|---------------|---------|
| **App Store submission** | Release | `./scripts/build_archive.sh` |
| **TestFlight beta** | Release | `./scripts/build_archive.sh Release` |
| **Ad-Hoc distribution** | Release | `./scripts/build_archive.sh Release` |
| **Internal QA testing** | Release* | `./scripts/build_archive.sh Release` |
| **Debugging crashes** | Debug | `./scripts/build_archive.sh Debug` |
| **Development** | Debug | `./scripts/build_archive.sh Debug` |

*For QA testing, use Release to match production, but keep Debug builds for investigating issues.

## TestFlight Beta Testing - Step by Step

### 1. Build Release Archive
```bash
./scripts/build_archive.sh Release
```

### 2. Check Archive Configuration
The script output will show:
```
Configuration: Release  ← Confirm this says "Release"
Version: 1.1
Build: 1
```

### 3. Open Xcode Organizer
```
Xcode → Window → Organizer
```

### 4. Distribute to TestFlight
1. Select the archive (newest at top)
2. Click "Distribute App"
3. Choose **"App Store Connect"**
4. Follow prompts:
   - Select destination: **"Upload"**
   - App Store Connect distribution options
   - Re-sign if needed
   - Review summary
   - Upload!

### 5. Verify in App Store Connect
1. Go to [App Store Connect](https://appstoreconnect.apple.com)
2. Select your app
3. Go to **TestFlight** tab
4. Wait for processing (~5-30 minutes)
5. Add to test groups
6. Send invites to testers

## Differences Between Debug and Release

### Code Optimization
```swift
// Debug:
// - Every line executed as written
// - Variables kept around for inspection
// - No inlining, no optimizations

// Release:
// - Aggressive optimizations
// - Dead code elimination
// - Function inlining
// - Faster execution
```

### Binary Size Comparison

**Example from typical build:**
```
Debug Archive:    62 MB
Release Archive:  38 MB
Reduction:        ~39% smaller

Debug IPA:        45 MB
Release IPA:      28 MB
Reduction:        ~38% smaller
```

### Performance Comparison

**Typical performance differences:**
- App launch: Release ~2x faster
- Rendering: Release ~1.5-3x faster
- CPU usage: Release ~30-50% less
- Battery drain: Release significantly better

## Common Mistakes

### ❌ Mistake 1: Using Debug for TestFlight
**Problem:** App Store Connect will reject it
```
Error: "The bundle RoomPlanSimple.app doesn't contain
an optimized build. Make sure you build with Release configuration."
```

**Solution:** Build with Release:
```bash
./scripts/build_archive.sh Release
```

### ❌ Mistake 2: Testing Release locally and thinking it's Debug
**Problem:** Can't debug crashes, no breakpoints work

**Solution:** Keep separate archives:
```bash
# For local development/debugging
./scripts/build_archive.sh Debug

# For TestFlight/App Store
./scripts/build_archive.sh Release
```

### ❌ Mistake 3: Not updating version/build before Release
**Problem:** App Store Connect rejects duplicate build numbers

**Solution:** Increment build number before archiving:
1. Xcode → Target → General → Build: `2` (increment)
2. Or in Info.plist: `CFBundleVersion`

## Archive Management

### Keep Both Configurations Organized

The script automatically timestamps archives. You can have both:

```
build/
├── RoomPlanSimple.xcarchive → latest (Release)
├── RoomPlanSimple_20251207_185238.xcarchive  (Release)
├── RoomPlanSimple_20251207_120000.xcarchive  (Debug)
└── ...
```

### Name Archives by Purpose

You can rename after building:
```bash
# Build Release
./scripts/build_archive.sh Release

# Rename for clarity
mv build/RoomPlanSimple_20251207_185238.xcarchive \
   build/RoomPlanSimple_v1.1_TestFlight.xcarchive

# Build Debug
./scripts/build_archive.sh Debug

mv build/RoomPlanSimple_20251207_190000.xcarchive \
   build/RoomPlanSimple_v1.1_Debug.xcarchive
```

## Verification Checklist

Before uploading to TestFlight, verify:

- ✅ Configuration: **Release** (check script output)
- ✅ Version number: Updated (e.g., 1.1 → 1.2)
- ✅ Build number: Incremented (e.g., 1 → 2)
- ✅ Archive size: ~30-50 MB (not 60-80 MB)
- ✅ Code signing: Valid certificate
- ✅ Tested on device: Release build works
- ✅ No debug code: Removed print statements, test code
- ✅ Info.plist: Correct bundle ID, version

## Quick Verification Commands

```bash
# Check configuration from build settings
xcodebuild -showBuildSettings -scheme RoomPlanSimple -configuration Release | grep "^[[:space:]]*CONFIGURATION ="

# Check archive size (Release should be smaller)
du -sh build/RoomPlanSimple*.xcarchive

# Check app version in archive
/usr/libexec/PlistBuddy -c "Print :ApplicationProperties:CFBundleShortVersionString" \
  build/RoomPlanSimple.xcarchive/Info.plist

# Check build number in archive
/usr/libexec/PlistBuddy -c "Print :ApplicationProperties:CFBundleVersion" \
  build/RoomPlanSimple.xcarchive/Info.plist
```

## Summary

**For your beta test on TestFlight:**

1. ✅ **Use RELEASE configuration**
2. ✅ Run: `./scripts/build_archive.sh Release` (or just `./scripts/build_archive.sh`)
3. ✅ Verify output says "Configuration: Release"
4. ✅ Upload to App Store Connect via Xcode Organizer
5. ✅ Distribute via TestFlight

**Never use Debug for:**
- ❌ App Store submission
- ❌ TestFlight distribution
- ❌ Production releases
- ❌ Public beta testing

**Use Debug only for:**
- ✅ Local development
- ✅ Debugging specific issues
- ✅ Investigating crashes

---

**Quick Answer:** For TestFlight beta testing, use **RELEASE** configuration!

```bash
./scripts/build_archive.sh Release
```

or simply:

```bash
./scripts/build_archive.sh
```

(Release is the default)
