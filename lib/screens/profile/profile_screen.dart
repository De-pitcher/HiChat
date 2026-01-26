import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';

import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../models/user.dart';
import '../../services/auth_state_manager.dart';
import '../../services/api_service.dart';
import '../../services/api_exceptions.dart';
import '../../widgets/custom_text_field.dart';
import '../../widgets/loading_overlay.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _aboutController = TextEditingController();
  
  final ApiService _apiService = ApiService();
  final ImagePicker _imagePicker = ImagePicker();
  
  bool _isLoading = false;
  bool _isEditing = false;
  File? _selectedImage;
  String? _base64Image;
  String? _errorMessage;
  String? _successMessage;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _usernameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _aboutController.dispose();
    super.dispose();
  }

  void _loadUserData() {
    final authManager = Provider.of<AuthStateManager>(context, listen: false);
    final user = authManager.currentUser;
    
    if (user != null) {
      _nameController.text = user.username; // Use username as display name
      _usernameController.text = user.username;
      _emailController.text = user.email ?? '';
      _phoneController.text = user.phoneNumber ?? '';
      _aboutController.text = user.about ?? '';
    }
  }

  Future<void> _selectImage() async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 80,
      );
      
      if (image != null) {
        final File imageFile = File(image.path);
        final List<int> imageBytes = await imageFile.readAsBytes();
        final String base64String = base64Encode(imageBytes);
        
        setState(() {
          _selectedImage = imageFile;
          _base64Image = 'data:image/jpeg;base64,$base64String';
          _errorMessage = null;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to select image: $e';
      });
    }
  }

  Future<void> _updateProfile() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final authManager = Provider.of<AuthStateManager>(context, listen: false);
    final currentUser = authManager.currentUser;
    
    if (currentUser?.token == null) {
      setState(() {
        _errorMessage = 'Authentication token not found. Please login again.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      final request = ProfileUpdateRequest(
        email: currentUser!.email, // Include email for upsert lookup
        username: _usernameController.text.trim().isEmpty ? null : _usernameController.text.trim(),
        phoneNumber: _phoneController.text.trim().isEmpty ? null : _phoneController.text.trim(),
        about: _aboutController.text.trim().isEmpty ? null : _aboutController.text.trim(),
        image: _base64Image,
      );

      // Update profile using the flexible upsert endpoint
      final updatedUser = await _apiService.updateUserProfileUpsert(
        currentUser.token!, 
        request,
      );
      
      // Update the auth state with the new user data
      await authManager.handleSuccessfulLogin(updatedUser);
      
      setState(() {
        _isLoading = false;
        _isEditing = false;
        _selectedImage = null;
        _base64Image = null;
        _successMessage = 'Profile updated successfully!';
      });
      
      // Clear success message after 3 seconds
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) {
          setState(() {
            _successMessage = null;
          });
        }
      });
      
    } on ValidationException catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = e.message;
      });
    } on AuthenticationException {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Authentication failed. Please login again.';
      });
    } on NetworkException catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = e.message;
      });
    } on ServerException {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Server error. Please try again later.';
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'An unexpected error occurred: $e';
      });
    }
  }



  void _toggleEdit() {
    setState(() {
      _isEditing = !_isEditing;
      _errorMessage = null;
      _successMessage = null;
      _selectedImage = null;
      _base64Image = null;
    });
    
    if (!_isEditing) {
      // Reset form data when canceling edit
      _loadUserData();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          'Profile',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.onSurface,
          ),
        ),
        backgroundColor: theme.scaffoldBackgroundColor,
        foregroundColor: theme.colorScheme.onSurface,
        elevation: 0,
        centerTitle: true,
        actions: [
          if (_isEditing)
            TextButton(
              onPressed: _isLoading ? null : _toggleEdit,
              child: Text(
                'Cancel',
                style: TextStyle(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            )
          else
            IconButton(
              onPressed: _toggleEdit,
              icon: Icon(
                Icons.edit_outlined,
                color: theme.colorScheme.primary,
              ),
            ),
        ],
      ),
      body: LoadingOverlay(
        isLoading: _isLoading,
        child: SingleChildScrollView(
          child: Column(
            children: [
              // Profile Header Section
              _buildProfileHeader(theme),
              
              // Messages Section
              _buildMessages(theme),
              
              // Form Section
              Container(
                margin: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Personal Information',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 20),
                      
                      // Form Fields
                      _buildFormFields(),
                      
                      const SizedBox(height: 32),
                      
                      // Update Button
                      if (_isEditing) _buildUpdateButton(theme),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProfileHeader(ThemeData theme) {
    final authManager = Provider.of<AuthStateManager>(context);  
    final user = authManager.currentUser;
    
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      child: Column(
        children: [
          // Profile Image
          Stack(
            children: [
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: theme.colorScheme.primary.withValues(alpha: 0.2),
                    width: 3,
                  ),
                ),
                child: CircleAvatar(
                  radius: 60,
                  backgroundColor: theme.colorScheme.surface,
                  backgroundImage: _selectedImage != null
                      ? FileImage(_selectedImage!)
                      : (user?.profileImageUrl?.isNotEmpty == true
                          ? NetworkImage(user!.profileImageUrl!)
                          : null) as ImageProvider?,
                  child: (_selectedImage == null && user?.profileImageUrl?.isEmpty != false)
                      ? Icon(
                          Icons.person_outline,
                          size: 60,
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                        )
                      : null,
                ),
              ),
              if (_isEditing)
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: theme.scaffoldBackgroundColor,
                        width: 3,
                      ),
                    ),
                    child: IconButton(
                      icon: const Icon(
                        Icons.camera_alt_outlined,
                        size: 20,
                        color: Colors.white,
                      ),
                      onPressed: _selectImage,
                    ),
                  ),
                ),
            ],
          ),
          
          const SizedBox(height: 16),
          
          // User Name
          Text(
            user?.username ?? 'User',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurface,
            ),
          ),
          
          const SizedBox(height: 4),
          
          // User Email
          Text(
            user?.email ?? '',
            style: TextStyle(
              fontSize: 16,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
          
          if (_isEditing && _selectedImage != null) ...[
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: () {
                setState(() {
                  _selectedImage = null;
                  _base64Image = null;
                });
              },
              icon: Icon(
                Icons.delete_outline,
                size: 18,
                color: theme.colorScheme.error,
              ),
              label: Text(
                'Remove Image',
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMessages(ThemeData theme) {
    if (_errorMessage == null && _successMessage == null) {
      return const SizedBox.shrink();
    }
    
    return Container(
      margin: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Column(
        children: [
          // Error Message
          if (_errorMessage != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: theme.colorScheme.error.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.error_outline,
                    color: theme.colorScheme.error,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style: TextStyle(
                        color: theme.colorScheme.error,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          
          // Success Message
          if (_successMessage != null) ...[
            if (_errorMessage != null) const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.green.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.check_circle_outline,
                    color: Colors.green.shade600,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _successMessage!,
                      style: TextStyle(
                        color: Colors.green.shade700,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildUpdateButton(ThemeData theme) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _updateProfile,
        style: ElevatedButton.styleFrom(
          backgroundColor: theme.colorScheme.primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          elevation: 0,
        ),
        child: _isLoading
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : const Text(
                'Update Profile',
                style: TextStyle(
                  fontSize: 16, 
                  fontWeight: FontWeight.w600,
                ),
              ),
      ),
    );
  }



  Widget _buildFormFields() {
    return Column(
      children: [
        CustomTextField(
          label: 'Username',
          controller: _usernameController,
          enabled: _isEditing,
          validator: (value) {
            if (value?.trim().isEmpty ?? true) {
              return 'Username is required';
            }
            if (value!.length < 3) {
              return 'Username must be at least 3 characters';
            }
            return null;
          },
        ),
        
        const SizedBox(height: 20),
        
        CustomTextField(
          label: 'Email',
          controller: _emailController,
          enabled: false, // Email usually shouldn't be editable
          keyboardType: TextInputType.emailAddress,
        ),
        
        const SizedBox(height: 20),
        
        CustomTextField(
          label: 'Phone Number',
          controller: _phoneController,
          enabled: _isEditing,
          keyboardType: TextInputType.phone,
          hintText: 'Enter your phone number',
        ),
        
        const SizedBox(height: 20),
        
        CustomTextField(
          label: 'About',
          controller: _aboutController,
          enabled: _isEditing,
          maxLines: 3,
          maxLength: 150,
          hintText: 'Tell us about yourself...',
        ),
      ],
    );
  }
}