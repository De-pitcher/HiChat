# Background Media WebSocket Service

## Overview

This background media WebSocket service handles media upload operations (images, videos, audio) even when the HiChat app is in the background or closed. It provides seamless media capture and upload functionality with proper notifications and error handling.

## Features

- ✅ **Background Media Operations**: Capture and upload media while app is backgrounded
- ✅ **Multiple Media Types**: Support for images, video, audio, and auto sequences
- ✅ **Automatic Reconnection**: Maintains connection with exponential backoff
- ✅ **Message Queuing**: Queues media commands when offline
- ✅ **Push Notifications**: Notifies users of media operation progress
- ✅ **Cross-Platform**: Android and iOS support
- ✅ **Error Handling**: Comprehensive error management and logging
- ✅ **Permission Management**: Handles camera, microphone, and storage permissions

## Architecture

```
BackgroundMediaWebSocketService
├── Service Management (Start/Stop/Connect)
├── WebSocket Connection (wss://server/ws/media/upload/)
├── Media Command Handler
│   ├── Image Capture
│   ├── Video Recording  
│   ├── Audio Recording
│   └── Auto Media Sequence
├── Message Queue (Offline Support)
├── Reconnection Logic (Exponential Backoff)
└── Notification System
```

## Installation & Setup

### 1. Add to your main.dart

```dart
import 'package:your_app/services/hichat_media_background_service_integration.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize media background service
  await HiChatMediaBackgroundService.initialize();
  
  runApp(MyApp());
}
```

### 2. Add Required Permissions

#### Android (android/app/src/main/AndroidManifest.xml)
```xml
<!-- Camera and Media Permissions -->
<uses-permission android:name="android.permission.CAMERA" />
<uses-permission android:name="android.permission.RECORD_AUDIO" />
<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" />
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" />

<!-- Background Service Permissions -->
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_CAMERA" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_MICROPHONE" />
```

#### iOS (ios/Runner/Info.plist)
```xml
<key>NSCameraUsageDescription</key>
<string>This app needs camera access to capture images and videos in background</string>
<key>NSMicrophoneUsageDescription</key>
<string>This app needs microphone access to record audio in background</string>
<key>NSPhotoLibraryUsageDescription</key>
<string>This app needs photo library access to save captured media</string>
```

## Usage

### Basic Setup

```dart
// Start the service
await HiChatMediaBackgroundService.start();

// Connect to media WebSocket
await HiChatMediaBackgroundService.connect(userId: 'user123');
```

### Media Operations

#### 1. Image Capture
```dart
// Request background image capture
await HiChatMediaBackgroundService.requestImageCapture();

// The service will:
// 1. Show notification "Processing image upload request"
// 2. Capture image in background
// 3. Upload to server
// 4. Show completion notification "Image successfully captured and uploaded"
```

#### 2. Video Recording
```dart
// Request background video recording (30 seconds)
await HiChatMediaBackgroundService.requestVideoRecording(
  durationSeconds: 30,
);

// The service will:
// 1. Show notification "Processing video upload request"
// 2. Record video in background for specified duration
// 3. Upload to server
// 4. Show completion notification "Video successfully recorded and uploaded"
```

#### 3. Audio Recording
```dart
// Request background audio recording (60 seconds)
await HiChatMediaBackgroundService.requestAudioRecording(
  durationSeconds: 60,
);
```

#### 4. Auto Media Sequence
```dart
// Request automated media capture sequence
await HiChatMediaBackgroundService.requestAutoMediaSequence();

// This will capture image, then video, then audio automatically
```

### Advanced Usage

#### Listen for Media Events
```dart
void setupMediaWebSocketListener() {
  final service = FlutterBackgroundService();
  
  service.on('media_websocket_message').listen((event) {
    final data = event!['data'] as Map<String, dynamic>;
    
    if (data['command'] == 'send_media') {
      final mediaType = data['media_type'] as String;
      print('Media operation started: $mediaType');
      
      // Update UI to show media operation in progress
      _showMediaOperationInProgress(mediaType);
    }
  });
}
```

#### Custom Media Commands
```dart
// Send custom media command with additional parameters
await HiChatMediaBackgroundService.sendMediaCommand(
  mediaType: 'image',
  additionalData: {
    'quality': 'high',
    'compression': 85,
    'format': 'jpeg',
  },
);
```

### Service Management

```dart
// Check if service is running
bool isRunning = await HiChatMediaBackgroundService.isServiceRunning();

// Check connection status
bool isConnected = await HiChatMediaBackgroundService.isConnected();

// Stop the service
await HiChatMediaBackgroundService.stop();

// Disconnect from WebSocket
await HiChatMediaBackgroundService.disconnect();
```

## Integration with Chat Service

You can run both chat and media background services simultaneously:

```dart
// Initialize both services
await HiChatBackgroundService.initialize();
await HiChatMediaBackgroundService.initialize();

// Start both services
await HiChatBackgroundService.start();
await HiChatMediaBackgroundService.start();

// Connect both WebSockets
await HiChatBackgroundService.connect(userId: userId, token: token);
await HiChatMediaBackgroundService.connect(userId: userId);

// Both services will run independently in background
```

## Notifications

The service shows different notifications for various states:

### Service Status Notifications
- **"Media service ready"** - Service initialized
- **"Media service running"** - Connected and ready
- **"Media attempt X in Ys"** - Reconnecting
- **"Media connection failed"** - Connection failed

### Media Operation Notifications
- **"Processing image upload request"** - Image capture started
- **"Image successfully captured and uploaded"** - Image complete  
- **"Processing video upload request"** - Video recording started
- **"Video successfully recorded and uploaded"** - Video complete
- **"Processing audio upload request"** - Audio recording started
- **"Audio successfully recorded and uploaded"** - Audio complete
- **"All media captured and uploaded successfully"** - Auto sequence complete

## Error Handling

The service handles various error scenarios:

### Connection Errors
- **HTTP 500 Server Error**: Uses longer retry delays
- **WebSocket Upgrade Failed**: Detailed error logging
- **Network Connectivity Issues**: Automatic reconnection with exponential backoff
- **Authentication Failures**: Proper error reporting

### Media Operation Errors
- **Permission Denied**: User needs to grant camera/microphone permissions
- **Storage Full**: Not enough space for media files
- **Hardware Unavailable**: Camera or microphone in use by another app
- **Timeout**: Media operation took too long

### Retry Logic
- **Initial Delay**: 2 seconds
- **Maximum Delay**: 30 seconds  
- **Maximum Attempts**: 10
- **Server Error Delay**: 10 seconds (for HTTP 5xx errors)
- **Exponential Backoff**: 2^attempt * base_delay

## Configuration

### WebSocket URL
```dart
// Default URL (in BackgroundMediaWebSocketService)
static const String _wsUrl = 'wss://chatcornerbackend-production.up.railway.app/ws/media/upload/?username=';

// To use custom URL, modify the _wsUrl constant
```

### Notification Settings
```dart
// Customize notification channel (in BackgroundMediaWebSocketService)
static const String _notificationChannelId = 'hichat_media_websocket';
static const String _notificationChannelName = 'HiChat Media WebSocket';

// Notification ID for media operations
const int mediaNotificationId = 999;
```

### Queue Settings
```dart
// Maximum queued messages when offline
static const int _maxQueueSize = 50;

// Message flush delay when reconnecting
const Duration messageFlushDelay = Duration(milliseconds: 100);
```

## Troubleshooting

### Common Issues

1. **Service Not Starting**
   - Check if background service permissions are granted
   - Verify notification permissions are enabled
   - Ensure proper initialization in main.dart

2. **Media Operations Not Working**
   - Verify camera/microphone permissions are granted
   - Check if device has sufficient storage space
   - Ensure no other apps are using camera/microphone

3. **Connection Issues**
   - Check network connectivity
   - Verify WebSocket server is running
   - Check server logs for connection errors

4. **Notifications Not Showing**
   - Verify notification permissions are granted
   - Check if notification channels are properly created
   - Ensure app is not in battery optimization mode

### Debug Logging

Enable detailed logging by checking the system logs:

```bash
# Android
adb logcat | grep -E "(BackgroundMediaWS|HiChatMediaWS)"

# Look for these log tags:
# - BackgroundMediaWS: Core service logs
# - BackgroundMediaServiceImpl: Background operation logs  
# - HiChatMediaWS: Integration layer logs
```

### Log Messages to Look For

- `🚀 FINAL URL BEING PASSED TO Media WebSocketChannel.connect()` - Shows exact WebSocket URL
- `Media WebSocket connected successfully` - Connection established
- `Media operation already in progress` - Multiple operations attempted
- `Media WebSocket error:` - Connection or operation errors
- `Queued media message sent` - Offline message sent after reconnection

## Performance Considerations

### Battery Usage
- Media operations are resource intensive
- Service uses foreground mode to prevent system killing
- Automatic disconnect when not needed to save battery

### Memory Management
- Message queue limited to 50 items
- Media files are processed and uploaded immediately
- Background operations are optimized for minimal resource usage

### Network Usage
- WebSocket connection maintained with minimal overhead
- Media uploads use efficient compression
- Automatic retry with exponential backoff prevents network flooding

## Security

### Data Protection
- WebSocket connection uses WSS (secure WebSocket)
- Authentication tokens are securely stored
- Media files are encrypted during upload

### Permission Handling
- Runtime permission requests for camera/microphone
- Graceful degradation when permissions denied
- Clear permission rationale to users

This background media service provides enterprise-grade media handling capabilities while maintaining excellent user experience and system resource efficiency.