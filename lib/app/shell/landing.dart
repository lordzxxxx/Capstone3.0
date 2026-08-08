import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:mycapstone_project/app/features/dashboard/homepage.dart';
import 'package:mycapstone_project/app/features/auth/login.dart';
import 'package:mycapstone_project/app/features/auth/signup.dart';

const Color _primaryAqua = Color(0xFF00A8B5);
const Color _secondaryIceBlue = Color(0xFF1E5A7A);
const Color _darkDeepTeal = Color(0xFF0A1F24);
const Color _lightOffWhite = Color(0xFFF5F5F5);

class LandingPage extends StatelessWidget {
  const LandingPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _darkDeepTeal,
      body: Stack(
        children: [
          // Decorative background circles
          Positioned(
            top: -60,
            left: -60,
            child: Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                color: _primaryAqua.withValues(alpha: 0.18),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Positioned(
            bottom: -40,
            right: -40,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: _secondaryIceBlue.withValues(alpha: 0.18),
                shape: BoxShape.circle,
              ),
            ),
          ),
          // Main content
          Center(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 160,
                      height: 160,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: _primaryAqua.withValues(alpha: 0.18),
                            blurRadius: 28,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: ClipOval(
                        child: Image.asset(
                          'assets/bg2.png',
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) {
                            return const Icon(
                              Icons.medical_services_rounded,
                              size: 100,
                              color: _primaryAqua,
                            );
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildPartnerLogo('assets/logo1.png'),
                        const SizedBox(width: 16),
                        _buildPartnerLogo('assets/logo2.png'),
                        const SizedBox(width: 16),
                        _buildPartnerLogo('assets/logo3.png'),
                      ],
                    ),
                    const SizedBox(height: 40),
                    // Title
                    Text(
                      'AI-DSUHIS',
                      style: Theme.of(context).textTheme.displaySmall?.copyWith(
                        color: _lightOffWhite,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    // Subtitle
                    Text(
                      'AI-Driven Solution For Unified Health Information System',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            color: _lightOffWhite,
                            fontSize: 24,
                            fontWeight: FontWeight.w500,
                          ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 34),
                    // Login Button
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.of(context).pushReplacement(
                            MaterialPageRoute(
                              builder: (context) => const Login(),
                            ),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _primaryAqua,
                          foregroundColor: _darkDeepTeal,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 2,
                        ),
                        child: Text(
                          'Login',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(
                                color: _darkDeepTeal,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Sign Up Button
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: OutlinedButton(
                        onPressed: () {
                          Navigator.of(context).pushReplacement(
                            MaterialPageRoute(
                              builder: (context) => const Signup(),
                            ),
                          );
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _lightOffWhite,
                          side: const BorderSide(color: _primaryAqua, width: 2),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          'Sign Up',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(
                                color: _lightOffWhite,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: TextButton(
                        onPressed: () {
                          Get.offAll(
                            () => const HomePage(),
                            arguments: {'offline': true},
                          );
                        },
                        style: TextButton.styleFrom(
                          foregroundColor: _lightOffWhite,
                          backgroundColor: _darkDeepTeal.withValues(alpha: 0.18),
                          side: BorderSide(
                            color: _lightOffWhite.withValues(alpha: 0.18),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          'Continue to Offline',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                color: _lightOffWhite,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPartnerLogo(String assetPath) {
    return SizedBox(
      width: 76,
      height: 76,
      child: Image.asset(
        assetPath,
        fit: BoxFit.contain,
      ),
    );
  }
}
