import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:call_log/call_log.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../constants/app_theme.dart';

class CallsScreen extends StatefulWidget {
  const CallsScreen({super.key});

  @override
  State<CallsScreen> createState() => _CallsScreenState();
}

class _CallsScreenState extends State<CallsScreen>
    with TickerProviderStateMixin {
  late TabController _tabController;
  List<CallLogEntry> _callLogs = [];
  bool _isLoading = true;
  bool _hasPermission = false;
  bool _hasMoreLogs = true;
  bool _isLoadingMore = false;
  int _currentOffset = 0;
  static const int _pageSize =
      30; // Reduced from 50 to 30 for better performance
  String _dialpadNumber = '';
  final TextEditingController _dialpadController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  // Cache for efficient filtering and sorting
  List<CallLogEntry>? _allCallLogsCache;

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
              _scrollController.position.maxScrollExtent * 0.9 &&
          !_isLoadingMore &&
          _hasMoreLogs) {
        _loadMoreCallLogs();
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _dialpadController.dispose();
    _scrollController.dispose();
    // Clear cache to free memory
    _allCallLogsCache = null;
    super.dispose();
  }

  Future<void> _loadCallLogs() async {
    if (_isLoading) return;

    setState(() {
      _isLoading = true;
      _currentOffset = 0;
      _callLogs.clear();
      _hasMoreLogs = true;
      // Clear cache for fresh load
      _allCallLogsCache = null;
    });

    await _requestPermissionsAndLoadLogs();
  }

  Future<void> _loadMoreCallLogs() async {
    if (_isLoadingMore || !_hasMoreLogs || _isLoading) return;

    setState(() {
      _isLoadingMore = true;
    });

    await _loadCallLogsPage();
  }

  Future<void> _requestPermissionsAndLoadLogs() async {
    try {
      debugPrint('🔄 Requesting permissions for call logs...');

      final PermissionStatus phoneStatus = await Permission.phone.request();
      final PermissionStatus smsStatus = await Permission.sms.request();

      debugPrint('Phone permission: $phoneStatus');
      debugPrint('SMS permission: $smsStatus');

      if (!phoneStatus.isGranted) {
        _showPermissionDialog();
        setState(() {
          _hasPermission = false;
          _isLoading = false;
          _isLoadingMore = false;
        });
        return;
      }

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
      debugPrint(
        '📞 Loading call logs page - Offset: $_currentOffset, PageSize: $_pageSize',
      );

      // Use time-based filtering for efficient loading
      final now = DateTime.now();
      final threeMonthsAgo = now.subtract(
        const Duration(days: 90),
      ); // Reduced from 1 year to 3 months

      Iterable<CallLogEntry> entries;

      if (_allCallLogsCache == null) {
        // Initial load - fetch all logs but with time limit
        entries = await CallLog.query(
          dateFrom: threeMonthsAgo.millisecondsSinceEpoch,
          dateTo: now.millisecondsSinceEpoch,
        );

        // Cache the results for pagination
        _allCallLogsCache = entries.toList();

        // Sort by timestamp (most recent first)
        _allCallLogsCache!.sort(
          (a, b) => (b.timestamp ?? 0).compareTo(a.timestamp ?? 0),
        );

        debugPrint('💾 Cached ${_allCallLogsCache!.length} call log entries');
      }

      // Get paginated data from cache
      final endIndex = _currentOffset + _pageSize;
      final hasMore = endIndex < _allCallLogsCache!.length;
      final pageData = _allCallLogsCache!.sublist(
        _currentOffset,
        endIndex.clamp(0, _allCallLogsCache!.length),
      );

      // Add small delay to prevent UI jank
      await Future.delayed(const Duration(milliseconds: 100));

      if (mounted) {
        setState(() {
          if (_currentOffset == 0) {
            _callLogs = pageData;
          } else {
            _callLogs.addAll(pageData);
          }

          _hasPermission = true;
          _isLoading = false;
          _isLoadingMore = false;
          _hasMoreLogs = hasMore;
          _currentOffset = endIndex;
        });
      }

      debugPrint(
        '✅ Loaded ${pageData.length} call log entries (Total: ${_callLogs.length}, HasMore: $hasMore)',
      );
    } catch (e) {
      debugPrint('❌ Error loading call logs page: $e');
      if (mounted) {
        _showCallLogPermissionError();
        setState(() {
          _hasPermission = false;
          _isLoading = false;
          _isLoadingMore = false;
        });
      }
    }
  }

  // Optimized list item builder to prevent unnecessary rebuilds
  Widget _buildCallLogItem(CallLogEntry callLog, int index) {
    final displayName = callLog.name ?? callLog.number ?? 'Unknown';
    final phoneNumber = callLog.number ?? '';

    return Container(
      key: ValueKey('call_log_${callLog.timestamp}_${callLog.number}'),
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
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: AppColors.primary,
          radius: 25,
          child: Text(
            _getContactInitials(callLog.name),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ),
        title: Text(
          displayName,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
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
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
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
          icon: Icon(Icons.call, color: AppColors.primary),
          tooltip: 'Call back',
        ),
        onTap: () => _makeCall(phoneNumber),
      ),
    );
  }

  Widget _buildCallLogsList() {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _callLogs.length + (_hasMoreLogs ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= _callLogs.length) {
          return _buildLoadingIndicator();
        }
        return _buildCallLogItem(_callLogs[index], index);
      },
    );
  }

  void _showPermissionDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Phone Permission Required'),
          content: const Text(
            'This app needs access to your phone and call logs to display call history.\n\n'
            'Please enable phone permissions in Settings.',
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
            'Unable to access call logs. Please enable phone permissions in Settings.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _loadCallLogs();
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

  Widget _buildLoadingIndicator() {
    if (!_isLoadingMore) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
      alignment: Alignment.center,
      child: Row(
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
            'Loading more...',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).textTheme.bodySmall?.color,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Calls'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadCallLogs,
            tooltip: 'Refresh call logs',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(text: 'Recent', icon: Icon(Icons.history)),
            Tab(text: 'Dialpad', icon: Icon(Icons.dialpad)),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildCallLogsTab(),
          _buildDialpadTab(), // Keep your existing dialpad implementation
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

  void _onDialpadTap(String digit) {
    setState(() {
      _dialpadNumber += digit;
      _dialpadController.text = _dialpadNumber;
      _dialpadController.selection = TextSelection.fromPosition(
        TextPosition(offset: _dialpadNumber.length),
      );
    });

    // Haptic feedback
    HapticFeedback.lightImpact();
  }

  void _onDialpadDelete() {
    if (_dialpadNumber.isNotEmpty) {
      setState(() {
        _dialpadNumber = _dialpadNumber.substring(0, _dialpadNumber.length - 1);
        _dialpadController.text = _dialpadNumber;
        _dialpadController.selection = TextSelection.fromPosition(
          TextPosition(offset: _dialpadNumber.length),
        );
      });
      HapticFeedback.lightImpact();
    }
  }

  void _onDialpadClear() {
    setState(() {
      _dialpadNumber = '';
      _dialpadController.clear();
    });
    HapticFeedback.mediumImpact();
  }

  Future<void> _makeCall(String phoneNumber) async {
    try {
      final cleanNumber = phoneNumber.replaceAll(RegExp(r'[^\d+]'), '');
      final uri = Uri(scheme: 'tel', path: cleanNumber);

      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Unable to make phone call'),
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
            content: Text('Failed to make call: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
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

  String _formatCallTime(int? timestamp) {
    if (timestamp == null) return '';

    final DateTime callTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final DateTime now = DateTime.now();
    final Duration difference = now.difference(callTime);

    if (difference.inDays > 0) {
      return '${difference.inDays}d ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m ago';
    } else {
      return 'Just now';
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

  String _getContactInitials(String? name) {
    if (name == null || name.isEmpty) return '?';

    final names = name
        .trim()
        .split(' ')
        .where((name) => name.isNotEmpty)
        .toList();

    if (names.length >= 2 && names[0].isNotEmpty && names[1].isNotEmpty) {
      return '${names[0][0].toUpperCase()}${names[1][0].toUpperCase()}';
    } else if (names.isNotEmpty && names[0].isNotEmpty) {
      return names[0][0].toUpperCase();
    } else {
      return '?';
    }
  }

  Widget _buildPermissionDenied() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.phone_disabled,
                size: 64,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Permission Required',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'HiChat needs access to your phone and call logs to display call history.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).textTheme.bodySmall?.color,
              ),
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: _loadCallLogs,
              icon: const Icon(Icons.refresh),
              label: const Text('Grant Permission'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
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
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.call,
                size: 64,
                color: Theme.of(
                  context,
                ).iconTheme.color?.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'No Call History',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Your call history will appear here once you make or receive calls.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).textTheme.bodySmall?.color,
              ),
            ),
          ],
        ),
      ),
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
              border: Border.all(color: Theme.of(context).dividerColor),
            ),
            child: TextField(
              controller: _dialpadController,
              style: Theme.of(
                context,
              ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w500),
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
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              shrinkWrap: true,
              children: [
                // Row 1
                _buildDialpadButton('1', ''),
                _buildDialpadButton('2', 'ABC'),
                _buildDialpadButton('3', 'DEF'),

                // Row 2
                _buildDialpadButton('4', 'GHI'),
                _buildDialpadButton('5', 'JKL'),
                _buildDialpadButton('6', 'MNO'),

                // Row 3
                _buildDialpadButton('7', 'PQRS'),
                _buildDialpadButton('8', 'TUV'),
                _buildDialpadButton('9', 'WXYZ'),

                // Row 4
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
              // Delete button
              FloatingActionButton(
                onPressed: _dialpadNumber.isEmpty ? null : _onDialpadDelete,
                backgroundColor: _dialpadNumber.isEmpty
                    ? Colors.grey[300]
                    : Colors.red[100],
                child: Icon(
                  Icons.backspace,
                  color: _dialpadNumber.isEmpty ? Colors.grey : Colors.red,
                ),
              ),

              // Call button
              FloatingActionButton.large(
                onPressed: _dialpadNumber.isEmpty
                    ? null
                    : () => _makeCall(_dialpadNumber),
                backgroundColor: _dialpadNumber.isEmpty
                    ? Colors.grey[300]
                    : Colors.green,
                child: Icon(
                  Icons.call,
                  color: _dialpadNumber.isEmpty ? Colors.grey : Colors.white,
                  size: 32,
                ),
              ),

              // Clear button
              FloatingActionButton(
                onPressed: _dialpadNumber.isEmpty ? null : _onDialpadClear,
                backgroundColor: _dialpadNumber.isEmpty
                    ? Colors.grey[300]
                    : Colors.orange[100],
                child: Icon(
                  Icons.clear,
                  color: _dialpadNumber.isEmpty ? Colors.grey : Colors.orange,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDialpadButton(String digit, String letters) {
    return Material(
      color: Theme.of(context).cardColor,
      borderRadius: BorderRadius.circular(50),
      elevation: 2,
      child: InkWell(
        onTap: () => _onDialpadTap(digit),
        borderRadius: BorderRadius.circular(50),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(50),
            border: Border.all(color: Theme.of(context).dividerColor, width: 1),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                digit,
                style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (letters.isNotEmpty)
                Text(
                  letters,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).textTheme.bodySmall?.color,
                    fontSize: 10,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
