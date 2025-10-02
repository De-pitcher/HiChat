import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/location_websocket_service.dart';

class LocationSharingScreen extends StatefulWidget {
  final String username;
  
  const LocationSharingScreen({
    super.key,
    required this.username,
  });

  @override
  State<LocationSharingScreen> createState() => _LocationSharingScreenState();
}

class _LocationSharingScreenState extends State<LocationSharingScreen> {
  final LocationWebSocketService _locationService = LocationWebSocketService.instance;
  bool _isConnected = false;
  String _connectionStatus = 'Disconnected';

  @override
  void initState() {
    super.initState();
    _updateConnectionStatus();
  }

  void _updateConnectionStatus() {
    setState(() {
      _isConnected = _locationService.isConnected;
      _connectionStatus = _isConnected ? 'Connected' : 'Disconnected';
    });
  }

  Future<void> _connectLocationWebSocket() async {
    try {
      await _locationService.connectWebSocket(widget.username);
      _updateConnectionStatus();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Location WebSocket connected'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to connect: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _disconnectLocationWebSocket() async {
    await _locationService.closeWebSocket();
    _updateConnectionStatus();
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Location WebSocket disconnected'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  Future<void> _shareCurrentLocation() async {
    try {
      await _locationService.shareCurrentLocation();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Location shared successfully'),
            backgroundColor: Colors.blue,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to share location: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    // Note: Don't dispose the service here as it's used globally
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          'Location Sharing',
          style: GoogleFonts.lato(
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: theme.scaffoldBackgroundColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: theme.colorScheme.onSurface),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Connection Status Card
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  children: [
                    Icon(
                      _isConnected ? Icons.wifi : Icons.wifi_off,
                      size: 48,
                      color: _isConnected ? Colors.green : Colors.red,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Connection Status',
                      style: GoogleFonts.lato(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _connectionStatus,
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        color: _isConnected ? Colors.green : Colors.red,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (_isConnected) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Username: ${widget.username}',
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 32),
            
            // Connect/Disconnect Button
            if (!_isConnected)
              ElevatedButton.icon(
                onPressed: _connectLocationWebSocket,
                icon: const Icon(Icons.connect_without_contact),
                label: const Text('Connect Location WebSocket'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              )
            else ...[
              ElevatedButton.icon(
                onPressed: _disconnectLocationWebSocket,
                icon: const Icon(Icons.close),
                label: const Text('Disconnect'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              
              const SizedBox(height: 16),
              
              // Share Location Button
              ElevatedButton.icon(
                onPressed: _shareCurrentLocation,
                icon: const Icon(Icons.my_location),
                label: const Text('Share Current Location'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
            
            const Spacer(),
            
            // Information Card
            Card(
              elevation: 1,
              color: theme.colorScheme.surfaceContainerHighest,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'How it works',
                          style: GoogleFonts.lato(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '• Connect to the location WebSocket service\n'
                      '• Server can request your location remotely\n'
                      '• You can also manually share your location\n'
                      '• Connection automatically reconnects if lost',
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}