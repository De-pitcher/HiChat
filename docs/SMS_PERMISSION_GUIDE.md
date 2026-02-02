# 📱 How to Grant SMS Permissions to HiChat App

## Quick Start Guide

### Method 1: Let the App Request Permissions (Recommended)

1. **Run the permission test app:**
   ```bash
   flutter run sms_permission_guide.dart
   ```

2. **Follow these steps in the app:**
   - Tap "Request SMS Permission"
   - Android will show a permission dialog
   - Tap "Allow" to grant SMS access
   - The app will confirm permissions are granted

### Method 2: Manual Permission Grant

If the automatic request doesn't work, grant permissions manually:

1. **Open Android Settings:**
   - Go to Settings on your Android device
   - Navigate to "Apps" or "Application Manager"
   - Find and tap on "HiChat"

2. **Grant SMS Permissions:**
   - Tap on "Permissions"
   - Find "SMS" in the list
   - Toggle it to "Allow" or "Enabled"

3. **Verify Permissions:**
   - Go back to the HiChat app
   - Tap "Check Permissions" to verify

## What SMS Permissions Allow:

✅ **READ_SMS** - Read existing SMS messages from your device
✅ **SEND_SMS** - Send SMS messages through the app  
✅ **RECEIVE_SMS** - Receive and process incoming SMS messages

## Why These Permissions Are Needed:

- **Chat Integration**: Display SMS conversations alongside app messages
- **Contact Sync**: Show real SMS history with your contacts
- **Message Sending**: Send SMS when internet is not available
- **Backup/Sync**: Backup your SMS messages to the cloud

## Permission Safety:

🔒 **Your SMS data is secure:**
- Only used within the HiChat app
- Not shared with third parties
- Stored securely on your device
- You can revoke permissions anytime

## Troubleshooting:

### Permission Dialog Not Showing?
- The app might already have permissions
- Try running: `flutter run sms_permission_guide.dart`
- Check if permissions are already granted

### Permission Denied?
- You can grant them manually in Settings
- Or use the "Open App Settings" button in the test app

### Still Having Issues?
- Make sure you're running on a real Android device (not emulator)
- Some Android versions require different permission flows
- Check that the app is installed properly

## Test Your SMS Integration:

Once permissions are granted, test the functionality:

```bash
# Run the SMS test app
flutter run sms_permission_guide.dart

# Or run the main app
flutter run
```

The test app will:
- ✅ Check permission status
- ✅ Read recent SMS messages  
- ✅ Display SMS conversations
- ✅ Test SMS sending (with valid phone number)

## Next Steps:

After granting permissions, your HiChat app will be able to:
- Display your existing SMS conversations
- Send and receive SMS messages
- Integrate SMS with chat features
- Backup messages to the cloud

**Your SMS functionality is now ready to use! 🎉**