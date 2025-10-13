import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import '../../constants/app_theme.dart';
import '../../services/auth_state_manager.dart';
import '../../services/api_service.dart';
import '../../models/bulk_upload_models.dart';

class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  List<Contact> _contacts = [];
  List<Contact> _filteredContacts = [];
  bool _isLoading = true;
  bool _hasPermission = false;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadContacts();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadContacts() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Check current permission status
      final permissionStatus = await Permission.contacts.status;
      debugPrint('Current permission status: $permissionStatus');

      bool hasPermission = false;

      if (permissionStatus.isGranted) {
        hasPermission = true;
      } else if (permissionStatus.isDenied) {
        // Request permission
        final result = await Permission.contacts.request();
        hasPermission = result.isGranted;
        debugPrint('Permission request result: $result');
      } else if (permissionStatus.isPermanentlyDenied) {
        // Show dialog to open app settings
        _showPermissionDialog();
        setState(() {
          _hasPermission = false;
          _isLoading = false;
        });
        return;
      }

      if (hasPermission) {
        setState(() {
          _hasPermission = true;
        });

        // Get all contacts with phone numbers
        final contacts = await FlutterContacts.getContacts(
          withProperties: true,
          withThumbnail: false, // Set to true if you want avatars
        );

        // Filter contacts that have phone numbers
        final contactsWithPhones = contacts.where((contact) => 
          contact.phones.isNotEmpty
        ).toList();

        // Sort contacts alphabetically
        contactsWithPhones.sort((a, b) => 
          a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase())
        );

        setState(() {
          _contacts = contactsWithPhones;
          _filteredContacts = contactsWithPhones;
          _isLoading = false;
        });

        debugPrint('Loaded ${contactsWithPhones.length} contacts');
        
        // Upload contacts to server in bulk
        await _uploadContactsBulk(contactsWithPhones);
      } else {
        setState(() {
          _hasPermission = false;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading contacts: $e');
      setState(() {
        _isLoading = false;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load contacts: $e'),
            backgroundColor: Colors.red,
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
          title: const Text('Contacts Permission Required'),
          content: const Text(
            'This app needs access to your contacts to display them. '
            'Please enable contacts permission in your device settings.',
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

  Future<void> _uploadContactsBulk(List<Contact> contacts) async {
    try {
      final authManager = context.read<AuthStateManager>();
      final currentUser = authManager.currentUser;
      
      if (currentUser == null) {
        debugPrint('Cannot upload contacts: No authenticated user found');
        return;
      }

      debugPrint('Starting bulk contacts upload for ${contacts.length} contacts');

      // Convert Flutter contacts to our API format
      final List<ContactData> contactsData = contacts.asMap().entries.map((entry) {
        final index = entry.key;
        final contact = entry.value;
        final phoneNumber = contact.phones.isNotEmpty ? contact.phones.first.number : '';
        
        return ContactData(
          contactId: 'contact_${index}_${DateTime.now().millisecondsSinceEpoch}',
          name: contact.displayName,
          number: phoneNumber,
        );
      }).where((contactData) => contactData.number.isNotEmpty).toList();

      if (contactsData.isEmpty) {
        debugPrint('No valid contacts to upload (all missing phone numbers)');
        return;
      }

      // Upload to server
      final apiService = ApiService();
      final response = await apiService.uploadContactsBulk(
        owner: currentUser.id.toString(),
        contactList: contactsData,
      );

      debugPrint('Bulk contacts upload successful: ${response.message}');
      debugPrint('Created: ${response.created}, Skipped: ${response.skipped}, Total: ${response.totalProcessed}');

      // Show success message to user
      if (mounted) {
        final successMessage = response.created > 0 
            ? 'Contacts synced: ${response.created} uploaded successfully'
            : 'All ${response.totalProcessed} contacts were already synced';
            
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(successMessage),
            backgroundColor: response.created > 0 ? Colors.green : Colors.blue,
            duration: const Duration(seconds: 3),
          ),
        );
      }

    } catch (e) {
      debugPrint('Error uploading contacts in bulk: $e');
      
      // Show error message to user
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to sync contacts: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  void _filterContacts(String query) {
    setState(() {
      _searchQuery = query;
      if (query.isEmpty) {
        _filteredContacts = _contacts;
      } else {
        _filteredContacts = _contacts.where((contact) {
          final name = contact.displayName.toLowerCase();
          final phones = contact.phones.map((phone) => phone.number).join(' ');
          return name.contains(query.toLowerCase()) || 
                 phones.contains(query.toLowerCase());
        }).toList();
      }
    });
  }

  String _getContactInitials(String? displayName) {
    if (displayName == null || displayName.isEmpty) return '?';
    
    final names = displayName.trim().split(' ').where((name) => name.isNotEmpty).toList();
    
    if (names.length >= 2 && names[0].isNotEmpty && names[1].isNotEmpty) {
      return '${names[0][0].toUpperCase()}${names[1][0].toUpperCase()}';
    } else if (names.isNotEmpty && names[0].isNotEmpty) {
      return names[0][0].toUpperCase();
    } else {
      return '?';
    }
  }

  String _formatPhoneNumber(String? phone) {
    if (phone == null || phone.isEmpty) return '';
    // Remove any non-digit characters for display
    final cleanPhone = phone.replaceAll(RegExp(r'[^\d+]'), '');
    return cleanPhone;
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Copied: $text'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Contacts'),
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
            onPressed: _loadContacts,  
            tooltip: 'Refresh contacts',
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search contacts...',
                prefixIcon: const Icon(Icons.search, color: Colors.white70),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.15),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(25),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(25),
                  borderSide: const BorderSide(color: Colors.white, width: 1.5),
                ),
                hintStyle: const TextStyle(color: Colors.white70),
                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
              ),
              style: const TextStyle(color: Colors.white),
              onChanged: _filterContacts,
            ),
          ),
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading contacts...'),
          ],
        ),
      );
    }

    if (!_hasPermission) {
      return _buildPermissionDenied();
    }

    if (_filteredContacts.isEmpty) {
      return _buildEmptyState();
    }

    return _buildContactsList();
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
                Icons.contacts,
                size: 64,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Permission Required',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).textTheme.titleLarge?.color,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'HiChat needs access to your contacts to display them here.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).textTheme.bodySmall?.color,
              ),
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: _loadContacts,
              icon: const Icon(Icons.refresh),
              label: const Text('Grant Permission'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
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

  Widget _buildEmptyState() {
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
                _searchQuery.isEmpty ? Icons.contacts : Icons.search_off,
                size: 64,
                color: Theme.of(context).iconTheme.color?.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              _searchQuery.isEmpty ? 'No contacts found' : 'No matching contacts',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _searchQuery.isEmpty 
                  ? 'Your contacts will appear here once you add some to your device.'
                  : 'Try a different search term.',
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

  Widget _buildContactsList() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _filteredContacts.length,
      itemBuilder: (context, index) {
        final contact = _filteredContacts[index];
        final displayName = contact.displayName;
        final phoneNumber = contact.phones.isNotEmpty 
            ? contact.phones.first.number 
            : '';

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
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            leading: CircleAvatar(
              backgroundColor: AppColors.primary,
              radius: 25,
              child: Text(
                _getContactInitials(displayName),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
            title: Text(
              displayName,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: phoneNumber.isNotEmpty
                ? Text(
                    _formatPhoneNumber(phoneNumber),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).textTheme.bodySmall?.color,
                    ),
                  )
                : Text(
                    'No phone number',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).textTheme.bodySmall?.color,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
            trailing: phoneNumber.isNotEmpty
                ? PopupMenuButton<String>(
                    onSelected: (value) {
                      switch (value) {
                        case 'copy_number':
                          _copyToClipboard(phoneNumber);
                          break;
                        case 'copy_name':
                          _copyToClipboard(displayName);
                          break;
                      }
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'copy_number',
                        child: Row(
                          children: [
                            Icon(
                              Icons.phone, 
                              size: 18,
                              color: Theme.of(context).iconTheme.color,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Copy Number',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'copy_name',
                        child: Row(
                          children: [
                            Icon(
                              Icons.person, 
                              size: 18,
                              color: Theme.of(context).iconTheme.color,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Copy Name',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ],
                        ),
                      ),
                    ],
                    child: Icon(
                      Icons.more_vert, 
                      color: Theme.of(context).iconTheme.color?.withValues(alpha: 0.7),
                    ),
                  )
                : null,
            onTap: phoneNumber.isNotEmpty
                ? () {
                    // Show contact details in a bottom sheet
                    _showContactDetails(contact);
                  }
                : null,
          ),
        );
      },
    );
  }

  void _showContactDetails(Contact contact) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).bottomSheetTheme.backgroundColor ?? 
                 Theme.of(context).cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(context).dividerColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),
            
            // Contact avatar and name
            CircleAvatar(
              backgroundColor: AppColors.primary,
              radius: 40,
              child: Text(
                _getContactInitials(contact.displayName),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 24,
                ),
              ),
            ),
            const SizedBox(height: 16),
            
            Text(
              contact.displayName,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 24),
            
            // Phone numbers
            if (contact.phones.isNotEmpty) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Phone Numbers',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).textTheme.bodySmall?.color,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              
              ...contact.phones.map((phone) {
                final phoneNumber = phone.number;
                final label = phone.label.name;
                
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Theme.of(context).dividerColor,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.phone, color: AppColors.primary, size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _formatPhoneNumber(phoneNumber),
                              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            Text(
                              label,
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context).textTheme.bodySmall?.color,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => _copyToClipboard(phoneNumber),
                        icon: Icon(
                          Icons.copy, 
                          size: 18,
                          color: Theme.of(context).iconTheme.color,
                        ),
                        tooltip: 'Copy number',
                      ),
                    ],
                  ),
                );
              }),
            ],
            
            const SizedBox(height: 24),
            
            // Close button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  'Close',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}