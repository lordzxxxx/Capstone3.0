import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:mycapstone_project/app/features/auth/login.dart';
import 'package:mycapstone_project/app/features/auth/reset_password_service.dart';
import 'package:mycapstone_project/app/features/auth/verification_code.dart';

const Color _primaryAqua = Color(0xFF00A8B5);
const Color _secondaryIceBlue = Color(0xFF1E5A7A);
const Color _darkDeepTeal = Color(0xFF0A1F24);
const Color _mutedCoolGray = Color(0xFF546E7A);
const Color _lightOffWhite = Color(0xFFF5F5F5);
const Color _sidebarDark = Color(0xFF0E2F34);
const Color _panelSurface = Color(0xFF061920);

class ForgotPassword extends StatefulWidget {
	const ForgotPassword({super.key});

	@override
	State<ForgotPassword> createState() => _ForgotPasswordState();
}

class _ForgotPasswordState extends State<ForgotPassword> {
	final TextEditingController emailController = TextEditingController();
	bool _isLoading = false;

	Future<void> resetPassword() async {
		final String email = emailController.text.trim();
		if (email.isEmpty) {
			Get.snackbar(
				'Error',
				'Please enter your email address',
				backgroundColor: const Color(0xFFD32F2F),
				colorText: Colors.white,
			);
			return;
		}
		setState(() => _isLoading = true);
		try {
			// Send verification code to email
			await ResetPasswordService.sendVerificationCode(email);

			setState(() => _isLoading = false);

			Get.snackbar(
				'Success',
				'Verification code sent to your email',
				backgroundColor: const Color(0xFF388E3C),
				colorText: Colors.white,
			);

			// Navigate to verification screen
			Future.delayed(const Duration(milliseconds: 500), () {
				Get.offAll(() => VerificationCode(email: email));
			});
		} catch (e) {
			setState(() => _isLoading = false);
			Get.snackbar(
				'Reset Failed',
				e.toString().replaceFirst('Exception: ', ''),
				backgroundColor: const Color(0xFFD32F2F),
				colorText: Colors.white,
			);
		}
	}

	@override
	void dispose() {
		emailController.dispose();
		super.dispose();
	}

	@override
	Widget build(BuildContext context) {
		return Scaffold(
			backgroundColor: _darkDeepTeal,
			appBar: AppBar(
				elevation: 0,
				backgroundColor: Colors.transparent,
				leading: IconButton(
					icon: const Icon(Icons.arrow_back, color: _lightOffWhite),
					onPressed: () {
						final navigator = Navigator.of(context);
						if (navigator.canPop()) {
							navigator.pop();
							return;
						}
						navigator.pushReplacement(
							MaterialPageRoute(builder: (context) => const Login()),
						);
					},
				),
				title: Text(
					'Forgot Password',
					style: Theme.of(context).textTheme.headlineMedium?.copyWith(
								color: _lightOffWhite,
							),
				),
			),
			body: Container(
				decoration: BoxDecoration(
					gradient: LinearGradient(
						begin: Alignment.topLeft,
						end: Alignment.bottomRight,
						colors: [
							_darkDeepTeal,
							_secondaryIceBlue.withValues(alpha: 0.28),
							_sidebarDark,
						],
					),
				),
				child: SingleChildScrollView(
					child: Padding(
						padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 40),
						child: Container(
							padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
							decoration: BoxDecoration(
								color: _sidebarDark.withValues(alpha: 0.94),
								borderRadius: BorderRadius.circular(24),
								border: Border.all(
									color: _primaryAqua.withValues(alpha: 0.16),
									width: 1.4,
								),
								boxShadow: [
									BoxShadow(
										color: Colors.black.withValues(alpha: 0.22),
										blurRadius: 24,
										offset: const Offset(0, 12),
									),
								],
							),
							child: Column(
								crossAxisAlignment: CrossAxisAlignment.start,
								children: [
									Center(
										child: Container(
											padding: const EdgeInsets.symmetric(
												horizontal: 14,
												vertical: 8,
											),
											decoration: BoxDecoration(
												color: _panelSurface,
												borderRadius: BorderRadius.circular(999),
												border: Border.all(
													color: _primaryAqua.withValues(alpha: 0.18),
												),
											),
											child: Text(
												'Secure Recovery',
												style: Theme.of(context).textTheme.labelLarge?.copyWith(
															color: _primaryAqua,
															fontWeight: FontWeight.w700,
															letterSpacing: 0.4,
														),
											),
										),
									),
									const SizedBox(height: 20),
									Center(
										child: Container(
											width: 100,
											height: 100,
											decoration: BoxDecoration(
												color: _panelSurface,
												borderRadius: BorderRadius.circular(24),
												border: Border.all(
													color: _primaryAqua.withValues(alpha: 0.22),
													width: 1.6,
												),
											),
											child: const Icon(
												Icons.lock_reset,
												color: _primaryAqua,
												size: 50,
											),
										),
									),
									const SizedBox(height: 32),
									Text(
										'Reset Password',
										style: Theme.of(context).textTheme.displaySmall?.copyWith(
													color: _lightOffWhite,
												),
									),
									const SizedBox(height: 8),
									Text(
										'Enter your email address and we\'ll send you a verification code to reset your password.',
										style: Theme.of(context).textTheme.bodyLarge?.copyWith(
													color: _lightOffWhite.withValues(alpha: 0.72),
												),
									),
									const SizedBox(height: 32),
									Text(
										'Email Address',
										style: Theme.of(context).textTheme.titleMedium?.copyWith(
													color: _lightOffWhite,
												),
									),
									const SizedBox(height: 8),
									TextField(
										controller: emailController,
										keyboardType: TextInputType.emailAddress,
										style: const TextStyle(color: _lightOffWhite),
										decoration: InputDecoration(
											hintText: 'you@example.com',
											hintStyle: TextStyle(
												color: _lightOffWhite.withValues(alpha: 0.42),
											),
											prefixIcon: const Icon(
												Icons.email_outlined,
												color: _primaryAqua,
											),
											border: OutlineInputBorder(
												borderRadius: BorderRadius.circular(12),
												borderSide: BorderSide(
													color: _primaryAqua.withValues(alpha: 0.20),
													width: 1.2,
												),
											),
											enabledBorder: OutlineInputBorder(
												borderRadius: BorderRadius.circular(12),
												borderSide: BorderSide(
													color: _primaryAqua.withValues(alpha: 0.20),
													width: 1.2,
												),
											),
											focusedBorder: OutlineInputBorder(
												borderRadius: BorderRadius.circular(12),
												borderSide: const BorderSide(
													color: _primaryAqua,
													width: 1.8,
												),
											),
											filled: true,
											fillColor: _panelSurface,
										),
									),
									const SizedBox(height: 32),
									SizedBox(
										width: double.infinity,
										height: 56,
										child: ElevatedButton(
											onPressed: _isLoading ? null : resetPassword,
											style: ElevatedButton.styleFrom(
												backgroundColor: _primaryAqua,
												foregroundColor: _darkDeepTeal,
												shape: RoundedRectangleBorder(
													borderRadius: BorderRadius.circular(12),
												),
												elevation: 2,
											),
											child: _isLoading
													? const SizedBox(
															height: 24,
															width: 24,
															child: CircularProgressIndicator(
																valueColor: AlwaysStoppedAnimation<Color>(
																	_darkDeepTeal,
																),
																strokeWidth: 2.5,
															),
														)
													: Text(
															'Send Verification Code',
														style: Theme.of(context)
																.textTheme
																.titleLarge
																?.copyWith(color: _darkDeepTeal),
													),
										),
									),
									const SizedBox(height: 24),
									Center(
										child: Row(
											mainAxisAlignment: MainAxisAlignment.center,
											children: [
												Text(
													'Remember your password? ',
													style: Theme.of(context).textTheme.bodyMedium?.copyWith(
																color: _lightOffWhite.withValues(alpha: 0.74),
															),
												),
												GestureDetector(
													onTap: () {
														Get.offAll(() => const Login());
													},
													child: Text(
														'Sign In',
														style: Theme.of(context).textTheme.titleMedium?.copyWith(
																	color: _primaryAqua,
																	fontWeight: FontWeight.bold,
																),
													),
												),
											],
										),
									),
								],
							),
						),
					),
				),
			),
		);
	}
}
