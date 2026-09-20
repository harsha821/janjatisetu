import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../state/session.dart';
import 'otr_registration_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _fullName = TextEditingController();
  final _email = TextEditingController();

  bool _registering = false;
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _phone.dispose();
    _password.dispose();
    _fullName.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final session = context.read<Session>();
    try {
      if (_registering) {
        await session.register(
          phone: _phone.text.trim(),
          password: _password.text,
          fullName: _fullName.text.trim(),
          email: _email.text.trim().isEmpty ? null : _email.text.trim(),
        );
      } else {
        await session.login(_phone.text.trim(), _password.text);
      }
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Could not reach the server. Check your connection and try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _fillDemo(String phone, String password) {
    _phone.text = phone;
    _password.text = password;
    setState(() => _registering = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 24),
                    _Logo(),
                    const SizedBox(height: 8),
                    const Text('JanjatiSetu', textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: AppColors.primary)),
                    const Text('Every student counts', textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic)),
                    const SizedBox(height: 32),
                    if (_registering) ...[
                      TextFormField(
                        controller: _fullName,
                        decoration: const InputDecoration(labelText: 'Full name'),
                        validator: (v) => (v == null || v.trim().length < 2) ? 'Enter your full name' : null,
                      ),
                      const SizedBox(height: 12),
                    ],
                    TextFormField(
                      controller: _phone,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(labelText: 'Phone number', prefixIcon: Icon(Icons.phone_outlined)),
                      validator: (v) => (v == null || v.trim().length < 10) ? 'Enter a valid phone number' : null,
                    ),
                    const SizedBox(height: 12),
                    if (_registering) ...[
                      TextFormField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(labelText: 'Email (optional)', prefixIcon: Icon(Icons.mail_outline)),
                      ),
                      const SizedBox(height: 12),
                    ],
                    TextFormField(
                      controller: _password,
                      obscureText: _obscure,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                      validator: (v) => (v == null || v.length < 6) ? 'Enter your password' : null,
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(_error!, style: const TextStyle(color: AppColors.danger)),
                    ],
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: _busy ? null : _submit,
                      child: _busy
                          ? const SizedBox(height: 18, width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : Text(_registering ? 'Create account' : 'Log in'),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: _busy ? null : () => setState(() => _registering = !_registering),
                      child: Text(_registering ? 'Already have an account? Log in' : "New here? Create an account"),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const OtrRegistrationScreen()),
                      ),
                      icon: const Icon(Icons.how_to_reg_outlined, color: Color(0xFFE11D48)),
                      label: const Text('One Time Registration (OTR)', style: TextStyle(color: Color(0xFFE11D48), fontWeight: FontWeight.bold)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFFE11D48)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                    const SizedBox(height: 24),
                    if (!_registering) _DemoAccounts(onPick: _fillDemo),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Logo extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 72,
      height: 72,
      alignment: Alignment.center,
      decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
      child: const Icon(Icons.school_rounded, color: Colors.white, size: 36),
    );
  }
}

class _DemoAccounts extends StatelessWidget {
  const _DemoAccounts({required this.onPick});

  final void Function(String phone, String password) onPick;

  static const _accounts = [
    {'label': 'Student — Sunita (correction pending)', 'phone': '9000000001', 'password': 'Student@123'},
    {'label': 'Student — Ravi (Top Class eligible)', 'phone': '9000000002', 'password': 'Student@123'},
    {'label': 'Verifier', 'phone': '9000000101', 'password': 'Verifier@123'},
    {'label': 'Ministry Admin', 'phone': '9000000201', 'password': 'Admin@123'},
  ];

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: const Text('Demo accounts', style: TextStyle(fontSize: 13, color: Colors.grey)),
      children: _accounts
          .map((a) => ListTile(
                dense: true,
                title: Text(a['label']!, style: const TextStyle(fontSize: 13)),
                subtitle: Text(a['phone']!, style: const TextStyle(fontSize: 12)),
                trailing: const Icon(Icons.chevron_right, size: 18),
                onTap: () => onPick(a['phone']!, a['password']!),
              ))
          .toList(),
    );
  }
}
