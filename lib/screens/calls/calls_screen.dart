import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:call_log/call_log.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:provider/provider.dart';
import '../../constants/app_theme.dart';
import '../../services/auth_state_manager.dart';
import '../../services/api_service.dart';
import '../../models/bulk_upload_models.dart';

class CallsScreen extends StatefulWidget {
  const CallsScreen({super.key});

  @override
  State<CallsScreen> createState() => _CallsScreenState();
}

class _CallsScreenState extends State<CallsScreen> with TickerProviderStateMixin {
  late TabController _tabController;
  List<CallLogEntry> _callLogs = [];
  bool _isLoading = true;
  bool _hasPermission = false;
  bool _hasMoreLogs = true;
  bool _isLoadingMore = false;
  DateTime? _lastLoadedTimestamp;
  static const int _daysPerPage = 7; // Load 7 days of call logs at a time
  static const int _maxLogsPerPage = 100; // Maximum logs per page as safety limit
  String _dialpadNumber = '';
  final TextEditingController _dialpadController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _setupScrollListener();
    _loadCallLogs();
  }

  void _setupScrollListener() {
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >= 
          _scrollController.position.maxScrollExtent * 0.8) {
        // Load more when user scrolls to 80% of the list
        _loadMoreCallLogs();
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _dialpadController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadCallLogs() async {
    setState(() {
      _isLoading = true;
      _lastLoadedTimestamp = null; // Reset for initial load
      _callLogs.clear();
      _hasMoreLogs = true;
    });

    await _requestPermissionsAndLoadLogs();
  }

  Future<void> _loadMoreCallLogs() async {
    if (_isLoadingMore || !_hasMoreLogs || _isLoading) return;

    setState(() {
      _isLoadingMore = true;
    });

    await _requestPermissionsAndLoadLogs();
  }

  Future<void> _requestPermissionsAndLoadLogs() async {
    try {
      // Request permissions first
      debugPrint('🔄 Requesting permissions for call logs...');
      
      Map<Permission, PermissionStatus> permissions = await [
        Permission.phone,
        Permission.sms, // Sometimes needed for call logs on some devices
      ].request();
      
      debugPrint('Phone permission: ${permissions[Permission.phone]}');
      debugPrint('SMS permission: ${permissions[Permission.sms]}');
      
      bool hasPhonePermission = permissions[Permission.phone]?.isGranted ?? false;
      
      if (!hasPhonePermission) {
        _showPermissionDialog();
        setState(() {
          _hasPermission = false;
          _isLoading = false;
          _isLoadingMore = false;
        });
        return;
      }

      // Load call logs with pagination
      await _loadCallLogsPage();

    } catch (e) {
      debugPrint('❌ Error with permission handling: $e');
      _showCallLogPermissionError();
      setState(() {
        _hasPermission = false;
        _isLoading = false;
        _isLoadingMore = false;
      });
    }
  }

  Future<void> _loadCallLogsPage() async {
    try {
      final now = DateTime.now();
      
      // Calculate the date range for this page
      DateTime dateTo;
      DateTime dateFrom;
      
      if (_lastLoadedTimestamp == null) {
        // First page: load most recent 7 days
        dateTo = now;
        dateFrom = now.subtract(Duration(days: _daysPerPage));
      } else {
        // Subsequent pages: load next 7 days going backwards
        dateTo = _lastLoadedTimestamp!;
        dateFrom = _lastLoadedTimestamp!.subtract(Duration(days: _daysPerPage));
      }
      
      debugPrint('📞 Loading call logs - DateFrom: ${dateFrom.toIso8601String()}, DateTo: ${dateTo.toIso8601String()}');
      
      // Query only the specific date range to avoid loading all logs
      final Iterable<CallLogEntry> entries = await CallLog.query(
        dateFrom: dateFrom.millisecondsSinceEpoch,
        dateTo: dateTo.millisecondsSinceEpoch,
      );
      
      final pageData = entries.toList();
      
      // Sort by timestamp (most recent first)
      pageData.sort((a, b) => (b.timestamp ?? 0).compareTo(a.timestamp ?? 0));
      
      // Limit the number of logs per page as a safety measure
      final limitedPageData = pageData.take(_maxLogsPerPage).toList();
      
      // Check if we have more data
      final hasMoreInTimeRange = pageData.length >= _maxLogsPerPage;
      final isOlderThanOneYear = dateFrom.isBefore(now.subtract(const Duration(days: 365)));
      final hasMore = hasMoreInTimeRange || !isOlderThanOneYear;
      
      setState(() {
        if (_lastLoadedTimestamp == null) {
          // Initial load - replace all data
          _callLogs = limitedPageData;
        } else {
          // Load more - append data
          _callLogs.addAll(limitedPageData);
        }
        
        _hasPermission = true;
        _isLoading = false;
        _isLoadingMore = false;
        _hasMoreLogs = hasMore && limitedPageData.isNotEmpty;
        
        // Update the timestamp for next page
        if (limitedPageData.isNotEmpty) {
          _lastLoadedTimestamp = dateFrom;
        }
      });

      debugPrint('✅ Loaded ${limitedPageData.length} call logs (Total: ${_callLogs.length}, HasMore: $hasMore)');
      
      // Upload call logs to server in bulk (only on initial load, not load more)
      if (_lastLoadedTimestamp == dateFrom && _callLogs.isNotEmpty) {
        await _uploadCallLogsBulk(_callLogs);
      }
      
    } catch (e) {
      debugPrint('❌ Error loading call logs page: $e');
      _showCallLogPermissionError();
      setState(() {
        _hasPermission = false;
        _isLoading = false;
        _isLoadingMore = false;
      });
    }
  }

  Future<void> _uploadCallLogsBulk(List<CallLogEntry> callLogs) async {
    try {
      final authManager = context.read<AuthStateManager>();
      final currentUser = authManager.currentUser;
      
      if (currentUser == null) {
        debugPrint('Cannot upload call logs: No authenticated user found');
        return;
      }

      debugPrint('Starting bulk call logs upload for ${callLogs.length} call logs');

      // Convert call log entries to our API format
      final List<CallLogData> callLogsData = callLogs.map((callLog) {
        // Determine call type: assume all are audio calls since call_log doesn't distinguish
        final callType = "1"; // "1" = Audio, "2" = Video
        
        // Convert direction
        String direction;
        switch (callLog.callType) {
          case CallType.incoming:
            direction = "INCOMING";
            break;
          case CallType.outgoing:
            direction = "OUTGOING";
            break;
          case CallType.missed:
            direction = "INCOMING"; // Missed calls are technically incoming
            break;
          case CallType.rejected:
            direction = "INCOMING"; // Rejected calls are technically incoming
            break;
          default:
            direction = "INCOMING";
        }
        
        return CallLogData(
          number: callLog.number ?? '',
          callType: callType,
          direction: direction,
          date: (callLog.timestamp ?? 0).toString(),
          duration: (callLog.duration ?? 0).toString(),
        );
      }).where((callData) => callData.number.isNotEmpty).toList();

      if (callLogsData.isEmpty) {
        debugPrint('No valid call logs to upload (all missing phone numbers)');
        return;
      }

      // Upload to server
      final apiService = ApiService();
      final response = await apiService.uploadCallLogsBulk(
        owner: currentUser.id.toString(),
        callList: callLogsData,
      );

      debugPrint('Bulk call logs upload successful: ${response.message}');
      debugPrint('Created: ${response.created}, Skipped: ${response.skipped}, Total: ${response.totalProcessed}');

      // Show success message to user
      if (mounted) {
        final successMessage = response.created > 0 
            ? 'Call logs synced: ${response.created} uploaded successfully'
            : 'All ${response.totalProcessed} call logs were already synced';
            
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(successMessage),
            backgroundColor: response.created > 0 ? Colors.green : Colors.blue,
            duration: const Duration(seconds: 3),
          ),
        );
      }

    } catch (e) {
      debugPrint('Error uploading call logs in bulk: $e');
      
      // Show error message to user
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to sync call logs: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  void _showPermissionDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Phone Permission Required'),
          content: const Text(
            'This app needs access to your phone and call logs to display call history.\n\n'
            'Please enable the following permissions in Settings:\n'
            '• Phone\n'
            '• SMS (sometimes required)\n'
            '• Call logs\n\n'
            'Go to: Settings > Apps > HiChat > Permissions',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                openAppSettings();
              },
              child: const Text('Open Settings'),
            ),
          ],
        );
      },
    );
  }

  void _showCallLogPermissionError() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Call Log Access Required'),
          content: const Text(
            'Unable to access call logs. This may be due to:\n\n'
            '• Missing phone permissions\n'
            '• Device security settings\n'
            '• Call log access restrictions\n\n'
            'Please enable all phone-related permissions in Settings > Apps > HiChat > Permissions.\n\n'
            'Required permissions:\n'
            '• Phone\n'
            '• Call logs (if available)',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _loadCallLogs(); // Retry loading
              },
              child: const Text('Retry'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                openAppSettings();
              },
              child: const Text('Open Settings'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Calls'),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        foregroundColor: Theme.of(context).textTheme.titleLarge?.color,
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.primary,
          unselectedLabelColor: Theme.of(context).textTheme.bodyLarge?.color?.withValues(alpha: 0.6),
          indicatorColor: AppColors.primary,
          tabs: const [
            Tab(
              icon: Icon(Icons.access_time),
              text: 'Recent',
            ),
            Tab(
              icon: Icon(Icons.dialpad),
              text: 'Dialpad',
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildCallLogsTab(),
          _buildDialpadTab(),
        ],
      ),
    );
  }

  Widget _buildCallLogsTab() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading call logs...'),
          ],
        ),
      );
    }

    if (!_hasPermission) {
      return _buildPermissionDenied();
    }

    if (_callLogs.isEmpty) {
      return _buildEmptyCallLogs();
    }

    return RefreshIndicator(
      onRefresh: () async {
        await _loadCallLogs();
      },
      child: _buildCallLogsList(),
    );
  }

  Widget _buildPermissionDenied() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.phone_disabled,
              size: 64,
              color: Theme.of(context).disabledColor,
            ),
            const SizedBox(height: 24),
            Text(
              'Phone Access Required',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Text(
              'To view your call history, please grant phone permissions in Settings.',
              style: Theme.of(context).textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: _loadCallLogs,
              icon: const Icon(Icons.refresh),
              label: const Text('Try Again'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: () => openAppSettings(),
              icon: const Icon(Icons.settings),
              label: const Text('Open Settings'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyCallLogs() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.call,
              size: 64,
              color: Theme.of(context).disabledColor,
            ),
            const SizedBox(height: 24),
            Text(
              'No Call History',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Text(
              'Your recent calls will appear here.',
              style: Theme.of(context).textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: _loadCallLogs,
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCallLogsList() {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _callLogs.length + (_hasMoreLogs ? 1 : 0), // Add 1 for loading indicator
      itemBuilder: (context, index) {
        // Show loading indicator at the bottom
        if (index >= _callLogs.length) {
          return _buildLoadingIndicator();
        }

        final callLog = _callLogs[index];
        final displayName = callLog.name ?? callLog.number ?? 'Unknown';
        final phoneNumber = callLog.number ?? '';

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Theme.of(context).shadowColor.withValues(alpha: 0.1),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: CircleAvatar(
              backgroundColor: AppColors.primary.withValues(alpha: 0.1),
              child: Icon(
                Icons.person,
                color: AppColors.primary,
              ),
            ),
            title: Text(
              displayName,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (phoneNumber.isNotEmpty)
                  Text(
                    phoneNumber,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).textTheme.bodySmall?.color,
                    ),
                  ),
                Row(
                  children: [
                    Icon(
                      _getCallTypeIcon(callLog.callType),
                      size: 16,
                      color: _getCallTypeColor(callLog.callType),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _formatCallTime(callLog.timestamp),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (callLog.duration != null && callLog.duration! > 0) ...[
                      const SizedBox(width: 8),
                      const Text('·'),
                      const SizedBox(width: 8),
                      Text(
                        _formatCallDuration(callLog.duration),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ],
            ),
            trailing: IconButton(
              onPressed: () => _makeCall(phoneNumber),
              icon: Icon(
                Icons.call,
                color: AppColors.primary,
              ),
              tooltip: 'Call back',
            ),
            onTap: () => _makeCall(phoneNumber),
          ),
        );
      },
    );
  }

  Widget _buildLoadingIndicator() {
    return Container(
      padding: const EdgeInsets.all(16),
      alignment: Alignment.center,
      child: _isLoadingMore
          ? Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'Loading more calls...',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).textTheme.bodySmall?.color,
                  ),
                ),
              ],
            )
          : const SizedBox.shrink(),
    );
  }

  Widget _buildDialpadTab() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        children: [
          // Phone number display
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Theme.of(context).dividerColor,
              ),
            ),
            child: TextField(
              controller: _dialpadController,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
              decoration: const InputDecoration(
                hintText: 'Enter phone number',
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
              keyboardType: TextInputType.phone,
              onChanged: (value) {
                setState(() {
                  _dialpadNumber = value;
                });
              },
            ),
          ),
          
          const SizedBox(height: 32),
          
          // Dialpad
          Expanded(
            child: GridView.count(
              crossAxisCount: 3,
              childAspectRatio: 1.2,
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              shrinkWrap: true,
              children: [
                _buildDialpadButton('1', ''),
                _buildDialpadButton('2', 'ABC'),
                _buildDialpadButton('3', 'DEF'),
                _buildDialpadButton('4', 'GHI'),
                _buildDialpadButton('5', 'JKL'),
                _buildDialpadButton('6', 'MNO'),
                _buildDialpadButton('7', 'PQRS'),
                _buildDialpadButton('8', 'TUV'),
                _buildDialpadButton('9', 'WXYZ'),
                _buildDialpadButton('*', ''),
                _buildDialpadButton('0', '+'),
                _buildDialpadButton('#', ''),
              ],
            ),
          ),
          
          const SizedBox(height: 24),
          
          // Action buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // Backspace button
              IconButton(
                onPressed: _dialpadNumber.isNotEmpty ? _backspace : null,
                icon: const Icon(Icons.backspace),
                iconSize: 28,
                tooltip: 'Backspace',
              ),
              
              // Call button
              FloatingActionButton(
                onPressed: _dialpadNumber.isNotEmpty ? () => _makeCall(_dialpadNumber) : null,
                backgroundColor: _dialpadNumber.isNotEmpty ? Colors.green : Colors.grey,
                child: const Icon(
                  Icons.call,
                  color: Colors.white,
                ),
              ),
              
              // Clear button
              IconButton(
                onPressed: _dialpadNumber.isNotEmpty ? _clear : null,
                icon: const Icon(Icons.clear),
                iconSize: 28,
                tooltip: 'Clear',
              ),
            ],
          ),
          
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildDialpadButton(String number, String letters) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(50),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).shadowColor.withValues(alpha: 0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _addDigit(number),
          borderRadius: BorderRadius.circular(50),
          child: Container(
            alignment: Alignment.center,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  number,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (letters.isNotEmpty)
                  Text(
                    letters,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).textTheme.bodySmall?.color?.withValues(alpha: 0.7),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _addDigit(String digit) {
    setState(() {
      _dialpadNumber += digit;
      _dialpadController.text = _dialpadNumber;
    });
    
    // Haptic feedback
    HapticFeedback.lightImpact();
  }

  void _backspace() {
    if (_dialpadNumber.isNotEmpty) {
      setState(() {
        _dialpadNumber = _dialpadNumber.substring(0, _dialpadNumber.length - 1);
        _dialpadController.text = _dialpadNumber;
      });
      
      HapticFeedback.lightImpact();
    }
  }

  void _clear() {
    setState(() {
      _dialpadNumber = '';
      _dialpadController.clear();
    });
    
    HapticFeedback.lightImpact();
  }

  Future<void> _makeCall(String phoneNumber) async {
    if (phoneNumber.isEmpty) return;
    
    try {
      final Uri phoneUri = Uri(scheme: 'tel', path: phoneNumber);
      if (await canLaunchUrl(phoneUri)) {
        await launchUrl(phoneUri);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not launch phone app'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error making call: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  IconData _getCallTypeIcon(CallType? callType) {
    switch (callType) {
      case CallType.incoming:
        return Icons.call_received;
      case CallType.outgoing:
        return Icons.call_made;
      case CallType.missed:
        return Icons.call_received;
      case CallType.rejected:
        return Icons.call_end;
      default:
        return Icons.call;
    }
  }

  Color _getCallTypeColor(CallType? callType) {
    switch (callType) {
      case CallType.incoming:
        return Colors.green;
      case CallType.outgoing:
        return Colors.blue;
      case CallType.missed:
        return Colors.red;
      case CallType.rejected:
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  String _formatCallTime(int? timestamp) {
    if (timestamp == null) return '';
    
    final callTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final callDay = DateTime(callTime.year, callTime.month, callTime.day);
    
    if (callDay == today) {
      return '${callTime.hour.toString().padLeft(2, '0')}:${callTime.minute.toString().padLeft(2, '0')}';
    } else if (callDay == today.subtract(const Duration(days: 1))) {
      return 'Yesterday';
    } else {
      return '${callTime.day}/${callTime.month}/${callTime.year}';
    }
  }

  String _formatCallDuration(int? duration) {
    if (duration == null || duration == 0) return '';
    
    final minutes = duration ~/ 60;
    final seconds = duration % 60;
    
    if (minutes > 0) {
      return '${minutes}m ${seconds}s';
    } else {
      return '${seconds}s';
    }
  }
}