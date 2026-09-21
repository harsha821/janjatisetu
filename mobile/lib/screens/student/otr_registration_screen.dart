import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../state/session.dart';

class OtrRegistrationScreen extends StatefulWidget {
  const OtrRegistrationScreen({super.key});

  @override
  State<OtrRegistrationScreen> createState() => _OtrRegistrationScreenState();
}

class _OtrRegistrationScreenState extends State<OtrRegistrationScreen> {
  int _currentStep = 1;

  // Step 1 Checkboxes
  bool _readGuidelines = false;
  bool _consentAadhaar = false;

  // Step 2 Mobile & Captcha
  final _mobileController = TextEditingController();
  final _mobileOtpController = TextEditingController();
  final _captchaController = TextEditingController();
  bool _mobileOtpSent = false;
  String _captchaType = 'image';
  String _currentCaptcha = 'NYVCSN';

  // Step 3 eKYC
  String _kycMode = 'aadhaar'; // 'aadhaar', 'eid', 'none'
  final _aadhaarController = TextEditingController();
  final _aadhaarOtpController = TextEditingController();
  bool _aadhaarOtpSent = false;
  bool _obscureAadhaar = true;

  // Step 4 Profile & Password
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  String _gender = 'Female';
  String _category = 'ST';
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  String _generatedOtr = '';

  bool _busy = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _regenerateCaptcha();
    _generatedOtr = 'OTR-2026-ST-${10000 + Random().nextInt(89999)}';
  }

  @override
  void dispose() {
    _mobileController.dispose();
    _mobileOtpController.dispose();
    _captchaController.dispose();
    _aadhaarController.dispose();
    _aadhaarOtpController.dispose();
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _regenerateCaptcha() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rnd = Random();
    setState(() {
      _currentCaptcha = List.generate(6, (_) => chars[rnd.nextInt(chars.length)]).join();
      _captchaController.clear();
    });
  }

  void _sendMobileOtp() {
    if (_mobileController.text.trim().length < 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid 10-digit mobile number')),
      );
      return;
    }
    setState(() {
      _mobileOtpSent = true;
      _mobileOtpController.text = '123456'; // demo helper
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('OTP sent to your mobile number. (Demo OTP: 123456)'),
        backgroundColor: AppColors.success,
      ),
    );
  }

  void _sendAadhaarOtp() {
    if (_aadhaarController.text.trim().length < 12) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid 12-digit Aadhaar / EID number')),
      );
      return;
    }
    setState(() {
      _aadhaarOtpSent = true;
      _aadhaarOtpController.text = '123456'; // demo helper
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('OTP sent to UIDAI registered mobile. (Demo OTP: 123456)'),
        backgroundColor: AppColors.success,
      ),
    );
  }

  void _verifyStep2() {
    if (!_mobileOtpSent) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please click "Get OTP" to request an OTP first')),
      );
      return;
    }
    if (_mobileOtpController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter the 6-digit OTP')),
      );
      return;
    }
    if (_captchaController.text.trim().toUpperCase() != _currentCaptcha.toUpperCase()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Incorrect Captcha Code. Please try again.')),
      );
      _regenerateCaptcha();
      return;
    }
    if (_passwordController.text.length < 8) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password must be at least 8 characters')),
      );
      return;
    }
    if (_passwordController.text != _confirmPasswordController.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Passwords do not match')),
      );
      return;
    }
    setState(() {
      _currentStep = 3;
    });
  }

  void _verifyStep3() {
    if (_kycMode != 'none') {
      if (!_aadhaarOtpSent) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please click "Get OTP" to verify Aadhaar')),
        );
        return;
      }
      if (_aadhaarOtpController.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter Aadhaar OTP')),
        );
        return;
      }
    }
    setState(() {
      if (_nameController.text.isEmpty) {
        _nameController.text = 'Sunita Oraon'; // Demo eKYC auto-fill
      }
      _currentStep = 4;
    });
  }

  Future<void> _completeRegistration() async {
    if (_nameController.text.trim().length < 2) {
      setState(() => _errorMessage = 'Please enter your full name');
      return;
    }
    if (_passwordController.text.length < 8) {
      setState(() => _errorMessage = 'Password must be at least 8 characters');
      return;
    }
    if (_passwordController.text != _confirmPasswordController.text) {
      setState(() => _errorMessage = 'Passwords do not match');
      return;
    }

    setState(() {
      _busy = true;
      _errorMessage = null;
    });

    final session = context.read<Session>();
    try {
      await session.register(
        phone: _mobileController.text.trim(),
        password: _passwordController.text,
        fullName: _nameController.text.trim(),
        email: _emailController.text.trim().isEmpty ? null : _emailController.text.trim(),
      );
      if (mounted) {
        Navigator.of(context).pop(); // Back to main root which auto-navigates to StudentShell
      }
    } on ApiException catch (e) {
      setState(() => _errorMessage = e.message);
    } catch (_) {
      setState(() => _errorMessage = 'Registration failed. Check connection.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              _buildTopNav(),
              const SizedBox(height: 16),
              _buildStepperHeader(),
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1050),
                    child: Card(
                      color: Colors.white,
                      elevation: 2,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: Padding(
                        padding: const EdgeInsets.all(28.0),
                        child: _buildCurrentStepContent(),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopNav() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.account_balance_rounded, color: AppColors.primary, size: 28),
              ),
              const SizedBox(width: 12),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'National Scholarship Portal',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF1E293B)),
                  ),
                  Text(
                    'JanjatiSetu — Unified ST/PVTG Portal',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ],
          ),
          Row(
            children: [
              TextButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.help_outline, size: 16),
                label: const Text("FAQ's"),
              ),
              TextButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.campaign_outlined, size: 16),
                label: const Text('Announcements'),
              ),
              TextButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.support_agent_outlined, size: 16),
                label: const Text('Helpdesk'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStepperHeader() {
    final steps = [
      {'num': 1, 'title': '1. Guidelines'},
      {'num': 2, 'title': '2. Register Mobile No.'},
      {'num': 3, 'title': '3. eKYC'},
      {'num': 4, 'title': '4. Finish'},
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Center(
        child: Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 10,
          children: steps.map((step) {
            final int num = step['num'] as int;
            final String title = step['title'] as String;
            final bool isActive = _currentStep == num;
            final bool isDone = _currentStep > num;

            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: isActive
                    ? const Color(0xFFE11D48) // NSP pink/red theme
                    : (isDone ? const Color(0xFF10B981) : const Color(0xFFE2E8F0)),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isDone)
                    const Icon(Icons.check_circle, size: 16, color: Colors.white)
                  else
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isActive ? Colors.white : const Color(0xFF64748B),
                      ),
                    ),
                  const SizedBox(width: 8),
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: isActive || isDone ? FontWeight.bold : FontWeight.w500,
                      color: isActive || isDone ? Colors.white : const Color(0xFF475569),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildCurrentStepContent() {
    switch (_currentStep) {
      case 1:
        return _buildStep1Guidelines();
      case 2:
        return _buildStep2MobileRegister();
      case 3:
        return _buildStep3Ekyc();
      case 4:
        return _buildStep4Finish();
      default:
        return const SizedBox();
    }
  }

  // ------------------------------------------------------------- STEP 1
  Widget _buildStep1Guidelines() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '1. One Time Registration (OTR) Guidelines for Scholarships Hosted on NSP',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
        ),
        const SizedBox(height: 16),
        const Divider(),
        const SizedBox(height: 12),
        _guidelinePoint('1. Mandatory Requirement:', 'One Time Registration (OTR) is mandatory for applying for various scholarship schemes on National Scholarship Portal/other portals.'),
        _guidelinePoint('2. Essential Requirement for OTR:', 'Active mobile number is mandatory for OTR.'),
        _guidelinePoint('3. No payment of fee:', 'No payment of fee is required for OTR.'),
        _guidelinePoint('4. Steps for Registration:', ''),
        const Padding(
          padding: EdgeInsets.only(left: 20, bottom: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('I. Once allotted an OTR, student can apply for scholarship later when the portal is open for application submission.', style: TextStyle(fontSize: 13, color: Color(0xFF475569))),
              SizedBox(height: 4),
              Text('II. Upon successful registration, a reference number will be sent on the registered mobile number.', style: TextStyle(fontSize: 13, color: Color(0xFF475569))),
              SizedBox(height: 4),
              Text('III. Download and install NSP OTR app and Aadhaar Face RD services on android based devices.', style: TextStyle(fontSize: 13, color: Color(0xFF475569))),
              SizedBox(height: 4),
              Text('IV. Perform the Face-Authentication using the generated reference number for OTR sent on your mobile no.', style: TextStyle(fontSize: 13, color: Color(0xFF475569))),
              SizedBox(height: 4),
              Text('V. After successful Face-Authentication OTR will be generated.', style: TextStyle(fontSize: 13, color: Color(0xFF475569))),
            ],
          ),
        ),
        _guidelinePoint('5.', 'Please apply for Scholarship using OTR. Merely generation of OTR does not tantamount to application for scholarship.'),
        _guidelinePoint('6. Aadhaar Requirement:', 'Aadhaar is required for OTR. If Aadhaar is not assigned, registration can be done using Enrollment ID (EID) for Aadhaar.'),
        _guidelinePoint('7.', 'It is advised to update other relevant demographic records (name, dob, gender) to match with Aadhaar/EID.'),
        _guidelinePoint('8.', 'Parent/legal guardian of minor applying with their Aadhaar must ensure that while making an application for Aadhaar enrolment of minor shall use the same demographic details.'),
        _guidelinePoint('9.', 'One OTR ID is allowed per student. However, parent/legal guardian can generate upto a maximum of two OTRs (for two minor children).'),
        _guidelinePoint('10.', 'In case more than one OTR is found for a student, she/he would be liable for debarment from scholarships.'),
        const SizedBox(height: 20),
        const Text(
          'I agree to the following:',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1E293B)),
        ),
        const SizedBox(height: 8),
        CheckboxListTile(
          value: _readGuidelines,
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
          title: const Text('I have read and understood the guidelines for One time Registration.', style: TextStyle(fontSize: 13)),
          onChanged: (val) => setState(() => _readGuidelines = val ?? false),
        ),
        CheckboxListTile(
          value: _consentAadhaar,
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
          title: const Text('I hereby consent to use the Aadhaar/ OTR for de-duplication on NSP/State/UT Scholarship Portals.', style: TextStyle(fontSize: 13)),
          onChanged: (val) => setState(() => _consentAadhaar = val ?? false),
        ),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12)),
              child: const Text('Cancel'),
            ),
            const SizedBox(width: 16),
            ElevatedButton(
              onPressed: (_readGuidelines && _consentAadhaar)
                  ? () => setState(() => _currentStep = 2)
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF334155),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
              ),
              child: const Text('Next'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _guidelinePoint(String boldText, String normalText) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(fontSize: 13, color: Color(0xFF334155), height: 1.4),
          children: [
            TextSpan(text: '$boldText ', style: const TextStyle(fontWeight: FontWeight.bold)),
            TextSpan(text: normalText),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------- STEP 2
  Widget _buildStep2MobileRegister() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '2. Register Mobile No.',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
        ),
        const SizedBox(height: 16),
        const Divider(),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth > 650;
            return Flex(
              direction: isWide ? Axis.horizontal : Axis.vertical,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Left: Form
                Expanded(
                  flex: isWide ? 6 : 0,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Mobile Number *', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _mobileController,
                              keyboardType: TextInputType.phone,
                              decoration: const InputDecoration(
                                hintText: 'Enter 10 digit mobile number',
                                border: OutlineInputBorder(),
                                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          ElevatedButton(
                            onPressed: _sendMobileOtp,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF0F172A),
                              foregroundColor: Colors.white,
                            ),
                            child: Text(_mobileOtpSent ? 'Resend OTP' : 'Get OTP'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Text('Enter OTP *', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _mobileOtpController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          hintText: 'Enter 6 digit OTP',
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Radio<String>(
                            value: 'image',
                            groupValue: _captchaType,
                            onChanged: (v) => setState(() => _captchaType = v!),
                          ),
                          const Text('Image Captcha', style: TextStyle(fontSize: 13)),
                          const SizedBox(width: 16),
                          Radio<String>(
                            value: 'audio',
                            groupValue: _captchaType,
                            onChanged: (v) => setState(() => _captchaType = v!),
                          ),
                          const Text('Audio Captcha', style: TextStyle(fontSize: 13)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE2E8F0),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: const Color(0xFFCBD5E1)),
                            ),
                            child: Text(
                              _currentCaptcha,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 4,
                                fontStyle: FontStyle.italic,
                                color: Color(0xFF1E293B),
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: _regenerateCaptcha,
                            icon: const Icon(Icons.refresh_rounded),
                            tooltip: 'Refresh Captcha',
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Text('Enter Captcha Code *', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _captchaController,
                        decoration: const InputDecoration(
                          hintText: 'Enter captcha code',
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Divider(),
                      const SizedBox(height: 12),
                      const Text('Set Account Password', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                      const SizedBox(height: 12),
                      const Text('Password *', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        decoration: InputDecoration(
                          hintText: 'Create password (min 8 characters)',
                          border: const OutlineInputBorder(),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          suffixIcon: IconButton(
                            icon: Icon(_obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                            onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text('Confirm Password *', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _confirmPasswordController,
                        obscureText: _obscureConfirmPassword,
                        decoration: InputDecoration(
                          hintText: 'Re-enter your password',
                          border: const OutlineInputBorder(),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          suffixIcon: IconButton(
                            icon: Icon(_obscureConfirmPassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                            onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (isWide) const SizedBox(width: 28),
                if (!isWide) const SizedBox(height: 24),
                // Right: Note Box
                Expanded(
                  flex: isWide ? 4 : 0,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Note:-', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        SizedBox(height: 8),
                        Text('1. Student/Parent/Legal guardian must read the instructions carefully before registration.', style: TextStyle(fontSize: 12, color: Color(0xFF475569))),
                        SizedBox(height: 6),
                        Text('2. Student/Parent/Legal guardian is advised to submit the requisite details carefully before submission. Correction/editing will not be allowed after submission.', style: TextStyle(fontSize: 12, color: Color(0xFF475569))),
                        SizedBox(height: 6),
                        Text('3. Any wrong/false information may lead to rejection.', style: TextStyle(fontSize: 12, color: Color(0xFF475569))),
                        SizedBox(height: 6),
                        Text('4. Student/Parent/Legal guardian is advised to submit active mobile number and email address. All correspondence/communication will be done on the submitted mobile/email only.', style: TextStyle(fontSize: 12, color: Color(0xFF475569))),
                        SizedBox(height: 6),
                        Text('5. Student is advised to refer to National Scholarship Portal for regular updates.', style: TextStyle(fontSize: 12, color: Color(0xFF475569))),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 28),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            OutlinedButton(
              onPressed: () => setState(() => _currentStep = 1),
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12)),
              child: const Text('Cancel'),
            ),
            const SizedBox(width: 16),
            ElevatedButton(
              onPressed: _verifyStep2,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF334155),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
              ),
              child: const Text('Verify'),
            ),
          ],
        ),
      ],
    );
  }

  // ------------------------------------------------------------- STEP 3
  Widget _buildStep3Ekyc() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '3. eKYC',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
        ),
        const SizedBox(height: 16),
        const Divider(),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            _kycOption('I have Aadhaar', 'aadhaar'),
            _kycOption('Aadhaar not assigned (I have EID)', 'eid'),
            _kycOption("I don't have Aadhaar/EID", 'none'),
          ],
        ),
        const SizedBox(height: 20),
        LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth > 650;
            return Flex(
              direction: isWide ? Axis.horizontal : Axis.vertical,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: isWide ? 6 : 0,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _kycMode == 'aadhaar'
                            ? 'Aadhaar No. *'
                            : (_kycMode == 'eid' ? 'Enrollment ID (EID) *' : 'School/College ID *'),
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _aadhaarController,
                              obscureText: _obscureAadhaar,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                hintText: _kycMode == 'aadhaar' ? 'Enter 12 digit Aadhaar number' : 'Enter ID number',
                                border: const OutlineInputBorder(),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                suffixIcon: IconButton(
                                  icon: Icon(_obscureAadhaar ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                                  onPressed: () => setState(() => _obscureAadhaar = !_obscureAadhaar),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          ElevatedButton(
                            onPressed: _sendAadhaarOtp,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF0F172A),
                              foregroundColor: Colors.white,
                            ),
                            child: Text(_aadhaarOtpSent ? 'Resend OTP' : 'Get OTP'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Text('Enter OTP *', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _aadhaarOtpController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          hintText: 'Enter 6 digit Aadhaar OTP',
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                      ),
                    ],
                  ),
                ),
                if (isWide) const SizedBox(width: 28),
                if (!isWide) const SizedBox(height: 24),
                Expanded(
                  flex: isWide ? 4 : 0,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Note:-', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        SizedBox(height: 8),
                        Text('1. Parent/Legal Guardian/Student must read the instructions carefully before registration.', style: TextStyle(fontSize: 12, color: Color(0xFF475569))),
                        SizedBox(height: 6),
                        Text('2. Parent/Legal Guardian/Student is advised to fill the requisite details carefully before submission, as correction/editing will not be allowed after submission.', style: TextStyle(fontSize: 12, color: Color(0xFF475569))),
                        SizedBox(height: 6),
                        Text('3. Any wrong/false information may lead to rejection.', style: TextStyle(fontSize: 12, color: Color(0xFF475569))),
                        SizedBox(height: 6),
                        Text('4. Parent/Legal Guardian/Student is advised to refer to National Scholarship Portal for regular updates.', style: TextStyle(fontSize: 12, color: Color(0xFF475569))),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 28),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            OutlinedButton(
              onPressed: () => setState(() => _currentStep = 2),
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12)),
              child: const Text('Cancel'),
            ),
            const SizedBox(width: 16),
            ElevatedButton(
              onPressed: _verifyStep3,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF334155),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
              ),
              child: const Text('Verify'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _kycOption(String title, String val) {
    final selected = _kycMode == val;
    return InkWell(
      onTap: () => setState(() => _kycMode = val),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFEFF6FF) : Colors.white,
          border: Border.all(color: selected ? AppColors.primary : const Color(0xFFCBD5E1)),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off, size: 16, color: selected ? AppColors.primary : Colors.grey),
            const SizedBox(width: 6),
            Text(title, style: TextStyle(fontSize: 12, color: selected ? AppColors.primary : Colors.black87)),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------- STEP 4
  Widget _buildStep4Finish() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '4. Finish & OTR Generation',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
        ),
        const SizedBox(height: 16),
        const Divider(),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFECFDF5),
            border: Border.all(color: const Color(0xFFA7F3D0)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              const Icon(Icons.check_circle, color: Color(0xFF059669), size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('e-KYC Verified Successfully!', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF065F46))),
                    Text('Your One Time Registration (OTR) ID: $_generatedOtr', style: const TextStyle(fontSize: 13, color: Color(0xFF047857), fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        const Text('Student Demographic Details', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        const SizedBox(height: 12),
        TextField(
          controller: _nameController,
          decoration: const InputDecoration(
            labelText: 'Full Name (as per Aadhaar) *',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
            labelText: 'Email Address (optional)',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: _gender,
                decoration: const InputDecoration(labelText: 'Gender', border: OutlineInputBorder()),
                items: ['Female', 'Male', 'Other'].map((g) => DropdownMenuItem(value: g, child: Text(g))).toList(),
                onChanged: (v) => setState(() => _gender = v!),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: _category,
                decoration: const InputDecoration(labelText: 'Social Category', border: OutlineInputBorder()),
                items: ['ST', 'PVTG'].map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                onChanged: (v) => setState(() => _category = v!),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        const Text('Set Account Password', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        const SizedBox(height: 12),
        TextField(
          controller: _passwordController,
          obscureText: _obscurePassword,
          decoration: InputDecoration(
            labelText: 'Create Password (min 8 characters) *',
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              icon: Icon(_obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _confirmPasswordController,
          obscureText: _obscureConfirmPassword,
          decoration: InputDecoration(
            labelText: 'Confirm Password *',
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              icon: Icon(_obscureConfirmPassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
              onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
            ),
          ),
        ),
        if (_errorMessage != null) ...[
          const SizedBox(height: 12),
          Text(_errorMessage!, style: const TextStyle(color: AppColors.danger)),
        ],
        const SizedBox(height: 24),
        Center(
          child: ElevatedButton(
            onPressed: _busy ? null : _completeRegistration,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0F172A),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 14),
            ),
            child: _busy
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Text('Complete Registration & Enter Portal', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
          ),
        ),
      ],
    );
  }
}
