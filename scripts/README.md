# Build Scripts

This directory contains build automation scripts for the RoomPlan app.

## Available Scripts

### 1. `build_archive.sh` - Create xcarchive for App Store submission

Creates an xcarchive file ready for distribution via App Store, TestFlight, or Ad-Hoc.

**Usage:**

```bash
# Build Release archive (default)
./scripts/build_archive.sh

# Build Debug archive
./scripts/build_archive.sh Debug

# Build Release archive (explicit)
./scripts/build_archive.sh Release
```

**What it does:**

1. Cleans previous build artifacts
2. Creates the `/build` directory (git-ignored)
3. Builds an xcarchive with proper signing
4. Saves archive with timestamp: `RoomPlanSimple_YYYYMMDD_HHMMSS.xcarchive`
5. Creates symlink: `RoomPlanSimple.xcarchive` → latest archive
6. Keeps last 5 archives (auto-cleanup)
7. Displays archive info (size, version, build number)

**Output:**

```
build/
├── RoomPlanSimple.xcarchive            → symlink to latest
├── RoomPlanSimple_20251207_184530.xcarchive
├── RoomPlanSimple_20251207_163022.xcarchive
└── RoomPlanSimple_20251207_121145.xcarchive
```

**Requirements:**

- Xcode installed
- Valid Apple Developer account
- Code signing configured (see `SETUP.md`)
- Optional: `xcbeautify` for prettier output (`brew install xcbeautify`)

**Next Steps After Archive:**

After the archive is created, you can:

1. **Open in Xcode Organizer:**
   ```
   Xcode → Window → Organizer
   ```

2. **Export IPA:**
   - Select the archive
   - Click "Distribute App"
   - Choose distribution method:
     - **App Store Connect** - For TestFlight/App Store
     - **Ad Hoc** - For testing on registered devices
     - **Enterprise** - If you have enterprise account
     - **Development** - For debugging

3. **Upload to App Store Connect:**
   - Select "App Store Connect" export
   - Follow Xcode prompts to upload

## Build Directory Structure

The `/build` directory is created automatically and contains:

```
build/
├── RoomPlanSimple.xcarchive              # Symlink to latest archive
├── RoomPlanSimple_YYYYMMDD_HHMMSS.xcarchive    # Timestamped archives
├── RoomPlanSimple_YYYYMMDD_HHMMSS.xcarchive
├── RoomPlanSimple_YYYYMMDD_HHMMSS.xcarchive
└── ...                                   # (keeps last 5 archives)
```

**Note:** The `/build` directory is git-ignored. Archives are not committed to version control.

## Troubleshooting

### "xcodebuild: command not found"
**Solution:** Install Xcode Command Line Tools:
```bash
xcode-select --install
```

### "No signing certificate found"
**Solution:** Configure code signing in Xcode:
1. Open project in Xcode
2. Select RoomPlanSimple target
3. Signing & Capabilities tab
4. Select your Team
5. See `SETUP.md` for detailed signing setup

### "Archive failed - Build input file cannot be found"
**Solution:** Clean derived data and try again:
```bash
rm -rf ~/Library/Developer/Xcode/DerivedData/RoomPlanSimple-*
./scripts/build_archive.sh
```

### "Automatic signing is disabled"
**Solution:** The script uses `-allowProvisioningUpdates` flag. Make sure:
1. Xcode is configured with your Apple ID
2. Automatic signing is enabled in project settings
3. Or manually select provisioning profile

## Tips

### Faster Builds

Install `xcbeautify` for cleaner, faster build output:
```bash
brew install xcbeautify
```

The script will automatically use it if available.

### Check Archive Info

To inspect an archive:
```bash
# List all archives
ls -lh build/*.xcarchive

# Check app info in archive
/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" \
  build/RoomPlanSimple.xcarchive/Products/Applications/RoomPlanSimple.app/Info.plist
```

### Clean Old Archives

The script keeps the last 5 archives. To manually clean:
```bash
# Remove all archives
rm -rf build/*.xcarchive

# Remove archives older than 7 days
find build -name "*.xcarchive" -mtime +7 -delete
```

## CI/CD Integration

This script is designed to be CI/CD friendly:

**GitHub Actions:**
```yaml
- name: Build Archive
  run: ./scripts/build_archive.sh Release

- name: Upload Archive
  uses: actions/upload-artifact@v3
  with:
    name: RoomPlanSimple-Archive
    path: build/RoomPlanSimple.xcarchive
```

**Exit Codes:**
- `0` - Success
- `1` - Build failed
- `1` - Invalid configuration parameter

## Version Management

Before building for App Store:

1. **Update version number:**
   - Xcode → Target → General → Version
   - Or edit `Info.plist`

2. **Update build number:**
   - Should increment for each submission
   - Xcode → Target → General → Build

3. **Commit version changes:**
   ```bash
   git add RoomPlanSimple/Info.plist
   git commit -m "Bump version to X.Y.Z (build N)"
   ```

## File Sizes

Typical archive sizes:
- Debug: ~50-80 MB
- Release: ~30-50 MB

Final IPA (after export):
- App Store: ~20-40 MB
- Ad Hoc: ~25-45 MB

## Security Notes

⚠️ **Important:**
- Archives may contain debug symbols and metadata
- The `/build` directory is git-ignored to prevent committing large files
- Never commit `.xcarchive` files to version control
- Archives contain your app binary and resources

## Additional Resources

- [Apple's Archiving Guide](https://developer.apple.com/documentation/xcode/distributing-your-app-for-beta-testing-and-releases)
- [App Store Connect Help](https://help.apple.com/app-store-connect/)
- [TestFlight Beta Testing](https://developer.apple.com/testflight/)

---

**Last Updated:** December 7, 2025
**Script Version:** 1.0
