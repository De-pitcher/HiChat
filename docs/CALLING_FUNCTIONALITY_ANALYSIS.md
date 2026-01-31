# Calling Functionality Analysis

## Overview
The HiChat application has **basic calling functionality** that integrates with the device's native phone dialer. It does **NOT** have in-app VoIP calling (voice/video calls). Instead, it provides:
- Call history viewing and management
- Dialpad for direct phone number entry
- Integration with native phone calling
- Call log history tracking

---

## Architecture & Components

### 1. **Calls Screen** (`lib/screens/calls/calls_screen.dart`)

#### Purpose
Main UI for call management with two tabs:
1. **Recent Calls Tab** - Shows call history
2. **Dialpad Tab** - Allows direct phone number dialing

#### Key Features

**Call History Tab:**
- Displays recent phone calls with details:
  - Contact name/phone number
  - Call direction (incoming/outgoing/missed/rejected)
  - Call duration
  - Call timestamp
- **Pagination**: Loads calls in 7-day chunks for performance
- **Max 100 calls per page** as safety limit
- **Infinite scroll**: Loads more logs when scrolling to 80% of list

**Dialpad Tab:**
- Grid of number buttons (0-9, *, #)
- Text field showing dialed number
- Call button to initiate call
- Backspace and clear functions
- Haptic feedback on button press

#### Key Methods

```dart
// Load call logs from device
Future<void> _loadCallLogsPage()
  - Queries system call logs using call_log plugin
  - Loads calls from specified date range
  - Sorts by timestamp (most recent first)

// Make phone call
Future<void> _makeCall(String phoneNumber)
  - Creates tel: URI scheme
  - Launches native phone dialer
  - Handles errors if phone app unavailable

// Format display
String _formatCallTime(int? timestamp)
  - Shows time for today's calls
  - Shows "Yesterday" for yesterday
  - Shows date for older calls

String _formatCallDuration(int? duration)
  - Displays duration as "Xm Ys" format
  - Handles edge cases (0 duration = no display)
```

---

### 2. **Permissions & Device Access**

#### Required Permissions
```dart
Permission.phone    // Access call logs (READ_CALL_LOG)
Permission.sms      // Sometimes needed on some Android devices
```

#### Permission Handling
- Auto-requests on screen load
- Shows permission denied dialog if rejected
- Allows user to open Settings to grant permission
- Gracefully degrades if permission not available

#### Permission Dialog UI
```
"Phone Permission Required"
"To view your call history, please grant phone permissions 
in Settings."
[Try Again] [Open Settings]
```

---

### 3. **Data Models**

#### CallLogEntry (from call_log plugin)
```dart
class CallLogEntry {
  String? number          // Phone number
  int? duration           // Call duration in seconds
  int? timestamp          // Call time in milliseconds
  CallType? callType      // incoming, outgoing, missed, rejected
}
```

#### Call Types
```dart
enum CallType {
  incoming,  // Green icon: ↙️
  outgoing,  // Blue icon: ↗️
  missed,    // Red icon: ↙️
  rejected   // Orange icon: ⊘
}
```

---

### 4. **Device Integration**

#### Call Log Access
- Uses `call_log` plugin to query device call history
- Accesses native call logs via ContentProvider (Android)
- Loads logs by date range for efficiency
- Supports pagination for large call histories

#### Making Calls
- Uses `url_launcher` plugin with `tel:` scheme
- Creates URI: `tel://{phone_number}`
- Launches native phone dialer
- Device handles the actual call

#### Example Call Flow
```
User taps "123-456-7890" 
  ↓
App creates: Uri(scheme: 'tel', path: '123-456-7890')
  ↓
url_launcher checks if phone app available
  ↓
Launches native phone dialer with number
  ↓
Device makes the call
```

---

## Feature Breakdown

### ✅ Implemented Features

| Feature | Status | Details |
|---------|--------|---------|
| **View Call History** | ✅ | Loads device call logs, displays with formatting |
| **Call Details** | ✅ | Shows number, type, duration, timestamp |
| **Dialpad** | ✅ | Full number entry grid with backspace/clear |
| **Make Calls** | ✅ | Initiates native phone calls via tel: scheme |
| **Pagination** | ✅ | Loads calls in 7-day increments |
| **Infinite Scroll** | ✅ | Auto-loads more when scrolling down |
| **Call Duration Format** | ✅ | Shows "Xm Ys" format |
| **Call Time Formatting** | ✅ | Smart display (time/Yesterday/date) |
| **Haptic Feedback** | ✅ | Button press feedback |
| **Permission Handling** | ✅ | Auto-request with fallback to Settings |
| **Call Type Icons** | ✅ | Color-coded icons per call type |

### ❌ NOT Implemented Features

| Feature | Status | Details |
|---------|--------|---------|
| **In-App VoIP Calls** | ❌ | No voice/video calling within app |
| **Call Recording** | ❌ | No recording capability |
| **Call Blocking** | ❌ | No blocking functionality |
| **Contact Integration** | ❌ | Shows phone number only, no contact lookup |
| **Call Transfer** | ❌ | No call forwarding |
| **Conference Calling** | ❌ | No multi-party calls |
| **Call Waiting** | ❌ | No call hold/resume |
| **Voicemail** | ❌ | No voicemail access |
| **Chat-to-Call** | ⚠️ | TODO in chat UI (not implemented) |

---

## Chat Integration (Planned)

### Current State
In chat screens (`enhanced_chat_screen.dart`, `chat_screen_original_backup.dart`):
```dart
IconButton(
  icon: const Icon(Icons.call),
  onPressed: () {
    // TODO: Implement voice call
  },
),
IconButton(
  icon: const Icon(Icons.videocam),
  onPressed: () {
    // TODO: Implement video call
  },
)
```

### Status
- **Voice Call Button**: Defined but not implemented
- **Video Call Button**: Defined but not implemented
- **Expected Behavior**: Would initiate in-app call with chat participant

---

## Call Log Upload to Backend

### Backend Integration
```dart
// In api_service.dart - uploadCallLogsBulk()
Future<BulkUploadResponse> uploadCallLogsBulk({
  required String owner,
  required List<CallLogData> callList,
})
```

### CallLogData Format
```dart
class CallLogData {
  String number;           // "1234567890"
  String callType;         // "1" = Audio, "2" = Video
  String direction;        // "INCOMING", "OUTGOING"
  String date;            // Timestamp in milliseconds
  String duration;        // Duration in seconds
}
```

### Upload Flow
```
Device Call Logs (native)
  ↓
CallLogEntry objects (via call_log plugin)
  ↓
Convert to CallLogData format
  ↓
Upload via API to backend
  ↓
Backend stores for user analytics/history
```

---

## SMS Functionality (Related)

The app also includes SMS capabilities (separate from calls):
- **Read SMS messages** - Access device SMS conversations
- **Send SMS** - Send text messages via native SMS app
- **SMS Conversations** - Group messages by phone number

See: `lib/screens/sms/sms_screen.dart` & `lib/plugins/sms_plugin.dart`

---

## Plugin Dependencies

```yaml
# Call log access
call_log: ^4.7.0          # Device call history

# Permission handling
permission_handler: ^11.1.0  # Request permissions

# URL launching (for tel: scheme)
url_launcher: ^6.2.0      # Launch phone dialer

# SMS functionality (related)
# (Custom Kotlin plugin in android/)
```

---

## Data Flow Diagram

```
┌─────────────────────┐
│ CallsScreen Widget  │
└──────────┬──────────┘
           │
           ├─────────────────────┐
           │                     │
    ┌──────▼──────┐      ┌──────▼──────┐
    │ Recent Tab  │      │ Dialpad Tab │
    └──────┬──────┘      └──────┬──────┘
           │                     │
           │          ┌──────────▼─────────┐
           │          │ User enters number │
           │          └──────────┬─────────┘
           │                     │
    ┌──────▼─────────────────────▼──────┐
    │   _makeCall(phoneNumber)          │
    └──────┬──────────────────────────┘
           │
           ├─────────────────────────┐
           │                         │
    ┌──────▼──────────┐    ┌─────────▼──────────┐
    │ Create URI      │    │ Check if available │
    │ tel://number    │    │ via url_launcher   │
    └──────┬──────────┘    └─────────┬──────────┘
           │                         │
           └─────────────┬───────────┘
                         │
                ┌────────▼──────────┐
                │ Launch native     │
                │ phone dialer      │
                └────────┬──────────┘
                         │
                ┌────────▼──────────┐
                │ Device makes call │
                └───────────────────┘
```

---

## Call History Load Flow

```
_loadCallLogs()
  ↓
_requestPermissionsAndLoadLogs()
  ├─ Request Permission.phone
  ├─ Check if granted
  └─ If granted: _loadCallLogsPage()
      ↓
      CallLog.query(dateFrom, dateTo)
        ↓
      [Native call logs from device]
        ↓
      Sort by timestamp (most recent first)
        ↓
      Limit to 100 entries per page
        ↓
      setState() to update UI
        ↓
      Listen for scroll at 80% position
        ↓
      Auto-load next page
```

---

## Performance Considerations

### Optimization Strategies
1. **Date Range Queries**: Load 7 days at a time, not all calls
2. **Pagination Limit**: Max 100 calls per page as safety
3. **Lazy Loading**: Load more only when user scrolls to 80%
4. **Sorting**: Done in-memory after query for speed
5. **State Management**: Minimal rebuilds with setState

### Potential Bottlenecks
- Large call histories (1000+ entries) may be slow to query
- Repeated scrolling trigger multiple page loads
- Device may not support date range filtering efficiently

---

## Testing Checklist

- [ ] Call history loads on permission grant
- [ ] Pagination works with multiple pages
- [ ] Infinite scroll loads more calls
- [ ] Dialpad accepts all valid phone characters
- [ ] Call button launches phone dialer
- [ ] Call type icons display correctly
- [ ] Time formatting works (time/Yesterday/date)
- [ ] Duration formats correctly (Xm Ys)
- [ ] Permission denial shows proper UI
- [ ] Settings button opens app settings
- [ ] Haptic feedback works on button press
- [ ] Empty state shows when no call history
- [ ] Error handling works gracefully

---

## Future Enhancement Opportunities

### High Priority
1. **VoIP Integration** - Add WebRTC or Agora for in-app calls
2. **Contact Lookup** - Match phone numbers to contacts
3. **Call Details** - Tap to see full call information
4. **Filtering** - Filter by call type/contact
5. **Search** - Search call history by number

### Medium Priority
1. **Call Blocking** - Block specific numbers
2. **Call Recording** - Record calls with permission
3. **Call Logs Sync** - Sync to backend for cross-device access
4. **Call Statistics** - Analytics dashboard
5. **Speed Dial** - Quick access to favorite contacts

### Low Priority
1. **Call Scheduling** - Remind user to call someone
2. **Call Transcription** - Convert calls to text
3. **Multi-language** - Support for different languages
4. **Dark Mode** - Better dark theme support
5. **Accessibility** - Screen reader support

---

## Summary

The **Calling functionality in HiChat is currently LIMITED to device call management**:
- ✅ Can view device call history
- ✅ Can initiate phone calls via native dialer
- ✅ Has dialpad for direct number entry
- ❌ Does NOT support in-app VoIP calling
- ❌ Does NOT support video calling
- ❌ Chat-to-call buttons are placeholders

The app leverages **native platform capabilities** rather than implementing custom calling logic, which is efficient but means features depend on device phone app availability.

To add in-app calling, you would need to integrate a **VoIP service** like:
- **Agora SDK** - Mature, widely used
- **Vonage (Nexmo)** - Enterprise-grade
- **Twilio** - Flexible, good documentation
- **WebRTC** - Open-source but requires signaling server
