import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'dart:convert';
import '../../constants/app_constants.dart';
import '../../services/api_service.dart';
import '../../models/user.dart';

class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({super.key});

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _nicknameController = TextEditingController();
  final TextEditingController _dobController = TextEditingController();
  final TextEditingController _aboutController = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  
  bool _isLoading = false;
  File? _selectedImage;
  final ImagePicker _imagePicker = ImagePicker();
  
  // Services
  late ApiService _apiService;
  
  // Arguments passed from registration or OTP screen
  String? _email;
  String? _password;
  String? _phoneNumber;
  String? _userToken;
  bool _isProfileUpdate = false;

  @override
  void initState() {
    super.initState();
    _apiService = ApiService();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Get arguments passed from registration screen or OTP screen
    final arguments = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    if (arguments != null) {
      _email = arguments['email'] as String?;
      _password = arguments['password'] as String?;
      _phoneNumber = arguments['phone_number'] as String?;
      _userToken = arguments['user_token'] as String?;
      _isProfileUpdate = arguments['is_profile_update'] as bool? ?? false;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _nicknameController.dispose();
    _dobController.dispose();
    _aboutController.dispose();
    _apiService.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 80,
      );
      
      if (image != null) {
        setState(() {
          _selectedImage = File(image.path);
        });
      }
    } catch (e) {
      _showError('Failed to pick image: $e');
    }
  }

  Future<void> _selectDateOfBirth() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime(1999, 1, 1), // Default to 1 Jan 1999
      firstDate: DateTime(1900),
      lastDate: DateTime.now(), // Only allow past dates
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
              primary: Theme.of(context).colorScheme.primary,
            ),
          ),
          child: child!,
        );
      },
    );
    
    if (picked != null) {
      final formattedDate = '${picked.year.toString().padLeft(4, '0')}-'
          '${picked.month.toString().padLeft(2, '0')}-'
          '${picked.day.toString().padLeft(2, '0')}';
      setState(() {
        _dobController.text = formattedDate;
      });
    }
  }

  Future<String?> _imageToBase64(File imageFile) async {
    try {
      final bytes = await imageFile.readAsBytes();
      return base64Encode(bytes);
    } catch (e) {
      return null;
    }
  }

  Future<void> _handleContinue() async {
    final name = _nameController.text.trim();
    final nickname = _nicknameController.text.trim();
    final about = _aboutController.text.trim();
    final dob = _dobController.text.trim();

    if (!_validateInput(name, nickname, about, dob)) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      String? base64Image;
      if (_selectedImage != null) {
        base64Image = await _imageToBase64(_selectedImage!);
        if (base64Image == null) {
          _showError('Failed to process image. Please try another one.');
          return;
        }
      }

      if (_isProfileUpdate && _userToken != null) {
        // Profile update flow - user already has basic account
        await _handleProfileUpdate(name, nickname, about, dob, base64Image);
      } else {
        // Initial signup flow - create new account (from OTP screen)
        await _handleInitialSignup(name, nickname, about, dob, base64Image);
      }
    } catch (e) {
      if (mounted) {
        _showError('Signup failed: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _handleProfileUpdate(String name, String nickname, String about, String dob, String? base64Image) async {
    // Profile update flow - update existing user profile
    final profileUpdateRequest = ProfileUpdateRequest(
      username: nickname,
      name: name,
      about: about,
      dateOfBirth: dob,
      image: base64Image,
      availability: 'online',
    );

    // Log profile update attempt
    print('=== PROFILE UPDATE ATTEMPT ===');
    print('User Token: ${_userToken?.substring(0, 20)}...');
    print('Username: $nickname');
    print('Name: $name');
    print('Has Profile Image: ${base64Image != null}');
    print('==============================');

    // Make API call to update user profile
    final updatedUser = await _apiService.updateUserProfile(_userToken!, profileUpdateRequest);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Welcome ${updatedUser.username}! Profile completed successfully.'),
          backgroundColor: Theme.of(context).colorScheme.primary,
          duration: const Duration(seconds: 2),
        ),
      );

      // Navigate directly to chat screen since user is now fully registered
      Navigator.pushNamedAndRemoveUntil(
        context,
        AppConstants.chatListRoute,
        (route) => false,
      );
    }
  }

  Future<void> _handleInitialSignup(String name, String nickname, String about, String dob, String? base64Image) async {
    // Initial signup flow - create new account (from OTP screen for new users)
    final signupRequest = SignupRequest(
      email: _email,
      phoneNumber: _phoneNumber,
      username: nickname,
      password: _password!,
      name: name,
      about: about,
      dateOfBirth: dob,
      profileImage: base64Image,
    );

    // Log signup attempt
    print('=== INITIAL SIGNUP ATTEMPT ===');
    print('Phone Number: $_phoneNumber');
    print('Email: $_email');
    print('Username: $nickname');
    print('Name: $name');
    print('Has Profile Image: ${base64Image != null}');
    print('==============================');

    // Make API call to create user
    final signupResponse = await _apiService.signupUser(signupRequest);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Welcome ${signupResponse.user.username}! Account created successfully.'),
          backgroundColor: Theme.of(context).colorScheme.primary,
          duration: const Duration(seconds: 2),
        ),
      );

      // Navigate directly to chat screen since user is now registered and authenticated
      Navigator.pushNamedAndRemoveUntil(
        context,
        AppConstants.chatListRoute,
        (route) => false,
      );
    }
  }

  bool _validateInput(String name, String nickname, String about, String dob) {
    if (_email == null && _phoneNumber == null) {
      _showError('Something went wrong. Please restart the signup process.');
      return false;
    }

    if (_password == null) {
      _showError('Something went wrong. Please restart the signup process.');
      return false;
    }

    if (name.isEmpty) {
      _showFieldError(_nameController, 'Full name is required');
      return false;
    }

    if (nickname.isEmpty) {
      _showFieldError(_nicknameController, 'Username is required');
      return false;
    }

    if (about.isEmpty) {
      _showFieldError(_aboutController, 'Tell us about yourself');
      return false;
    }

    if (dob.isEmpty) {
      _showFieldError(_dobController, 'Date of birth is required');
      return false;
    }

    return true;
  }

  void _showFieldError(TextEditingController controller, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.error,
        duration: const Duration(seconds: 3),
      ),
    );
    FocusScope.of(context).requestFocus(FocusNode());
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.error,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: _buildBody(theme),
    );
  }

  Widget _buildBody(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Form(
        key: _formKey,
        child: Column(
          children: [
            const SizedBox(height: 40), // Status bar padding
            _buildTitle(theme),
            const SizedBox(height: 32),
            _buildProfileImageSection(theme),
            const SizedBox(height: 32),
            _buildNameField(theme),
            const SizedBox(height: 12),
            _buildNicknameField(theme),
            const SizedBox(height: 12),
            _buildDobField(theme),
            const SizedBox(height: 12),
            _buildAboutField(theme),
            const SizedBox(height: 64),
            _buildContinueButton(theme),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildTitle(ThemeData theme) {
    return Column(
      children: [
        Text(
          'Fill Your Profile',
          textAlign: TextAlign.center,
          style: GoogleFonts.lato(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Profile image is optional',
          textAlign: TextAlign.center,
          style: GoogleFonts.poppins(
            fontSize: 12,
            color: theme.colorScheme.onSurface.withOpacity(0.6),
          ),
        ),
      ],
    );
  }

  Widget _buildProfileImageSection(ThemeData theme) {
    return SizedBox(
      width: 140,
      height: 140,
      child: Stack(
        children: [
          // Profile image
          Container(
            width: 140,
            height: 140,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: theme.colorScheme.surface,
              border: Border.all(
                color: theme.dividerColor,
                width: 2,
              ),
            ),
            child: ClipOval(
              child: _selectedImage != null
                  ? Image.file(
                      _selectedImage!,
                      fit: BoxFit.cover,
                      width: 140,
                      height: 140,
                    )
                  : Icon(
                      Icons.person,
                      size: 60,
                      color: theme.colorScheme.onSurface.withOpacity(0.5),
                    ),
            ),
          ),
          // Edit button
          Positioned(
            bottom: 4,
            right: 4,
            child: GestureDetector(
              onTap: _pickImage,
              child: Container(
                width: 35,
                height: 35,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: theme.colorScheme.primary,
                ),
                child: Icon(
                  Icons.edit,
                  size: 20,
                  color: theme.colorScheme.onPrimary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNameField(ThemeData theme) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: TextFormField(
        controller: _nameController,
        decoration: InputDecoration(
          hintText: 'Name',
          hintStyle: TextStyle(
            color: const Color(0xA8A8A8A8),
            fontSize: 16,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: theme.dividerColor, width: 1),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: theme.dividerColor, width: 1),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: theme.colorScheme.primary, width: 2),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: theme.colorScheme.error, width: 1),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: theme.colorScheme.error, width: 2),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          filled: true,
          fillColor: theme.brightness == Brightness.dark 
            ? theme.colorScheme.surface.withOpacity(0.8)
            : theme.colorScheme.surface,
        ),
        style: TextStyle(
          color: theme.colorScheme.onSurface,
          fontSize: 16,
        ),
        textInputAction: TextInputAction.next,
        onEditingComplete: () => FocusScope.of(context).nextFocus(),
      ),
    );
  }

  Widget _buildNicknameField(ThemeData theme) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: TextFormField(
        controller: _nicknameController,
        decoration: InputDecoration(
          hintText: 'Nickname',
          hintStyle: TextStyle(
            color: const Color(0xA8A8A8A8),
            fontSize: 16,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: theme.dividerColor, width: 1),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: theme.dividerColor, width: 1),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: theme.colorScheme.primary, width: 2),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: theme.colorScheme.error, width: 1),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: theme.colorScheme.error, width: 2),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          filled: true,
          fillColor: theme.brightness == Brightness.dark 
            ? theme.colorScheme.surface.withOpacity(0.8)
            : theme.colorScheme.surface,
        ),
        style: TextStyle(
          color: theme.colorScheme.onSurface,
          fontSize: 16,
        ),
        textInputAction: TextInputAction.next,
        onEditingComplete: () => FocusScope.of(context).nextFocus(),
      ),
    );
  }

  Widget _buildDobField(ThemeData theme) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: TextFormField(
        controller: _dobController,
        decoration: InputDecoration(
          hintText: 'Date Of Birth',
          hintStyle: TextStyle(
            color: const Color(0xA8A8A8A8),
            fontSize: 16,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: theme.dividerColor, width: 1),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: theme.dividerColor, width: 1),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: theme.colorScheme.primary, width: 2),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: theme.colorScheme.error, width: 1),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: theme.colorScheme.error, width: 2),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          filled: true,
          fillColor: theme.brightness == Brightness.dark 
            ? theme.colorScheme.surface.withOpacity(0.8)
            : theme.colorScheme.surface,
        ),
        style: TextStyle(
          color: theme.colorScheme.onSurface,
          fontSize: 16,
        ),
        readOnly: true,
        onTap: _selectDateOfBirth,
      ),
    );
  }

  Widget _buildAboutField(ThemeData theme) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: TextFormField(
        controller: _aboutController,
        decoration: InputDecoration(
          hintText: 'About Us',
          hintStyle: TextStyle(
            color: const Color(0xA8A8A8A8),
            fontSize: 16,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: theme.dividerColor, width: 1),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: theme.dividerColor, width: 1),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: theme.colorScheme.primary, width: 2),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: theme.colorScheme.error, width: 1),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: theme.colorScheme.error, width: 2),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          filled: true,
          fillColor: theme.brightness == Brightness.dark 
            ? theme.colorScheme.surface.withOpacity(0.8)
            : theme.colorScheme.surface,
        ),
        style: TextStyle(
          color: theme.colorScheme.onSurface,
          fontSize: 16,
        ),
        textInputAction: TextInputAction.done,
        onEditingComplete: () => _handleContinue(),
      ),
    );
  }

  Widget _buildContinueButton(ThemeData theme) {
    return SizedBox(
      width: 262,
      height: 52,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _handleContinue,
        style: ElevatedButton.styleFrom(
          backgroundColor: theme.colorScheme.primary,
          foregroundColor: theme.colorScheme.onPrimary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(26),
          ),
          elevation: 0,
          disabledBackgroundColor: theme.colorScheme.primary.withOpacity(0.6),
        ),
        child: _isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : Text(
                'Continue',
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
      ),
    );
  }
}