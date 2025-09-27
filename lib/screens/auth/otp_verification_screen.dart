import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import '../../constants/app_constants.dart';
import '../../services/api_service.dart';
import '../../services/firebase_phone_auth_service.dart';
import '../../services/auth_state_manager.dart';
import '../../models/user.dart';

class OTPVerificationScreen extends StatefulWidget {
  final String phoneNumber;
  final String password;
  final bool isPhoneExist;

  const OTPVerificationScreen({
    super.key,
    required this.phoneNumber,
    required this.password,
    required this.isPhoneExist,
  });

  @override
  State<OTPVerificationScreen> createState() => _OTPVerificationScreenState();
}

class _OTPVerificationScreenState extends State<OTPVerificationScreen> {
  final List<TextEditingController> _otpControllers = 
      List.generate(6, (index) => TextEditingController());
  final List<FocusNode> _focusNodes = 
      List.generate(6, (index) => FocusNode());
  
  bool _isLoading = false;
  bool _isResending = false;
  Timer? _countdownTimer;
  int _resendCountdown = 60;
  bool _canResend = false;

  // Services
  late ApiService _apiService;
  final FirebasePhoneAuthService _firebasePhoneAuth = FirebasePhoneAuthService();

  @override
  void initState() {
    super.initState();
    _apiService = ApiService();
    _startCountdown();
  }

  void _startCountdown() {
    setState(() {
      _resendCountdown = 60;
      _canResend = false;
    });
    
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_resendCountdown > 0) {
        setState(() {
          _resendCountdown--;
        });
      } else {
        setState(() {
          _canResend = true;
        });
        timer.cancel();
      }
    });
  }

  void _resetCountdown() {
    _countdownTimer?.cancel();
    _startCountdown();
  }

  void _clearAllFields() {
    for (var controller in _otpControllers) {
      controller.clear();
    }
    // Focus on first field after clearing all
    _focusNodes[0].requestFocus();
    setState(() {}); // Rebuild to update UI
  }

  @override
  void dispose() {
    for (var controller in _otpControllers) {
      controller.dispose();
    }
    for (var focusNode in _focusNodes) {
      focusNode.dispose();
    }
    _countdownTimer?.cancel();
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
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 40.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 24),
          _buildTitle(theme),
          const SizedBox(height: 8),
          _buildSubtitle(theme),
          const SizedBox(height: 32),
          _buildOTPFields(theme),
          const SizedBox(height: 20),
          _buildResendSection(theme),
          const SizedBox(height: 48),
          _buildVerifyButton(theme),
        ],
      ),
    );
  }

  Widget _buildTitle(ThemeData theme) {
    return Text(
      'OTP Code Verification',
      textAlign: TextAlign.center,
      style: GoogleFonts.lato(
        fontSize: 28,
        fontWeight: FontWeight.bold,
        color: theme.colorScheme.primary,
      ),
    );
  }

  Widget _buildSubtitle(ThemeData theme) {
    // Mask phone number like in Android: +1180*******11
    String maskedPhone = _maskPhoneNumber(widget.phoneNumber);
    
    return Text(
      'Code Has Been send to $maskedPhone',
      textAlign: TextAlign.center,
      style: GoogleFonts.poppins(
        fontSize: 12.82,
        color: theme.colorScheme.onSurface,
        fontWeight: FontWeight.normal,
      ),
    );
  }

  String _maskPhoneNumber(String phone) {
    if (phone.length > 6) {
      return '${phone.substring(0, 4)}*******${phone.substring(phone.length - 2)}';
    }
    return phone;
  }

  Widget _buildOTPFields(ThemeData theme) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: List.generate(6, (index) => _buildOTPField(index, theme)),
      ),
    );
  }

  Widget _buildOTPField(int index, ThemeData theme) {
    return Container(
      width: 45,
      height: 55,
      decoration: BoxDecoration(
        border: Border.all(
          color: _otpControllers[index].text.isNotEmpty
              ? theme.colorScheme.primary
              : theme.dividerColor,
          width: 2,
        ),
        borderRadius: BorderRadius.circular(8),
        color: theme.colorScheme.surface,
      ),
      child: KeyboardListener(
        focusNode: FocusNode(),
        onKeyEvent: (KeyEvent event) {
          // Handle backspace on empty field
          if (event is KeyDownEvent && 
              event.logicalKey == LogicalKeyboardKey.backspace &&
              _otpControllers[index].text.isEmpty &&
              index > 0) {
            _focusNodes[index - 1].requestFocus();
          }
        },
        child: TextFormField(
          controller: _otpControllers[index],
          focusNode: _focusNodes[index],
          textAlign: TextAlign.center,
          style: GoogleFonts.poppins(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.onSurface,
          ),
          keyboardType: TextInputType.number,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(1),
        ],
        decoration: const InputDecoration(
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          errorBorder: InputBorder.none,
          focusedErrorBorder: InputBorder.none,
          contentPadding: EdgeInsets.all(0),
          fillColor: Colors.transparent,
          filled: true,
        ),
        onChanged: (value) {
          setState(() {}); // Rebuild to update border color
          
          if (value.isNotEmpty) {
            // Move to next field when user enters a digit
            if (index < 5) {
              _focusNodes[index + 1].requestFocus();
            } else {
              // Last field, remove focus
              _focusNodes[index].unfocus();
              // Auto-verify if all fields are filled
              _checkAutoVerify();
            }
          } else {
            // Field is now empty (user deleted content or pressed backspace)
            // Move to previous field
            if (index > 0) {
              _focusNodes[index - 1].requestFocus();
            }
          }
        },
        ),
      ),
    );
  }

  Widget _buildResendSection(ThemeData theme) {
    return Column(
      children: [
        if (!_canResend)
          Text(
            'Resend Code in ${_resendCountdown}s',
            style: GoogleFonts.poppins(
              fontSize: 12.83,
              color: theme.colorScheme.onSurface,
              fontWeight: FontWeight.normal,
            ),
          )
        else
          GestureDetector(
            onTap: _isResending ? null : _handleResendOTP,
            child: Text(
              _isResending ? 'Resending...' : 'Resend Code',
              style: GoogleFonts.poppins(
                fontSize: 12.83,
                color: _isResending 
                    ? theme.colorScheme.onSurface.withValues(alpha: 0.5)
                    : theme.colorScheme.primary,
                fontWeight: FontWeight.normal,
              ),
            ),
          ),
        SizedBox(height: 8),
        // Clear All button for easy reset
        GestureDetector(
          onTap: () {
            _clearAllFields();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('All fields cleared'),
                duration: Duration(milliseconds: 800),
                backgroundColor: theme.colorScheme.primary,
              ),
            );
          },
          child: Text(
            'Clear All',
            style: GoogleFonts.poppins(
              fontSize: 12.83,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              fontWeight: FontWeight.normal,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildVerifyButton(ThemeData theme) {
    final isOTPComplete = _otpControllers.every((controller) => 
        controller.text.isNotEmpty);

    return SizedBox(
      width: 262,
      height: 52, // Consistent with phone signin screen
      child: ElevatedButton(
        onPressed: (_isLoading || !isOTPComplete) ? null : _handleVerifyOTP,
        style: ElevatedButton.styleFrom(
          backgroundColor: theme.colorScheme.primary,
          foregroundColor: theme.colorScheme.onPrimary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          elevation: 0,
          disabledBackgroundColor: theme.colorScheme.primary.withValues(alpha: 0.6),
        ),
        child: _isLoading
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(theme.colorScheme.onPrimary),
                ),
              )
            : Text(
                'Verify',
                style: GoogleFonts.poppins(
                  fontSize: 14, // Matching Android size
                  fontWeight: FontWeight.w600,
                ),
              ),
      ),
    );
  }

  void _checkAutoVerify() {
    final isOTPComplete = _otpControllers.every((controller) => 
        controller.text.isNotEmpty);
    
    if (isOTPComplete && !_isLoading) {
      // Add a small delay for better UX
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          _handleVerifyOTP();
        }
      });
    }
  }

  Future<void> _handleVerifyOTP() async {
    final otp = _otpControllers.map((controller) => controller.text).join();
    
    if (otp.length != 6) {
      _showError('Please enter the complete OTP');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // Verify OTP using Firebase Phone Auth
      final credential = await _firebasePhoneAuth.verifyOTP(otp);
      
      if (credential != null) {
        // Sign in with Firebase credential
        await _firebasePhoneAuth.signInWithCredential(credential);
        
        debugPrint('Firebase phone authentication successful');
        
        // Check if phone number exists in backend system
        final phoneNumber = widget.phoneNumber.startsWith('+') 
            ? widget.phoneNumber.substring(1) 
            : widget.phoneNumber;
            
        final phoneCheckResponse = await _apiService.checkPhoneNumber(phoneNumber);
        
        if (phoneCheckResponse.exists) {
          // Phone exists - proceed with phone login
          await _handlePhoneLogin();
        } else {
          // Phone doesn't exist - navigate to profile setup for account creation
          await _handleNewUserRegistration();
        }
      }
      
    } catch (e) {
      if (mounted) {
        _showError('Verification failed: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _handlePhoneLogin() async {
    try {
      final phoneLoginRequest = PhoneLoginRequest(
        phoneNumber: widget.phoneNumber,
        password: widget.password,
      );
      
      final loginResponse = await _apiService.phoneLogin(phoneLoginRequest);
      
      if (mounted) {
        // Update AuthStateManager with the logged-in user
        await Provider.of<AuthStateManager>(context, listen: false)
            .handleSuccessfulLogin(loginResponse.user);
        
        // Navigate to chat screen on successful login
        Navigator.pushNamedAndRemoveUntil(
          context,
          AppConstants.chatListRoute,
          (route) => false,
        );
        
        _showSuccess('Welcome back, ${loginResponse.user.username}!');
      }
    } catch (e) {
      if (mounted) {
        _showError('Login failed: $e');
      }
      rethrow; // Re-throw to be caught by parent try-catch
    }
  }

  Future<void> _handleNewUserRegistration() async {
    if (mounted) {
      // Navigate to profile setup screen for new user registration
      Navigator.pushReplacementNamed(
        context,
        AppConstants.profileSetupRoute,
        arguments: {
          'phone_number': widget.phoneNumber,
          'password': widget.password,
        },
      );
      
      _showSuccess('Phone verified! Please complete your profile setup.');
    }
  }

  Future<void> _handleResendOTP() async {
    setState(() {
      _isResending = true;
    });

    try {
      // Resend OTP using Firebase Phone Auth
      final otpSent = await _firebasePhoneAuth.resendOTP(
        phoneNumber: widget.phoneNumber,
        onSuccess: (message) {
          if (mounted) {
            _showSuccess(message);
            // Reset countdown after successful resend
            _resetCountdown();
          }
        },
        onError: (error) {
          if (mounted) {
            _showError(error);
          }
        },
        onCodeSent: (verificationId) {
          debugPrint('OTP resent with verification ID: $verificationId');
        },
      );
      
      if (!otpSent && mounted) {
        _showError('Failed to resend OTP. Please try again.');
      }
      
    } catch (e) {
      if (mounted) {
        _showError('Failed to resend OTP: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isResending = false;
        });
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