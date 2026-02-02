# Comprehensive Audio/Video Call Functionality Analysis

**Last Updated**: February 1, 2026  
**Status**: ✅ PARTIALLY IMPLEMENTED (Infrastructure ready, integration in progress)

---

## Executive Summary

The HiChat application has a **two-tier calling system**:

1. **Implemented**: Core infrastructure for call signaling and media handling
2. **In Progress**: Integration with chat UI and call state management
3. **Missing**: Complete end-to-end call flow and incoming call UI

---

## 1. Architecture Overview

### System Components

```
┌─────────────────────────────────────────────────────────────┐
│                     Chat Screen (UI)                         │
│  - Call/Video buttons in AppBar                              │
│  - Call message cards display                                │
└────────────────┬────────────────────────────────────────────┘
                 │
         ┌───────┴────────┐
         │                │
┌────────▼────────────┐  ┌─────────────────────┐
│ Signaling Service   │  │ Chat WebSocket      │
│ CallSignalingService│  │ Service             │
│                     │  │                     │
│ - Send invitations  │──┤ - Call message      │
│ - Accept/Reject     │  │   handling          │
│ - End calls         │  │ - Message parsing   │
│ - State tracking    │  │                     │
└─────────┬──────────┘  └────────┬────────────┘
          │                      │
          └──────────┬───────────┘
                     │
          ┌──────────▼──────────┐
          │ Agora SDK           │
          │ AgoraCallService    │
          │                     │
          │ - RTC Engine init   │
          │ - Media streaming   │
          │ - Audio/Video setup │
          │ - Event listeners   │
          └──────────┬──────────┘
                     │
          ┌──────────▼──────────┐
          │ Active Call Screen  │
          │                     │
          │ - Video feeds       │
          │ - Call controls     │
          │ - Duration timer    │
          └─────────────────────┘
```

---

## 2. Core Services

### 2.1 CallSignalingService
**File**: [lib/services/call_signaling_service.dart](lib/services/call_signaling_service.dart)  
**Lines**: 404 total  
**Pattern**: Singleton  
**Dependencies**: ChatWebSocketService

#### Purpose
Manages call state transitions and signaling messages over WebSocket. Routes all call-related messages through the existing chat WebSocket.

#### Key Methods

```dart
// Initialize the service
Future<void> initialize(String userId)

// Outgoing calls
Future<void> sendCallInvitation({
  required String toUserId,
  required String toUserName,
  required String channelName,
  required bool isVideoCall,
})

// Incoming call handling
Future<void> acceptCall(String callId, {String? channelName})
Future<void> rejectCall(String callId, {String reason})

// Call termination
Future<void> endCall(String callId, {int? durationSeconds})

// Streams for state changes
Stream<CallInvitation> get incomingCalls
Stream<CallStateChange> get callStateChanges
```

#### WebSocket Message Format

**Outgoing Call Invitation**:
```json
{
  "type": "call_invitation",
  "call_id": "call_1706705824123_129",
  "from_user_id": "129",
  "to_user_id": "136",
  "to_user_name": "ahmedkhan123",
  "channel_name": "call_12_1706705824123",
  "is_video_call": true,
  "timestamp": "2026-02-01T12:30:24.123Z"
}
```

**Call Acceptance**:
```json
{
  "type": "call_accepted",
  "call_id": "call_1706705824123_129",
  "channel_name": "call_12_1706705824123",
  "timestamp": "2026-02-01T12:30:30.456Z"
}
```

**Call Rejection**:
```json
{
  "type": "call_rejected",
  "call_id": "call_1706705824123_129",
  "reason": "User declined",
  "timestamp": "2026-02-01T12:30:25.789Z"
}
```

**Call Ended**:
```json
{
  "type": "call_ended",
  "call_id": "call_1706705824123_129",
  "duration": 180,
  "timestamp": "2026-02-01T12:33:24.000Z"
}
```

#### Models

**CallInvitation**:
```dart
class CallInvitation {
  final String callId;
  final String fromUserId;
  final String fromUserName;
  final String channelName;
  final bool isVideoCall;
  final DateTime timestamp;
}
```

**CallStateChange**:
```dart
class CallStateChange {
  final CallStateType type;
  final String? callId;
  final String? fromUserId;
  final String? toUserId;
  final String? channelName;
  final String? message;
  final int? duration;
  final DateTime timestamp;
}

enum CallStateType {
  callInitiated,    // Outgoing call started
  incomingCall,     // Incoming call received
  callAccepted,     // Call accepted
  callRejected,     // Call rejected
  callEnded,        // Call ended
  callMissed,       // Call went unanswered
}
```

---

### 2.2 AgoraCallService
**File**: [lib/services/agora_call_service.dart](lib/services/agora_call_service.dart)  
**Lines**: 380 total  
**Pattern**: Singleton  
**Agora SDK Version**: 6.3.0

#### Purpose
Handles real-time audio/video communication using Agora's RTC engine. Manages channel joining, media setup, and event handling.

#### Configuration

```dart
// App ID from Agora console
static const String AGORA_APP_ID = '9d6f9392e0ff44a7838c091757a70615';
```

#### Key Methods

```dart
// Initialization
Future<void> initialize()
bool get isInitialized

// Call management
Future<bool> initiateCall({
  required String channelName,
  required int uid,
  required bool videoCall,
})

Future<void> endCall()

// Media control
Future<void> muteMicrophone(bool mute)
Future<void> disableCamera(bool disable)
Future<void> enableSpeaker(bool enable)
Future<void> switchCamera()

// Permissions
Future<bool> requestCallPermissions({bool videoCall = false})

// Events
Stream<CallEvent> get callEvents
```

#### Call Event Types

```dart
enum CallEventType {
  initialized,        // SDK initialized
  channelJoined,      // Successfully joined channel
  channelLeft,        // Left channel
  remoteUserJoined,   // Remote user joined
  remoteUserLeft,     // Remote user left
  error,              // Error occurred
  tokenExpiring,      // Auth token expiring
  permissionDenied,   // Permissions not granted
}

class CallEvent {
  final CallEventType type;
  final String message;
  final int? userId;        // For user-related events
  final dynamic data;
  final DateTime timestamp;
}
```

#### Event Listeners

```dart
_agoraEngine.registerEventHandler(
  RtcEngineEventHandler(
    onJoinChannelSuccess: (connection, elapsed) { /* Connected */ },
    onLeaveChannel: (connection, stats) { /* Disconnected */ },
    onUserJoined: (connection, remoteUid, elapsed) { /* Remote user joined */ },
    onUserOffline: (connection, remoteUid, reason) { /* Remote user left */ },
    onError: (err, msg) { /* Error occurred */ },
    onTokenPrivilegeWillExpire: (connection, token) { /* Token expiring */ },
  ),
);
```

#### Permission Handling

```dart
// For audio call: requests Microphone
// For video call: requests Microphone + Camera
Future<bool> requestCallPermissions({bool videoCall = false})

// Permissions checked:
- Permission.microphone
- Permission.camera (if videoCall == true)
- Permission.bluetoothAudio (implicit)
```

---

### 2.3 Integration with ChatWebSocketService
**File**: [lib/services/chat_websocket_service.dart](lib/services/chat_websocket_service.dart)  
**Message Type Parsing** (Line ~1599):

#### Message Type Recognition

```dart
static MessageType _parseMessageType(dynamic type) {
  final typeStr = type.toString().toLowerCase();
  switch (typeStr) {
    case 'call_invitation':
    case 'call_accepted':
    case 'call_rejected':
    case 'call_declined':
    case 'call_ended':
    case 'call':
      return MessageType.call;  // ✅ All call types mapped
    default:
      return MessageType.text;
  }
}
```

#### New Message Handling (Line ~950)

```dart
// When backend sends new_message with message_type: "call_invitation"
final messageType = _parseMessageType(data['message_type']);

// Message object created with:
Message(
  id: 377,
  chatId: 12,
  content: '{"type":"call_invitation","call_id":"call_123",...}',
  type: MessageType.call,  // ✅ Correctly identified
  isCall: true,
)

// Stored in ChatStateManager._chatMessages[chatId]
// Broadcasts to UI via notifyListeners()
```

---

## 3. UI Integration

### 3.1 Enhanced Chat Screen
**File**: [lib/screens/chat/enhanced_chat_screen.dart](lib/screens/chat/enhanced_chat_screen.dart)  
**Call Buttons** (Line ~497):

```dart
AppBar(
  actions: [
    // Voice call button
    IconButton(
      icon: Icon(
        Icons.call,
        color: Theme.of(context).brightness == Brightness.light
            ? AppColors.primary
            : Colors.white,  // ✅ Theme-aware colors
      ),
      onPressed: () => _initiateCall(isVideoCall: false),
    ),
    
    // Video call button
    IconButton(
      icon: Icon(
        Icons.videocam,
        color: Theme.of(context).brightness == Brightness.light
            ? AppColors.primary
            : Colors.white,  // ✅ Theme-aware colors
      ),
      onPressed: () => _initiateCall(isVideoCall: true),
    ),
  ],
)
```

#### Call Initiation Flow (Line ~700)

```dart
void _initiateCall({required bool isVideoCall}) async {
  try {
    final signalingService = CallSignalingService();
    final channelName = 'call_${widget.chat.id}_${DateTime.now().millisecondsSinceEpoch}';

    // Step 1: Send call invitation via signaling service
    await signalingService.sendCallInvitation(
      toUserId: widget.chat.id,
      toUserName: widget.chat.name,
      channelName: channelName,
      isVideoCall: isVideoCall,
    );

    // Step 2: Navigate to active call screen
    if (context.mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => ActiveCallScreen(
            channelName: channelName,
            remoteUserName: widget.chat.name,
            isVideoCall: isVideoCall,
            callId: channelName,
          ),
        ),
      );
    }

    // Step 3: Show confirmation toast
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Calling ${widget.chat.name}... (${isVideoCall ? 'video' : 'voice'} call)'),
        duration: const Duration(seconds: 2),
      ),
    );
  } catch (e) {
    debugPrint('❌ EnhancedChatScreen: Error initiating call: $e');
  }
}
```

### 3.2 Call Message Card
**File**: [lib/widgets/chat/call_message_card.dart](lib/widgets/chat/call_message_card.dart)  
**Purpose**: Display call-related messages in chat history

#### Features

- **WhatsApp-style design**: Minimal horizontal layout
- **Call type icons**: Different icons for call/video call
- **Direction indicators**: Shows if call was made or received
- **Timestamp**: Formatted time display
- **Status colors**: Blue (invitation), Green (accepted), Red (declined)

#### Rendering (Line ~800 in EnhancedChatScreen)

```dart
if (message.isCall) {
  return CallMessageCard(
    message: message,
    isCurrentUser: isCurrentUser,
  );
}
```

#### Message JSON Structure

```json
{
  "type": "call_invitation",
  "call_id": "call_1706705824123_129",
  "from_user_id": "129",
  "is_video_call": false,
  "timestamp": "2026-02-01T12:30:24.123Z"
}
```

---

### 3.3 Active Call Screen
**File**: [lib/screens/calls/active_call_screen.dart](lib/screens/calls/active_call_screen.dart)  
**Lines**: 472 total

#### Features

- **Call Duration Timer**: Updates every second
- **Media Controls**:
  - Microphone mute/unmute
  - Camera enable/disable
  - Speaker on/off
  - Camera switch (front/back)
- **Remote User Tracking**: Listens to Agora events
- **Call Termination**: Ends Agora call and signals via CallSignalingService

#### State Management

```dart
class _ActiveCallScreenState extends State<ActiveCallScreen> {
  bool _isMuted = false;
  bool _isCameraDisabled = false;
  bool _isSpeakerEnabled = true;
  
  int? _remoteUserId;  // Updated when remote user joins
  Duration _callDuration = Duration.zero;  // Updated every second
  DateTime _callStartTime;
}
```

#### Agora Event Handling

```dart
void _listenToAgoraEvents() {
  _agoraService.callEvents.listen((event) {
    switch (event.type) {
      case CallEventType.remoteUserJoined:
        setState(() {
          _remoteUserId = event.userId;  // Show remote video
        });
        break;
        
      case CallEventType.remoteUserLeft:
        setState(() {
          _remoteUserId = null;  // Hide remote video
        });
        break;
        
      case CallEventType.error:
      case CallEventType.channelLeft:
        Navigator.of(context).pop();  // Exit call screen
        break;
        
      default:
        break;
    }
  });
}
```

---

### 3.4 Incoming Call Screen
**File**: [lib/screens/calls/incoming_call_screen.dart](lib/screens/calls/incoming_call_screen.dart)  
**Lines**: 361 total

#### Features

- **Pulse Animation**: Animated avatar with expanding rings
- **Caller Information**: Name and call type (audio/video)
- **Accept/Reject Buttons**: Large touch targets
- **Ringtone Support**: Placeholder for ringtone playback

#### Accept Call Flow

```dart
Future<void> _handleAccept() async {
  try {
    // Step 1: Accept via signaling service
    await _signalingService.acceptCall(
      widget.invitation.callId,
      channelName: widget.invitation.channelName,
    );

    // Step 2: Initialize Agora call
    final success = await _agoraService.initiateCall(
      channelName: widget.invitation.channelName,
      uid: widget.invitation.fromUserId.hashCode.abs() % 100000,
      videoCall: widget.invitation.isVideoCall,
    );

    if (success) {
      widget.onAccepted();  // Callback to parent
      if (mounted) {
        Navigator.of(context).pop();  // Close incoming call screen
      }
    }
  } catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Error: ${e.toString()}')),
    );
  }
}
```

#### Reject Call Flow

```dart
Future<void> _handleReject() async {
  try {
    await _signalingService.rejectCall(
      widget.invitation.callId,
      reason: 'User declined',
    );
    
    widget.onRejected();  // Callback to parent
    if (mounted) {
      Navigator.of(context).pop();
    }
  } catch (e) {
    // Error handling
  }
}
```

---

### 3.5 Calls Screen (History)
**File**: [lib/screens/calls/calls_screen.dart](lib/screens/calls/calls_screen.dart)  
**Lines**: 905 total

#### Purpose
Displays system call logs from device (not chat-specific calls yet)

#### Features

- **Two Tabs**: 
  - All calls (mixed incoming/outgoing)
  - Missed calls
  
- **Call Log Display**:
  - Caller/callee name
  - Call type (incoming/outgoing/missed)
  - Call duration
  - Timestamp

- **Dialpad**:
  - Manual number input
  - Direct calling via system dialer

- **Permissions**:
  - Requests `Permission.phone`
  - Handles denial gracefully

#### Data Source

```dart
// Loads from device call log via call_log plugin
final Iterable<CallLogEntry> entries = await CallLog.query(
  dateFrom: dateFrom.millisecondsSinceEpoch,
  dateTo: dateTo.millisecondsSinceEpoch,
);
```

---

## 4. Message Type System

### 4.1 MessageType Enum
**File**: [lib/models/message.dart](lib/models/message.dart)

```dart
enum MessageType {
  text,      // Regular text message
  image,     // Image message
  video,     // Video file
  audio,     // Audio file
  file,      // Generic file
  call,      // ✅ NEW - Call invitations and related messages
}
```

### 4.2 Call Message Getter

```dart
// In Message class
bool get isCall => type == MessageType.call;
```

### 4.3 Type Parsing (Three Locations)

#### Location 1: Message._parseMessageType() - Line 164

```dart
static MessageType _parseMessageType(dynamic type) {
  if (type == null) return MessageType.text;
  final typeStr = type.toString().toLowerCase();
  switch (typeStr) {
    case 'text': return MessageType.text;
    case 'image': return MessageType.image;
    case 'video': return MessageType.video;
    case 'audio': return MessageType.audio;
    case 'file': return MessageType.file;
    case 'call_invitation':
    case 'call_accepted':
    case 'call_rejected':
    case 'call_declined':
    case 'call_ended':
    case 'call':
      return MessageType.call;  // ✅ Handles all call variants
    default:
      return MessageType.text;
  }
}
```

#### Location 2: ChatStateManager._parseMessageType() - Line 966

```dart
MessageType _parseMessageType(String type) {
  switch (type.toLowerCase()) {
    case 'call_invitation':
    case 'call_accepted':
    case 'call_rejected':
    case 'call_declined':
    case 'call_ended':
    case 'call':
      return MessageType.call;  // ✅ Consistent mapping
    // ... other types
  }
}
```

#### Location 3: ChatWebSocketService._parseMessageType() - Line 1599

```dart
static MessageType _parseMessageType(dynamic type) {
  final typeStr = type.toString().toLowerCase();
  switch (typeStr) {
    case 'call_invitation':
    case 'call_accepted':
    case 'call_rejected':
    case 'call_declined':
    case 'call_ended':
    case 'call':
      return MessageType.call;  // ✅ Three-layer consistency
    default:
      return MessageType.text;
  }
}
```

---

## 5. End-to-End Call Flow

### 5.1 Outgoing Call Flow

```
User presses "Call" button in EnhancedChatScreen
    ↓
_initiateCall(isVideoCall: false)
    ↓
Generate channelName: 'call_12_1706705824123'
    ↓
CallSignalingService.sendCallInvitation()
    ↓
Create message JSON with:
  - type: "call_invitation"
  - call_id: "call_1706705824123_129"
  - channel_name: "call_12_1706705824123"
  - is_video_call: false
  - timestamp: "2026-02-01T..."
    ↓
Send via ChatWebSocketService.sendMessage()
    ↓
WebSocket transmits to backend
    ↓
Backend routes to recipient user
    ↓
Recipient's WebSocket receives message
    ↓
ChatWebSocketService._handleNewMessage()
    ↓
Message.fromJson() parses message_type: "call_invitation"
    ↓
Message.type = MessageType.call ✅
    ↓
ChatStateManager.onNewMessage(message)
    ↓
Message stored in _chatMessages[chatId]
    ↓
notifyListeners() triggered
    ↓
EnhancedChatScreen receives update
    ↓
CallMessageCard renders: "Incoming call from John"
    ↓
[MISSING] Incoming call notification/overlay shown
```

### 5.2 Accepting Call Flow

```
User accepts incoming call
    ↓
IncomingCallScreen._handleAccept()
    ↓
CallSignalingService.acceptCall(callId)
    ↓
Create call_accepted message
    ↓
Send via WebSocket to caller
    ↓
Caller receives acceptance notification
    ↓
AgoraCallService.initiateCall(channelName)
    ↓
Request permissions (microphone/camera)
    ↓
Agora.initialize(AGORA_APP_ID)
    ↓
Join channel: "call_12_1706705824123"
    ↓
Setup audio/video streams
    ↓
Register event listeners
    ↓
Listen for remote user join
    ↓
Remote user joins channel
    ↓
CallEvent: remoteUserJoined
    ↓
ActiveCallScreen displays remote video
    ↓
Streams sync via Agora network
```

### 5.3 Ending Call Flow

```
User presses "End Call" button
    ↓
ActiveCallScreen._endCall()
    ↓
AgoraCallService.endCall()
    ↓
Agora.leaveChannel()
    ↓
CallEvent: channelLeft
    ↓
CallSignalingService.endCall(callId, durationSeconds)
    ↓
Create call_ended message:
  - call_id: "call_1706705824123_129"
  - duration: 180 (seconds)
  - timestamp: "2026-02-01T12:33:24.000Z"
    ↓
Send via WebSocket
    ↓
Recipient receives call_ended notification
    ↓
ChatStateManager updates message history
    ↓
CallMessageCard renders: "Call ended - 3 min 0 sec"
    ↓
Navigation.pop() - Exit call screen
```

---

## 6. Current Implementation Status

### ✅ Implemented

- [x] **CallSignalingService**: Full message signaling via WebSocket
- [x] **AgoraCallService**: RTC engine integration and media management
- [x] **Call message display**: CallMessageCard widget
- [x] **Active call screen**: Full UI with controls and timer
- [x] **Incoming call screen**: Pulse animation and accept/reject
- [x] **Message type parsing**: Three-layer consistency for call messages
- [x] **Theme-aware buttons**: Call/video buttons visible in light mode
- [x] **Call history tracking**: System call logs (via call_log plugin)
- [x] **Outgoing call initiation**: From chat screen app bar

### ⚠️ Partially Implemented

- [ ] **Incoming call notifications**: Screen created but not triggered from WebSocket
- [ ] **Call history in chat**: Messages stored but notification overlay missing
- [ ] **Ringtone playback**: Placeholder method, needs audio plugin
- [ ] **Call decline option**: UI ready but missing from call message
- [ ] **Call info screen**: Could show call details before connecting

### ❌ Not Implemented

- [ ] **Background call handling**: When app is backgrounded
- [ ] **Missed call badges**: Chat list indicators
- [ ] **Call transfer**: Forwarding calls to other users
- [ ] **Conference calls**: Group calling (>2 participants)
- [ ] **Screen sharing**: Video screen capture feature
- [ ] **Call recording**: Save call data
- [ ] **Call encryption**: End-to-end encryption for calls
- [ ] **Network quality indicator**: Show signal strength
- [ ] **Call stats dashboard**: Call analytics

---

## 7. WebSocket Message Flow

### Backend Integration Points

#### 1. Sending Call Invitations
```
App → ChatWebSocketService.sendMessage()
    → JSON: {"type": "call_invitation", "call_id": "...", ...}
    → WebSocket → Backend
    → Backend → Recipient's WebSocket
```

#### 2. Receiving Call Invitations
```
Backend → Recipient's WebSocket
        → ChatWebSocketService receives {"type": "new_message", "message": {...}}
        → ChatWebSocketService._handleNewMessage()
        → Message._parseMessageType("call_invitation") → MessageType.call
        → ChatStateManager stores message
        → notifyListeners() triggers UI update
```

#### 3. Call Status Updates
```
Backend → WebSocket: {"type": "call_accepted"}
                or {"type": "call_rejected"}
                or {"type": "call_ended"}
        → ChatWebSocketService._handleNewMessage()
        → Message stored with correct type
        → UI updated with status
```

### Message Validation

```dart
// In ChatWebSocketService._handleNewMessage() ~ Line 950

final messageType = data['message_type']; // e.g., "call_invitation"

// Parse to enum
MessageType parsedType = _parseMessageType(messageType);
// Result: MessageType.call ✅

// Create message
Message message = Message.fromJson({
  'id': 377,
  'message_type': 'call_invitation',
  'content': '{"call_id":"...", "is_video_call":false}',
  'timestamp': '2026-02-01T12:30:24.123Z',
  // ... other fields
});

// Message object has:
// - message.type == MessageType.call ✅
// - message.isCall == true ✅
// - message.content == parsed JSON string
```

---

## 8. Dependencies & Versions

### External Packages

```yaml
# RTC/Media
agora_rtc_engine: ^6.3.0          # Agora SDK for real-time communication
permission_handler: ^11.4.4        # Request microphone/camera permissions

# Call logs (system calls, not chat)
call_log: ^4.4.2                  # Access device call history
url_launcher: ^6.1.8              # Make phone calls via system dialer

# State Management & UI
provider: ^6.0.0                  # Reactive state management
flutter: ^3.0.0                   # Flutter framework
```

### Internal Services

```
CallSignalingService (singleton)
    ↓ uses
ChatWebSocketService (singleton)
    
AgoraCallService (singleton)
    ↓ uses
agora_rtc_engine (6.3.0)

ActiveCallScreen
    ↓ uses
AgoraCallService
CallSignalingService

IncomingCallScreen
    ↓ uses
CallSignalingService
AgoraCallService
```

---

## 9. Error Handling

### Common Scenarios

#### Scenario 1: Permission Denied
```dart
Future<bool> requestCallPermissions({bool videoCall = false}) {
  // Returns false if permissions not granted
  // ActiveCallScreen checks this before joining channel
  // Shows SnackBar error message to user
}
```

#### Scenario 2: Network Failure
```dart
// CallSignalingService wraps sendMessage in try-catch
try {
  await _chatWebSocketService.sendMessage(...);
} catch (e) {
  debugPrint('❌ Error sending invitation: $e');
  rethrow;
}

// UI catches and shows error
ScaffoldMessenger.of(context).showSnackBar(
  SnackBar(content: Text('Error: $e'))
);
```

#### Scenario 3: Agora Channel Join Failure
```dart
// AgoraCallService.onError event listener triggers
// ActiveCallScreen exits: Navigator.of(context).pop()
// User returned to chat screen
```

#### Scenario 4: Substring Error (FIXED)
```dart
// Previous: message.content.substring(0, 50)
// Problem: Content "1769824740211" (13 chars) < 50 chars requested

// Fixed:
final contentPreview = message.content.length > 50 
    ? message.content.substring(0, 50) 
    : message.content;
```

---

## 10. Testing Checklist

### Unit Tests Needed

- [ ] CallSignalingService message creation
- [ ] MessageType parsing for all call variants
- [ ] AgoraCallService initialization
- [ ] CallMessageCard JSON parsing

### Integration Tests Needed

- [ ] End-to-end call invitation flow
- [ ] Call acceptance and rejection
- [ ] Agora channel joining
- [ ] Remote user detection

### Manual Testing Checklist

- [ ] **Audio Call**: Two users on same backend
  - [ ] Initiate audio call
  - [ ] Receive notification
  - [ ] Accept call
  - [ ] Hear audio
  - [ ] End call
  - [ ] Call appears in history

- [ ] **Video Call**: Two users on same backend
  - [ ] Initiate video call
  - [ ] See camera preview
  - [ ] Accept call
  - [ ] See remote video
  - [ ] Toggle camera on/off
  - [ ] Switch camera (front/back)
  - [ ] End call

- [ ] **Call Messages**: In chat history
  - [ ] Call invitation appears as message
  - [ ] Call accepted appears as message
  - [ ] Call declined appears as message
  - [ ] Call ended shows duration

- [ ] **Light Mode**: AppBar visibility
  - [ ] Call button visible (not white on white)
  - [ ] Video button visible
  - [ ] Colors match primary theme

- [ ] **Error Scenarios**:
  - [ ] Reject call while ringing
  - [ ] End call during conversation
  - [ ] Network disconnect during call
  - [ ] Permission denial

---

## 11. Architecture Diagram

```
┌──────────────────────────────────────────────────────────┐
│                    UI Layer                               │
├──────────────────────────────────────────────────────────┤
│                                                            │
│  EnhancedChatScreen        ActiveCallScreen               │
│  ┌─────────────────────┐   ┌──────────────────────────┐  │
│  │ Call/Video buttons  │   │ Video feed               │  │
│  │ CallMessageCard     │   │ Call duration timer      │  │
│  │ Message history     │   │ Controls (mute, camera)  │  │
│  └──────────┬──────────┘   └────────────┬─────────────┘  │
│             │                           │                 │
└─────────────┼───────────────────────────┼─────────────────┘
              │                           │
         ┌────┴───────┐                   │
         │             │                   │
┌────────▼────────────────────────────────▼────────┐
│              Service Layer                       │
├─────────────────────────────────────────────────┤
│                                                  │
│  CallSignalingService          AgoraCallService │
│  ├─ Send invitations            ├─ Initialize  │
│  ├─ Accept/Reject calls         ├─ Join channel│
│  ├─ Track call state            ├─ Media setup │
│  └─ Event streams               └─ Events      │
│         ↓                                       │
│  ChatWebSocketService                          │
│  ├─ Message routing                           │
│  ├─ Message parsing                           │
│  └─ WebSocket management                      │
│         ↓                                       │
└────────────────────────────────────────────────┘
           │
       ┌───┴──────────┐
       │              │
┌──────▼──────┐  ┌───▼────────────────────┐
│ Backend API │  │ Agora Cloud Network    │
│ - WebSocket │  │ - RTC channels         │
│ - Messages  │  │ - Media streams        │
└─────────────┘  └────────────────────────┘
```

---

## 12. Future Enhancements

### Phase 2: Production Readiness

1. **Background Calls**
   - Keep call active when app minimized
   - Use native CallKit (iOS) / ConnectionService (Android)

2. **Incoming Call Notification**
   - Show system-level call notification
   - Integration with notification service

3. **Call Persistence**
   - Store call history in local database
   - Sync with backend

4. **Network Optimization**
   - Quality indicators
   - Network fallback strategy
   - Bandwidth adaptation

### Phase 3: Advanced Features

1. **Group Calls**
   - Support >2 participants
   - Agora group channel management

2. **Screen Sharing**
   - Share screen during video call
   - Desktop client support

3. **Call Recording**
   - Local recording to device
   - Backend recording support

4. **Encryption**
   - E2E encryption for calls
   - Agora custom encryption

5. **Call Transfer**
   - Forward calls to other users
   - Conference merging

---

## 13. Performance Considerations

### Current Performance

- **Initialization**: CallSignalingService lazy-loads ChatWebSocketService
- **Memory**: Agora SDK ~30-50MB (includes native libraries)
- **Battery**: Audio call ~5% per hour, Video ~15% per hour
- **Bandwidth**: Audio 50-100 kbps, Video 500-2500 kbps (depends on quality)

### Optimization Tips

1. **Release Resources**
   ```dart
   @override
   void dispose() {
     _agoraService.dispose();  // Close Agora engine
     super.dispose();
   }
   ```

2. **Lazy Initialize**
   ```dart
   // Only init Agora when call is initiated
   // Not on app startup
   ```

3. **Handle Permissions Gracefully**
   ```dart
   // Don't crash if permissions denied
   // Show user-friendly error message
   ```

---

## 14. Known Issues & Limitations

### Issue 1: Incoming Call Notification
**Status**: ⚠️ NOT YET IMPLEMENTED  
**Impact**: Users don't see incoming calls
**Solution**: Create IncomingCallNotification screen triggered from ChatWebSocketService

### Issue 2: Background Call Handling
**Status**: ❌ NOT IMPLEMENTED  
**Impact**: Call disconnects if app backgrounded
**Solution**: Use native platform channels for background call support

### Issue 3: Call History Integration
**Status**: ⚠️ PARTIAL  
**Impact**: Shows device call logs, not chat-specific calls  
**Solution**: Sync Agora/signaling call data to database

### Issue 4: Ringtone Playback
**Status**: ⚠️ PLACEHOLDER  
**Impact**: No sound for incoming calls  
**Solution**: Use `audioplayers` or `assets_audio_player` plugin

### Issue 5: Token Expiration
**Status**: ⚠️ NEEDS HANDLING  
**Impact**: Long calls may fail when token expires  
**Solution**: Implement token refresh in AgoraCallService

---

## 15. Summary Table

| Component | Status | Lines | Key Dependency |
|-----------|--------|-------|-----------------|
| CallSignalingService | ✅ Complete | 404 | ChatWebSocketService |
| AgoraCallService | ✅ Complete | 380 | agora_rtc_engine 6.3.0 |
| ActiveCallScreen | ✅ Complete | 472 | AgoraCallService |
| IncomingCallScreen | ✅ Complete | 361 | CallSignalingService |
| CallMessageCard | ✅ Complete | 200 | Message model |
| Message Type Parsing | ✅ Complete | 3 locations | message.dart |
| Call Buttons | ✅ Complete | AppBar actions | CallSignalingService |
| WebSocket Integration | ✅ Complete | chat_websocket_service.dart | Backend API |
| System Call History | ✅ Complete | 905 | call_log plugin |
| **Incoming Notification** | ❌ Missing | - | UI trigger needed |
| **Background Calls** | ❌ Missing | - | Platform channels |
| **Ringtone** | ⚠️ Placeholder | - | audio plugin |

---

## 16. Quick Reference

### Key Files to Modify for New Features

```
To add call transfer:
  ├─ lib/services/call_signaling_service.dart (add transferCall method)
  ├─ lib/screens/calls/active_call_screen.dart (add transfer UI button)
  └─ Backend API (add transfer message type)

To add group calls:
  ├─ lib/services/agora_call_service.dart (use group channel)
  ├─ lib/models/chat.dart (track group call state)
  └─ lib/screens/calls/active_call_screen.dart (show multiple videos)

To add call recording:
  ├─ lib/services/agora_call_service.dart (enable recording)
  ├─ lib/screens/calls/active_call_screen.dart (add record button)
  └─ Backend (store recording metadata)
```

### Debug Commands

```dart
// Check if services initialized
debugPrint('Agora initialized: ${AgoraCallService().isInitialized}');
debugPrint('Signaling initialized: ${CallSignalingService()._initialized}');

// Monitor WebSocket messages
// (Already in ChatWebSocketService with 🎬 prefix)

// Check message type parsing
debugPrint('Message type: ${message.type}');
debugPrint('Is call: ${message.isCall}');
```

---

**Document Version**: 1.0  
**Last Reviewed**: February 1, 2026  
**Maintained By**: Development Team  
**Next Review**: February 15, 2026
