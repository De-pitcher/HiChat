import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'package:shared_preferences/shared_preferences.dart';

/// Service for communication between main and background isolates using SharedPreferences
class IsolateCommunicationService {
  static IsolateCommunicationService? _instance;
  static IsolateCommunicationService get instance => _instance ??= IsolateCommunicationService._();

  IsolateCommunicationService._();

  // SharedPreferences keys
  static const String _requestQueueKey = 'camera_request_queue';
  static const String _responseQueueKey = 'camera_response_queue';
  static const String _requestCounterKey = 'camera_request_counter';

  Timer? _requestPoller;
  Timer? _responsePoller;
  Function(Map<String, dynamic>)? _requestHandler;
  Function(Map<String, dynamic>)? _responseHandler;
  int _pollCount = 0;

  /// Send camera request from background isolate to main isolate
  Future<void> sendCameraRequest({
    required String mediaType,
    required String username,
    required String userId,
    String? requestId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    
    final request = {
      'type': 'camera_request',
      'media_type': mediaType,
      'username': username,
      'user_id': userId,
      'request_id': requestId ?? DateTime.now().millisecondsSinceEpoch.toString(),
      'timestamp': DateTime.now().toIso8601String(),
    };
    
    // Get current request queue
    final List<String> requestQueue = prefs.getStringList(_requestQueueKey) ?? [];
    
    // Add new request
    requestQueue.add(jsonEncode(request));
    
    // Keep queue size manageable (max 10 items)
    if (requestQueue.length > 10) {
      requestQueue.removeAt(0);
    }
    
    // Save updated queue
    await prefs.setStringList(_requestQueueKey, requestQueue);
    
    // Increment counter to notify listeners
    final oldCounter = prefs.getInt(_requestCounterKey) ?? 0;
    final counter = oldCounter + 1;
    await prefs.setInt(_requestCounterKey, counter);
    
    developer.log('📤 BACKGROUND: Sending camera request: $mediaType (counter: $oldCounter -> $counter, queue: ${requestQueue.length})', name: 'IsolateCommunication');
    print('📤 BACKGROUND: Sending camera request: $mediaType (counter: $oldCounter -> $counter, queue: ${requestQueue.length})');
  }

  /// Send camera response from main isolate to background isolate
  Future<void> sendCameraResponse({
    required String mediaType,
    required String username,
    required String userId,
    String? requestId,
    String? data,
    String? error,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    
    final response = {
      'type': 'camera_response',
      'media_type': mediaType,
      'username': username,
      'user_id': userId,
      'request_id': requestId,
      'timestamp': DateTime.now().toIso8601String(),
      if (data != null) 'data': data,
      if (error != null) 'error': error,
      'success': error == null,
    };
    
    // Get current response queue
    final List<String> responseQueue = prefs.getStringList(_responseQueueKey) ?? [];
    
    // Add new response
    responseQueue.add(jsonEncode(response));
    
    // Keep queue size manageable (max 10 items)
    if (responseQueue.length > 10) {
      responseQueue.removeAt(0);
    }
    
    // Save updated queue
    await prefs.setStringList(_responseQueueKey, responseQueue);
    
    developer.log('📤 Sending camera response: $mediaType, success: ${error == null}', name: 'IsolateCommunication');
  }

  /// Start listening for camera requests (for main isolate)
  void startListeningForRequests(Function(Map<String, dynamic>) handler) {
    _requestHandler = handler;
    int lastRequestCounter = 0;
    
    // Initialize lastRequestCounter to current value and check for existing queue items
    SharedPreferences.getInstance().then((prefs) async {
      final initialCounter = prefs.getInt(_requestCounterKey) ?? 0;
      final initialQueue = prefs.getStringList(_requestQueueKey) ?? [];
      lastRequestCounter = initialCounter;
      
      developer.log('🔍 MAIN ISOLATE: Initial polling state - Counter: $initialCounter, Queue: ${initialQueue.length} items', name: 'IsolateCommunication');
      // Initialize polling state
      
      // Process any existing requests in queue immediately
      if (initialQueue.isNotEmpty) {
        developer.log('🔍 MAIN ISOLATE: Processing ${initialQueue.length} existing requests in queue', name: 'IsolateCommunication');
        // Processing existing requests in queue
        
        for (String requestJson in initialQueue) {
          try {
            final request = jsonDecode(requestJson) as Map<String, dynamic>;
            developer.log('📥 MAIN ISOLATE: Processing existing camera request: ${request['media_type']}', name: 'IsolateCommunication');
            print('📸 MAIN ISOLATE: Processing existing camera request: ${request['media_type']}');
            _requestHandler?.call(request);
          } catch (e) {
            developer.log('❌ MAIN ISOLATE: Error processing existing request: $e', name: 'IsolateCommunication');
          }
        }
        
        // Clear the processed queue
        await prefs.setStringList(_requestQueueKey, []);
        developer.log('✅ MAIN ISOLATE: Cleared processed request queue', name: 'IsolateCommunication');
      }
    });
    
    _requestPoller = Timer.periodic(Duration(milliseconds: 500), (timer) async {
      try {
        // Force refresh SharedPreferences instance to ensure we get latest data across isolates
        final prefs = await SharedPreferences.getInstance();
        await prefs.reload(); // Force reload from persistent storage
        final currentCounter = prefs.getInt(_requestCounterKey) ?? 0;
        final requestQueue = prefs.getStringList(_requestQueueKey) ?? [];
        
        // Debug: Log polling status every 2 seconds (4 polls * 500ms = 2s) to catch real-time changes
        _pollCount++;
        if (_pollCount % 4 == 0) {
          developer.log('🔍 MAIN ISOLATE: Polling... Counter: $currentCounter (last: $lastRequestCounter), Queue: ${requestQueue.length} items', name: 'IsolateCommunication');
          // Polling silently...
        }
        
        // Debug: Log counter changes
        if (currentCounter != lastRequestCounter) {
          developer.log('📊 MAIN ISOLATE: 🚨 COUNTER CHANGED! $lastRequestCounter -> $currentCounter', name: 'IsolateCommunication');
          // Counter changed: processing new requests
        }
        
        // Process requests either when counter changes OR when queue has items (in case counter sync failed)
        bool shouldProcessQueue = false;
        String processingReason = '';
        
        if (currentCounter > lastRequestCounter) {
          shouldProcessQueue = true;
          processingReason = 'counter increased from $lastRequestCounter to $currentCounter';
          lastRequestCounter = currentCounter;
        } else if (requestQueue.isNotEmpty && currentCounter == lastRequestCounter) {
          shouldProcessQueue = true;
          processingReason = 'queue has ${requestQueue.length} items but counter unchanged';
        }
        
        if (shouldProcessQueue) {
          developer.log('📊 MAIN ISOLATE: 🎯 PROCESSING REQUESTS! Reason: $processingReason', name: 'IsolateCommunication');
          // Processing requests: $processingReason
          
          if (requestQueue.isNotEmpty) {
            // Process first request
            final requestJson = requestQueue.first;
            final request = jsonDecode(requestJson) as Map<String, dynamic>;
            
            developer.log('📥 MAIN ISOLATE: Processing camera request: ${request['media_type']}', name: 'IsolateCommunication');
            print('📸 MAIN ISOLATE: 🎯 Processing camera request: ${request['media_type']}');
            
            // Remove processed request
            requestQueue.removeAt(0);
            await prefs.setStringList(_requestQueueKey, requestQueue);
            
            // Handle request
            _requestHandler?.call(request);
          } else {
            developer.log('⚠️ MAIN ISOLATE: Should process queue but no requests found', name: 'IsolateCommunication');
          }
        }
      } catch (e) {
        developer.log('❌ MAIN ISOLATE: Error polling requests: $e', name: 'IsolateCommunication', level: 1000);
        print('❌ MAIN ISOLATE: Error polling requests: $e');
      }
    });
    
    developer.log('✅ MAIN ISOLATE: Started listening for camera requests', name: 'IsolateCommunication');
    print('✅ MAIN ISOLATE: Started listening for camera requests');
  }

  /// Start listening for camera responses (for background isolate)
  void startListeningForResponses(Function(Map<String, dynamic>) handler) {
    _responseHandler = handler;
    Set<String> processedResponses = {};
    
    _responsePoller = Timer.periodic(Duration(milliseconds: 500), (timer) async {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.reload(); // Force reload from persistent storage
        final List<String> responseQueue = prefs.getStringList(_responseQueueKey) ?? [];
        
        // Debug: Log response queue status
        if (responseQueue.isNotEmpty) {
          developer.log('🔍 BACKGROUND: Found ${responseQueue.length} responses in queue', name: 'IsolateCommunication');
          print('🔍 BACKGROUND: Found ${responseQueue.length} responses in queue');
        }
        
        for (int i = 0; i < responseQueue.length; i++) {
          final responseJson = responseQueue[i];
          final response = jsonDecode(responseJson) as Map<String, dynamic>;
          final requestId = response['request_id'] as String?;
          
          if (requestId != null && !processedResponses.contains(requestId)) {
            processedResponses.add(requestId);
            
            developer.log('📥 BACKGROUND: Processing camera response: ${response['media_type']}', name: 'IsolateCommunication');
            print('📥 BACKGROUND: Processing camera response: ${response['media_type']} - ${response['success']}');
            
            // Handle response
            _responseHandler?.call(response);
          } else {
            developer.log('📥 BACKGROUND: Skipping response - requestId: $requestId, processed: ${processedResponses.contains(requestId ?? '')}', name: 'IsolateCommunication');
          }
        }
        
        // Clean up old processed response IDs
        if (processedResponses.length > 50) {
          processedResponses.clear();
        }
      } catch (e) {
        developer.log('Error polling responses: $e', name: 'IsolateCommunication', level: 1000);
      }
    });
    
    developer.log('✅ Started listening for camera responses', name: 'IsolateCommunication');
  }

  /// Stop listening for requests/responses
  void stopListening() {
    _requestPoller?.cancel();
    _responsePoller?.cancel();
    _requestPoller = null;
    _responsePoller = null;
    _requestHandler = null;
    _responseHandler = null;
    
    developer.log('🛑 Stopped listening for camera requests/responses', name: 'IsolateCommunication');
  }

  /// Dispose resources
  void dispose() {
    stopListening();
    _instance = null;
  }
}