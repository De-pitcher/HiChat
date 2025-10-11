import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/background_service_provider.dart';

/// Dialog showing background service status and controls
class BackgroundServiceStatusDialog extends StatelessWidget {
  const BackgroundServiceStatusDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<BackgroundServiceProvider>(
      builder: (context, backgroundService, child) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.cloud, color: Colors.blue),
              SizedBox(width: 8),
              Text('Background Service'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildStatusRow('Status', backgroundService.connectionStatus),
              const SizedBox(height: 8),
              _buildStatusRow(
                'Service Running', 
                backgroundService.isServiceRunning ? 'Yes' : 'No',
                color: backgroundService.isServiceRunning ? Colors.green : Colors.red,
              ),
              const SizedBox(height: 8),
              _buildStatusRow(
                'Connected', 
                backgroundService.isConnected ? 'Yes' : 'No',
                color: backgroundService.isConnected ? Colors.green : Colors.red,
              ),
              const SizedBox(height: 8),
              if (backgroundService.currentUsername != null)
                _buildStatusRow('Username', backgroundService.currentUsername!),
              const SizedBox(height: 8),
              _buildStatusRow(
                'Health', 
                backgroundService.serviceHealthStatus,
                color: backgroundService.isServiceHealthy ? Colors.green : Colors.orange,
              ),
              const SizedBox(height: 16),
              Text(
                'Recent Messages: ${backgroundService.recentMessages.length}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              Text(
                'The background service keeps your chat connection alive even when the app is closed or in background.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
          actions: [
            if (!backgroundService.isServiceRunning && backgroundService.currentUsername != null)
              TextButton.icon(
                onPressed: () async {
                  await backgroundService.restartService();
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Start Service'),
              ),
            if (backgroundService.isServiceRunning && !backgroundService.isConnected)
              TextButton.icon(
                onPressed: () async {
                  await backgroundService.restartService();
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Reconnect'),
              ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildStatusRow(String label, String value, {Color? color}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 80,
          child: Text(
            '$label:',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(color: color),
          ),
        ),
      ],
    );
  }
}

/// Show the background service status dialog
void showBackgroundServiceStatus(BuildContext context) {
  showDialog(
    context: context,
    builder: (context) => const BackgroundServiceStatusDialog(),
  );
}