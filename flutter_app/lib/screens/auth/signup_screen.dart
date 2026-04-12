import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../config/app_theme.dart';
import '../../services/supabase_service.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _formKey    = GlobalKey<FormState>();
  final _firstCtrl  = TextEditingController();
  final _lastCtrl   = TextEditingController();
  final _phoneCtrl  = TextEditingController();
  final _emailCtrl  = TextEditingController();
  final _passCtrl   = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _loading = false;
  bool _obscurePass = true;

  Future<void> _signUp() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    final email    = _emailCtrl.text.trim();
    final password = _passCtrl.text;
    try {
      await SupabaseService().signUp(
        email,
        password,
        firstName: _firstCtrl.text.trim(),
        lastName:  _lastCtrl.text.trim(),
        phone:     _phoneCtrl.text.trim(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Account created! Check your email to confirm.'),
          ),
        );
        context.go('/login');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Sign up failed: $e'),
              backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _signUpWithGoogle() async {
    setState(() => _loading = true);
    try {
      await SupabaseService().signInWithGoogle();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Google sign up failed: $e'),
              backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _firstCtrl.dispose();
    _lastCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios,
              color: AppColors.textPrimary, size: 18),
          onPressed: () => context.pop(),
        ),
        title: Text('Create Account',
            style: GoogleFonts.playfairDisplay(
                color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 16),

                // Logo
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: AppColors.accent,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.format_paint,
                      color: Colors.black, size: 28),
                ),
                const SizedBox(height: 20),

                Text('Create account',
                    style: GoogleFonts.playfairDisplay(
                        color: AppColors.textPrimary,
                        fontSize: 26,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                const Text('Save your rooms and track your projects',
                    style: TextStyle(
                        color: AppColors.textSecondary, fontSize: 14)),
                const SizedBox(height: 28),

                // First + Last name row
                Row(children: [
                  Expanded(
                    child: _DarkField(
                      controller: _firstCtrl,
                      label: 'First Name',
                      icon: Icons.person_outlined,
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Required' : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _DarkField(
                      controller: _lastCtrl,
                      label: 'Last Name',
                      icon: Icons.person_outlined,
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Required' : null,
                    ),
                  ),
                ]),
                const SizedBox(height: 14),

                // Phone
                _DarkField(
                  controller: _phoneCtrl,
                  label: 'Phone Number',
                  icon: Icons.phone_outlined,
                  keyboardType: TextInputType.phone,
                  validator: (v) =>
                      (v == null || v.trim().length < 7)
                          ? 'Enter a valid phone number'
                          : null,
                ),
                const SizedBox(height: 14),

                // Email
                _DarkField(
                  controller: _emailCtrl,
                  label: 'Email',
                  icon: Icons.email_outlined,
                  keyboardType: TextInputType.emailAddress,
                  validator: (v) =>
                      (v == null || !v.contains('@'))
                          ? 'Enter a valid email'
                          : null,
                ),
                const SizedBox(height: 14),

                // Password
                _DarkField(
                  controller: _passCtrl,
                  label: 'Password',
                  icon: Icons.lock_outlined,
                  obscureText: _obscurePass,
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePass
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      color: AppColors.textSecondary,
                      size: 20,
                    ),
                    onPressed: () =>
                        setState(() => _obscurePass = !_obscurePass),
                  ),
                  validator: (v) =>
                      (v == null || v.length < 6)
                          ? 'At least 6 characters'
                          : null,
                ),
                const SizedBox(height: 14),

                // Confirm password
                _DarkField(
                  controller: _confirmCtrl,
                  label: 'Confirm Password',
                  icon: Icons.lock_outlined,
                  obscureText: true,
                  validator: (v) =>
                      v != _passCtrl.text ? 'Passwords do not match' : null,
                ),
                const SizedBox(height: 28),

                FilledButton(
                  onPressed: _loading ? null : _signUp,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _loading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.black))
                      : const Text('Create Account',
                          style: TextStyle(
                              fontSize: 16,
                              color: Colors.black,
                              fontWeight: FontWeight.w600)),
                ),
                const SizedBox(height: 20),

                Row(children: const [
                  Expanded(child: Divider(color: AppColors.border)),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Text('or',
                        style: TextStyle(
                            color: AppColors.textSecondary, fontSize: 13)),
                  ),
                  Expanded(child: Divider(color: AppColors.border)),
                ]),
                const SizedBox(height: 20),

                OutlinedButton.icon(
                  icon: const Icon(Icons.g_mobiledata,
                      size: 24, color: AppColors.textPrimary),
                  label: const Text('Continue with Google',
                      style: TextStyle(
                          color: AppColors.textPrimary, fontSize: 15)),
                  onPressed: _loading ? null : _signUpWithGoogle,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    side: const BorderSide(color: AppColors.border),
                  ),
                ),
                const SizedBox(height: 32),

                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('Already have an account?',
                        style: TextStyle(
                            color: AppColors.textSecondary, fontSize: 13)),
                    TextButton(
                      onPressed: () => context.go('/login'),
                      child: const Text('Sign In',
                          style: TextStyle(
                              color: AppColors.accent,
                              fontSize: 13,
                              fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DarkField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final TextInputType? keyboardType;
  final bool obscureText;
  final Widget? suffixIcon;
  final String? Function(String?)? validator;

  const _DarkField({
    required this.controller,
    required this.label,
    required this.icon,
    this.keyboardType,
    this.obscureText = false,
    this.suffixIcon,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      style: const TextStyle(color: AppColors.textPrimary),
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        labelStyle:
            const TextStyle(color: AppColors.textSecondary, fontSize: 14),
        prefixIcon: Icon(icon, color: AppColors.textSecondary, size: 20),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: AppColors.card,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.accent),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.error),
        ),
      ),
    );
  }
}
