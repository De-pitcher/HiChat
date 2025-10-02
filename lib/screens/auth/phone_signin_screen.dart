import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:country_code_picker/country_code_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../constants/app_constants.dart';
import '../../services/api_service.dart';
import '../../services/firebase_phone_auth_service.dart';

class PhoneSignInScreen extends StatefulWidget {
  const PhoneSignInScreen({super.key});

  @override
  State<PhoneSignInScreen> createState() => _PhoneSignInScreenState();
}

class _PhoneSignInScreenState extends State<PhoneSignInScreen> {
  final TextEditingController _phoneController = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  
  CountryCode _selectedCountry = CountryCode.fromCountryCode('US');
  bool _rememberMe = false;
  bool _isLoading = false;
  
  // Services
  late ApiService _apiService;
  late SharedPreferences _sharedPreferences;
  final FirebasePhoneAuthService _firebasePhoneAuth = FirebasePhoneAuthService();

  @override
  void initState() {
    super.initState();
    _apiService = ApiService();
    _initializeSharedPreferences();
  }

  Future<void> _initializeSharedPreferences() async {
    _sharedPreferences = await SharedPreferences.getInstance();
    _loadRememberedPhone();
  }

  void _loadRememberedPhone() {
    final savedPhone = _sharedPreferences.getString('remembered_phone');
    if (savedPhone != null && savedPhone.isNotEmpty) {
      // Parse the full number to extract country code and phone number
      final fullNumber = savedPhone.startsWith('+') ? savedPhone : '+$savedPhone';
      
      // Try to parse country code from the full number
      final commonCountries = [
        CountryCode(name: 'United States', code: 'US', dialCode: '+1'),
        CountryCode(name: 'United Kingdom', code: 'GB', dialCode: '+44'),
        CountryCode(name: 'Nigeria', code: 'NG', dialCode: '+234'),
        CountryCode(name: 'Canada', code: 'CA', dialCode: '+1'),
        CountryCode(name: 'Australia', code: 'AU', dialCode: '+61'),
      ];
      
      for (final country in commonCountries) {
        if (fullNumber.startsWith(country.dialCode!)) {
          setState(() {
            _selectedCountry = country;
            _phoneController.text = fullNumber.substring(country.dialCode!.length);
            _rememberMe = true;
          });
          break;
        }
      }
    }
  }

  void _saveRememberedPhone() {
    if (_rememberMe) {
      final fullNumber = '${_selectedCountry.dialCode}${_phoneController.text}';
      _sharedPreferences.setString('remembered_phone', fullNumber);
    } else {
      _sharedPreferences.remove('remembered_phone');
    }
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _apiService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: _buildAppBar(theme),
      body: _buildBody(theme),
    );
  }

  PreferredSizeWidget _buildAppBar(ThemeData theme) {
    return AppBar(
      backgroundColor: theme.scaffoldBackgroundColor,
      elevation: 0,
      leading: IconButton(
        icon: Icon(Icons.arrow_back, color: theme.colorScheme.onSurface),
        onPressed: () => Navigator.pop(context),
      ),
      systemOverlayStyle: theme.brightness == Brightness.dark 
        ? SystemUiOverlayStyle.light 
        : SystemUiOverlayStyle.dark,
    );
  }

  Widget _buildBody(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Form(
        key: _formKey,
        child: Column(
          children: [
            _buildLogo(theme),
            const SizedBox(height: 48),
            _buildTitle(theme),
            const SizedBox(height: 28),
            _buildPhoneInputSection(),
            const SizedBox(height: 20),
            _buildRememberMeSection(),
            const SizedBox(height: 81),
            _buildSignInButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildLogo(ThemeData theme) {
    return Container(
      margin: const EdgeInsets.only(top: 24),
      child: Image.asset(
        'assets/images/app_logo.png',
        width: 133,
        height: 115,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) {
          // Fallback logo if image not found
          return Container(
            width: 133,
            height: 115,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.phone_android,
              size: 60,
              color: theme.colorScheme.primary,
            ),
          );
        },
      ),
    );
  }

  Widget _buildTitle(ThemeData theme) {
    return Text(
      'Enter Phone Number to continue',
      textAlign: TextAlign.center,
      style: GoogleFonts.lato(
        fontSize: 28,
        fontWeight: FontWeight.bold,
        color: theme.colorScheme.primary,
      ),
    );
  }

  Widget _buildPhoneInputSection() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: TextFormField(
        controller: _phoneController,
        decoration: InputDecoration(
          hintText: 'Enter phone number',
          hintStyle: TextStyle(
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
            fontSize: 16,
          ),
          prefixIcon: LayoutBuilder(
            builder: (context, constraints) {
              // Calculate 40% of the field width for country picker (4:6 ratio)
              final countryPickerWidth = constraints.maxWidth * 0.4;
              
              return Container(
                width: countryPickerWidth,
                padding: EdgeInsets.zero,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Expanded(
                      child: CountryCodePicker(
                        onChanged: (countryCode) {
                          setState(() {
                            _selectedCountry = countryCode;
                          });
                        },
                        initialSelection: _selectedCountry.code,
                        favorite: const ['+1', 'US', '+44', 'GB', '+234', 'NG'],
                        showCountryOnly: false,
                        showOnlyCountryWhenClosed: false,
                        alignLeft: false,
                        textStyle: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                          fontSize: 14, // Slightly smaller text
                        ),
                        dialogTextStyle: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                        searchStyle: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                        dialogBackgroundColor: Theme.of(context).colorScheme.surface,
                        barrierColor: Colors.black.withValues(alpha: 0.5),
                        boxDecoration: const BoxDecoration(
                          color: Colors.transparent,
                        ),
                        padding: EdgeInsets.zero,
                        flagWidth: 18, // Smaller flag
                        showDropDownButton: true,
                      ),
                    ),
                    Container(
                      height: 24,
                      width: 1,
                      color: Theme.of(context).dividerColor,
                      margin: const EdgeInsets.only(left: 4, right: 8),
                    ),
                  ],
                ),
              );
            },
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: Theme.of(context).dividerColor, width: 1),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: Theme.of(context).dividerColor, width: 1),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: Theme.of(context).colorScheme.primary, width: 2),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: Theme.of(context).colorScheme.error, width: 1),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: Theme.of(context).colorScheme.error, width: 2),
          ),
          contentPadding: const EdgeInsets.only(left: 8, right: 16, top: 16, bottom: 16),
          filled: true,
          fillColor: Theme.of(context).brightness == Brightness.dark 
            ? Theme.of(context).colorScheme.surface.withValues(alpha: 0.8)
            : Theme.of(context).colorScheme.surface,
        ),
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurface,
          fontSize: 16,
        ),
        keyboardType: TextInputType.phone,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(15), // Reasonable phone number length
        ],
        validator: _validatePhoneNumber,
        textInputAction: TextInputAction.done,
      ),
    );
  }

  String? _validatePhoneNumber(String? value) {
    if (value == null || value.isEmpty) {
      return 'Phone number is required';
    }
    
    // Basic phone number validation
    if (value.length < 7) {
      return 'Phone number is too short';
    }
    
    if (value.length > 15) {
      return 'Phone number is too long';
    }
    
    return null;
  }

  Widget _buildRememberMeSection() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          GestureDetector(
            onTap: () {
              setState(() {
                _rememberMe = !_rememberMe;
              });
            },
            child: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: _rememberMe ? Theme.of(context).colorScheme.primary : Colors.transparent,
                border: Border.all(
                  color: Theme.of(context).colorScheme.primary,
                  width: 2,
                ),
                borderRadius: BorderRadius.circular(4),
              ),
              child: _rememberMe
                  ? const Icon(
                      Icons.check,
                      size: 16,
                      color: Colors.white,
                    )
                  : null,
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () {
              setState(() {
                _rememberMe = !_rememberMe;
              });
            },
            child: Text(
              'Remember Me',
              style: GoogleFonts.poppins(
                fontSize: 12.82,
                color: Theme.of(context).colorScheme.onSurface,
                fontWeight: FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSignInButton() {
    return SizedBox(
      width: 262,
      height: 52, // Matching the enhanced height from login screen
      child: ElevatedButton(
        onPressed: _isLoading ? null : _handleSignIn,
        style: ElevatedButton.styleFrom(
          backgroundColor: Theme.of(context).colorScheme.primary,
          foregroundColor: Theme.of(context).colorScheme.onPrimary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(26),
          ),
          elevation: 0,
          disabledBackgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.6),
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
                'Sign In',
                style: GoogleFonts.poppins(
                  fontSize: 16, // Matching enhanced font size
                  fontWeight: FontWeight.w600,
                ),
              ),
      ),
    );
  }

  Future<void> _handleSignIn() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final phoneNumber = _phoneController.text.trim();
    if (phoneNumber.isEmpty) {
      _showError('Please enter a phone number');
      return;
    }

    final fullPhoneNumber = '${_selectedCountry.dialCode}$phoneNumber';
    
    setState(() {
      _isLoading = true;
    });

    try {
      // Save remember me setting
      _saveRememberedPhone();
      
      // Send OTP using Firebase Phone Auth
      final otpSent = await _firebasePhoneAuth.sendOTP(
        phoneNumber: fullPhoneNumber,
        onSuccess: (message) {
          debugPrint('OTP sent successfully: $message');
        },
        onError: (error) {
          if (mounted) {
            _showError(error);
          }
        },
        onCodeSent: (verificationId) {
          debugPrint('Verification ID received: $verificationId');
        },
        onAutoVerificationCompleted: (credential) async {
          // Handle auto-verification (rare on most devices)
          debugPrint('Auto-verification completed');
          await _handleAutoVerification(credential, fullPhoneNumber);
        },
      );
      
      if (otpSent && mounted) {
        // Navigate to OTP verification screen
        Navigator.pushNamed(
          context,
          AppConstants.otpVerificationRoute,
          arguments: {
            'phone_number': fullPhoneNumber,
            'password': fullPhoneNumber, // Keep for backward compatibility
            'is_phone_exist': true, // Will be determined after OTP verification
          },
        );
      }
    } catch (e) {
      if (mounted) {
        _showError('Failed to send OTP: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  /// Handle auto-verification when Firebase automatically verifies the phone number
  Future<void> _handleAutoVerification(credential, String phoneNumber) async {
    try {
      // Sign in with the credential
      await _firebasePhoneAuth.signInWithCredential(credential);
      
      if (mounted) {
        // Show success message
        _showSuccess('Phone number verified automatically!');
        
        // Navigate directly to OTP screen or handle the verification
        Navigator.pushNamed(
          context,
          AppConstants.otpVerificationRoute,
          arguments: {
            'phone_number': phoneNumber,
            'password': phoneNumber,
            'is_phone_exist': true,
            'auto_verified': true, // Flag to indicate auto-verification
          },
        );
      }
    } catch (e) {
      if (mounted) {
        _showError('Auto-verification failed: $e');
      }
    }
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Theme.of(context).colorScheme.error,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  void _showSuccess(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }
}