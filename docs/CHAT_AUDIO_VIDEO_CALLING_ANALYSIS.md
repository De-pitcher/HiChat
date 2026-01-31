# Chat Screen Call (Audio/Video) Functionality Analysis

## Current Status: ❌ NOT IMPLEMENTED

The voice and video calling buttons in the chat header are **defined but completely non-functional**. They are placeholder UI elements with TODO comments.

---

## UI Implementation

### Location
- **File**: `lib/screens/chat/enhanced_chat_screen.dart`
- **Also in**: `lib/widgets/chat/chat_app_bar.dart`
- **Position**: Chat screen app bar (header)

### Visual Components

#### 1. Voice Call Button
```dart
IconButton(
  icon: const Icon(Icons.call),
  onPressed: () {
    // TODO: Implement voice call
  },
),
```

#### 2. Video Call Button
```dart
IconButton(
  icon: const Icon(Icons.videocam),
  onPressed: () {
    // TODO: Implement video call
  },
),
```

### Button Properties
- **Icon Color**: Default (usually primary color)
- **Location**: Right side of app bar
- **Order**: Voice call → Video call → Menu
- **Behavior**: Currently does nothing when tapped
- **Visibility**: Always visible (no conditional checks)

---

## Architecture Currently Missing

To implement chat calling, the app would need:

### 1. **Call Signaling Service**
```dart
// Needed but NOT implemented
class CallSignalingService {
  // Send call invitation
  Future<void> initiateCall(String recipientId, CallType type)
  
  // Handle incoming call
  Stream<CallInvitation> onIncomingCall()
  
  // Accept/Reject call
  Future<void> acceptCall(String callId)
  Future<void> rejectCall(String callId)
  
  // End call
  Future<void> endCall(String callId)
}
```

### 2. **VoIP/Media Service** 
**NOT integrated** - App would need one of:
- **Agora SDK** - Real-time voice/video
- **Twilio** - WebRTC-based calling
- **Vonage/Nexmo** - Enterprise calling
- **Janus/OpenVidu** - Self-hosted WebRTC
- **WebRTC** - Direct peer-to-peer

### 3. **Permission Handling**
```dart
// Permissions needed but NOT requested for calls
Permission.microphone    // For audio
Permission.camera        // For video
Permission.bluetoothAudio // For headsets
```

### 4. **Call State Management**
**NOT implemented** - Would need:
```dart
class CallState {
  String callId
  String initiatorId
  String recipientId
  CallType type              // audio, video, or screen_share
  CallStatus status          // idle, ringing, connected, ended
  DateTime startTime
  Duration duration
}
```

### 5. **Notification System for Incoming Calls**
**NOT implemented** - Would need:
- Incoming call notification overlay
- Caller info display
- Accept/Reject buttons
- Ringtone playback
- Do Not Disturb handling

---

## Data Flow (If Implemented)

### Outgoing Call Flow
```
User taps "Call" button in chat
  ↓
Check call permissions (microphone/camera)
  ↓
Show call type dialog: Audio/Video?
  ↓
Initiate call via signaling service
  ↓
Send call invitation via WebSocket
  ↓
Wait for recipient to accept/reject
  ↓
On acceptance: Start media stream
  ↓
On rejection/timeout: Show missed call
```

### Incoming Call Flow
```
Backend sends call invitation via WebSocket
  ↓
Media WebSocket receives notification
  ↓
Show incoming call notification overlay
  ↓
Play ringtone
  ↓
User accepts/rejects
  ↓
On acceptance: Connect media streams
  ↓
On rejection: Notify caller of rejection
```

---

## Integration Points

### 1. Chat WebSocket Service
**File**: `lib/services/chat_websocket_service.dart`

Currently handles:
- ✅ Text messages
- ✅ Message receipt acknowledgments
- ✅ Presence updates (online/offline)
- ❌ Call invitations
- ❌ Call status updates
- ❌ Call termination

Would need to add call-related message types:
```dart
// Example message types needed
'call_invitation'      // Invite someone to call
'call_accepted'        // Call recipient accepted
'call_rejected'        // Call recipient declined
'call_ended'           // Call terminated
'call_missed'          // Call went unanswered
```

### 2. Media WebSocket Service
**File**: `lib/services/unified_background_websocket_service.dart`

Currently handles:
- ✅ Media stream over WebSocket
- ✅ Media upload requests
- ❌ Real-time audio/video streaming
- ❌ Call codec negotiation

The media WebSocket is used for **media upload** (images/audio/video files), NOT for real-time calling. Real-time calling would need:
- Separate WebRTC peer connection
- Media codec negotiation (OPUS for audio, VP8/VP9 for video)
- Jitter buffers and packet loss recovery

### 3. Background Service
**File**: `lib/services/unified_background_websocket_service.dart`

Could be extended to:
- Listen for incoming call invitations in background
- Display incoming call notification
- Handle call in background when app is closed/minimized

---

## What Needs to Be Implemented

### Phase 1: Core Infrastructure
1. **Call Signaling Service**
   - Communicate call state changes via WebSocket
   - Message format: `{type: 'call_invitation', callId, initiatorId, recipientId, callType, timestamp}`
   - Handle call lifecycle events

2. **Permissions Framework**
   - Request microphone permission before audio call
   - Request camera permission before video call
   - Handle permission denial gracefully

3. **Call State Manager**
   - Track active call
   - Manage call duration/timer
   - Handle call status changes (ringing → connected → ended)

### Phase 2: UI/UX
1. **Call Invitation Dialog**
   - Show when user taps call button
   - Select call type (audio/video)
   - Confirm before initiating

2. **Incoming Call Overlay**
   - Full-screen notification
   - Caller name/photo
   - Accept/Reject buttons
   - Ringtone/vibration

3. **Active Call Screen**
   - Remote user video/info
   - Local user camera preview
   - Controls: mute, speaker, end call
   - Call duration timer

4. **Call End Screen**
   - Call summary (duration, type)
   - Option to send message
   - Option to call again

### Phase 3: Media Integration
1. **WebRTC Setup**
   - Initialize media capture (microphone/camera)
   - Create peer connection
   - Handle ICE candidates
   - Manage media streams

2. **Codec Selection**
   - Audio: OPUS (preferred) or G.711
   - Video: VP8/VP9 (hardware accelerated if available)
   - Adaptive bitrate based on network

3. **Network Optimization**
   - Bandwidth estimation
   - Packet loss handling
   - Echo cancellation
   - Noise suppression

---

## Backend Requirements

### 1. Call Signaling Endpoint
```
POST /api/calls/initiate
  {
    initiatorId: string
    recipientId: string
    callType: 'audio' | 'video'
    timestamp: ISO8601
  }
  
  Returns:
  {
    callId: string
    signaling_server: string
    ice_servers: [...]
  }
```

### 2. WebSocket Message Types
```dart
// Invitation
{
  "type": "call_invitation",
  "callId": "call_123",
  "initiatorId": 129,
  "initiatorName": "Sparks",
  "callType": "audio|video",
  "timestamp": "2026-01-29T..."
}

// Response
{
  "type": "call_response",
  "callId": "call_123",
  "status": "accepted|rejected",
  "timestamp": "2026-01-29T..."
}

// End
{
  "type": "call_ended",
  "callId": "call_123",
  "duration": 120,
  "reason": "user_ended|missed|rejected"
}
```

### 3. Call History Storage
- Store call duration
- Store call type (audio/video)
- Store call status (connected/rejected/missed)
- Link to chat for history

---

## Recommended Implementation Path

### Option A: Third-Party Service (Recommended)
**Agora** or **Vonage** - Most reliable
- Pros: Battle-tested, good docs, enterprise support
- Cons: Monthly cost, dependency on external service
- Time: 2-3 weeks integration

**Implementation**:
```dart
// Would look something like:
class AgoraCallService {
  Future<void> initiateCall(String userId, CallType type) async {
    // Get token from backend
    final token = await apiService.getAgoraToken();
    
    // Initialize Agora engine
    await AgoraRtcEngine.create(appId);
    
    // Join channel
    await agoraEngine.joinChannel(
      token: token,
      channelName: 'call_$callId',
      uid: currentUserId,
    );
  }
}
```

### Option B: WebRTC (Self-hosted)
**flutter_webrtc** + own signaling server
- Pros: Full control, no monthly costs
- Cons: Requires backend development, more complex
- Time: 4-6 weeks implementation

**Implementation**:
```dart
class WebRTCCallService {
  late RTCPeerConnection _peerConnection;
  late MediaStream _localStream;
  
  Future<void> initiateCall(String recipientId) async {
    // Get ICE servers from backend
    final iceServers = await apiService.getIceServers();
    
    // Create peer connection
    _peerConnection = await createPeerConnection(
      RTCConfiguration(iceServers: iceServers),
    );
    
    // Add local stream
    _localStream = await getDisplayMedia();
    _peerConnection.addStream(_localStream);
    
    // Create and send offer
    final offer = await _peerConnection.createOffer();
    await _peerConnection.setLocalDescription(offer);
    
    // Send via signaling service
    await chatWebSocketService.sendCallInvitation(
      recipientId: recipientId,
      offer: offer,
    );
  }
}
```

### Option C: Simple Phone Calling (Quick)
**Skip VoIP, use native dialer**
- Pros: Quick to implement, leverages device
- Cons: Not true VoIP, user sees their number
- Time: 1-2 days

**Would be similar to call history screen** - launches device phone app

---

## Permission Requirements

```dart
// In pubspec.yaml, would need:
agora_rtc_engine: ^6.0.0      // If using Agora
flutter_webrtc: ^0.10.0       // If using WebRTC

// In AndroidManifest.xml:
<uses-permission android:name="android.permission.RECORD_AUDIO" />
<uses-permission android:name="android.permission.CAMERA" />
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />

// In iOS Info.plist:
<key>NSCameraUsageDescription</key>
<string>We need camera access for video calls</string>
<key>NSMicrophoneUsageDescription</key>
<string>We need microphone access for audio calls</string>
```

---

## Current Code Locations

### UI Elements (No Implementation)
- `lib/screens/chat/enhanced_chat_screen.dart:495-503` - Video call buttons
- `lib/widgets/chat/chat_app_bar.dart:210-225` - App bar buttons

### Related Services (Could be Extended)
- `lib/services/chat_websocket_service.dart` - Add call messages
- `lib/services/unified_background_websocket_service.dart` - Handle call notifications
- `lib/services/auth_state_manager.dart` - Initialize call service on login

### Call History (Exists but Separate)
- `lib/screens/calls/calls_screen.dart` - Device call logs (not app calls)

---

## Estimated Development Time

| Implementation | Time | Complexity |
|---|---|---|
| **Agora SDK** | 2-3 weeks | Medium |
| **Vonage** | 2-3 weeks | Medium |
| **flutter_webrtc** | 4-6 weeks | High |
| **Native Phone Dialer** | 1-2 days | Low |

---

## Current Blockers

1. **No VoIP service integrated** - Must choose and integrate
2. **No call signaling** - Backend needs call API endpoints
3. **No permission framework for calls** - Microphone/camera not requested
4. **No call state management** - Need to track active calls
5. **No UI for call screens** - Need incoming/active call screens
6. **No background call handling** - Need to handle calls when minimized

---

## Next Steps to Implement

1. **Decision**: Choose calling service (Agora recommended)
2. **Backend**: Set up call signaling endpoints + WebSocket messages
3. **Setup**: Add SDK to pubspec.yaml + native configs
4. **Permissions**: Request microphone/camera on call initiation
5. **UI**: Build incoming call + active call screens
6. **Integration**: Connect call buttons to call service
7. **Testing**: Test on actual devices (emulators have issues with media)

---

## Summary

The chat calling buttons are **currently just placeholder UI** with no functionality. To implement them, you need to:

✅ Choose a VoIP service (Agora/Vonage/WebRTC)
✅ Integrate SDK into app
✅ Implement call signaling via WebSocket
✅ Build UI for incoming/active calls  
✅ Add permission handling
✅ Test on real devices

**Estimated effort**: 2-6 weeks depending on approach chosen.

**Recommendation**: Use **Agora SDK** for fastest, most reliable implementation.
