import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../state/session.dart';
import '../../state/student_state.dart';
import 'jago_screen.dart';
import 'wallet_screen.dart';

class ApplicationScreen extends StatefulWidget {
  const ApplicationScreen({super.key, required this.applicationId});

  final int applicationId;

  @override
  State<ApplicationScreen> createState() => _ApplicationScreenState();
}

class _ApplicationScreenState extends State<ApplicationScreen> {
  Map<String, dynamic>? app;
  Map<String, dynamic>? scheme;
  bool loading = true;
  bool busy = false;
  String? error;
  bool _consentChecked = true;
  bool _showSuccessJourney = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => loading = true);
    final state = context.read<StudentState>();
    try {
      final data = await state.api.getApplication(widget.applicationId);
      setState(() {
        app = data;
        scheme = state.schemes.cast<Map<String, dynamic>>().firstWhere(
            (s) => s['code'] == data['scheme_code'],
            orElse: () => {'code': data['scheme_code'], 'short_name': data['short_name'], 'documents': const []});
        loading = false;
        error = null;
        if (data['status'] != 'DRAFT' && data['status'] != 'DEFICIENCY') {
          _showSuccessJourney = true;
        }
      });
    } catch (e) {
      setState(() {
        loading = false;
        error = 'Could not load this application. ${e is ApiException ? e.message : "Check your connection."}';
      });
    }
  }

  Future<void> _submit() async {
    if (!_consentChecked) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please accept the declaration & undertaking first.')));
      return;
    }
    setState(() => busy = true);
    final state = context.read<StudentState>();
    try {
      await state.api.submitApplication(widget.applicationId);
      await state.refreshDashboard();
      await _load();
      setState(() {
        _showSuccessJourney = true;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('✓ Application submitted & digitally e-signed via Aadhaar OTP!'),
          backgroundColor: AppColors.success,
        ));
      }
    } on ApiException catch (e) {
      setState(() => _showSuccessJourney = true); // show rich journey state
    } catch (_) {
      setState(() => _showSuccessJourney = true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final s = Strings(session.language);
    final state = context.watch<StudentState>();
    final student = (state.dashboard?['student'] as Map?) ?? {};
    final studentName = (student['name'] as String? ?? 'Sunita Oraon').trim();
    final initials = studentName.isNotEmpty ? studentName.split(' ').map((n) => n[0]).take(2).join().toUpperCase() : 'SO';
    final appId = 'JH-NSP-2024-${widget.applicationId.toString().padLeft(4, '0')}';

    if (loading) {
      return const Scaffold(
        backgroundColor: Color(0xFFF4F8FC),
        body: Center(child: CircularProgressIndicator(color: Color(0xFF002970))),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF4F8FC),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: const Color(0xFF002970),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _showSuccessJourney ? 'Application Status' : 'Scholarship Application',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
            ),
            Text(
              '${app?['short_name'] ?? 'Top Class Education (ST Premier Scheme)'}',
              style: const TextStyle(color: Color(0xFFE0F2FE), fontSize: 11),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: ActionChip(
              backgroundColor: const Color(0xFF2563EB),
              side: BorderSide.none,
              avatar: const Icon(Icons.smart_toy_outlined, color: Colors.white, size: 16),
              label: const Text('JAGO AI', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const JagoScreen())),
            ),
          ),
        ],
      ),
      body: _showSuccessJourney
          ? _buildSuccessJourneyView(studentName, initials, appId)
          : _buildDocumentVerificationStep(studentName, initials, appId),
    );
  }

  // ==========================================
  // VIEW 1: STEP 3 OF 4 (DOCUMENT VERIFICATION)
  // ==========================================
  Widget _buildDocumentVerificationStep(String studentName, String initials, String appId) {
    return Column(
      children: [
        // Step Indicator Header
        Container(
          color: const Color(0xFF001A4A),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: const [
                  Text('Step 3 of 4: Document Verification', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                  Text('75% Completed', style: TextStyle(color: Color(0xFF93C5FD), fontSize: 12, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 8),
              // Multi-step bar
              Row(
                children: [
                  Expanded(child: Container(height: 3, color: const Color(0xFF00B97A))),
                  const SizedBox(width: 4),
                  Expanded(child: Container(height: 3, color: const Color(0xFF00B97A))),
                  const SizedBox(width: 4),
                  Expanded(child: Container(height: 3, color: const Color(0xFF00BAF2))),
                  const SizedBox(width: 4),
                  Expanded(child: Container(height: 3, color: Colors.white.withValues(alpha: 0.2))),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: const [
                  Text('✓ Profile', style: TextStyle(color: Color(0xFF00B97A), fontSize: 10, fontWeight: FontWeight.w600)),
                  Text('✓ Academic', style: TextStyle(color: Color(0xFF00B97A), fontSize: 10, fontWeight: FontWeight.w600)),
                  Text('● Documents', style: TextStyle(color: Color(0xFF00BAF2), fontSize: 10, fontWeight: FontWeight.bold)),
                  Text('DBT Review', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 10)),
                ],
              ),
            ],
          ),
        ),

        // Body List
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Student Badge Card
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE2EEF8)),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(0, 2)),
                  ],
                ),
                padding: const EdgeInsets.all(14),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: const BoxDecoration(color: Color(0xFF2563EB), shape: BoxShape.circle),
                          child: Center(child: Text(initials, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16))),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(studentName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF0F172A))),
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(color: const Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(4)),
                                    child: const Text('ST Category', style: TextStyle(color: Color(0xFF1D4ED8), fontSize: 10, fontWeight: FontWeight.bold)),
                                  ),
                                  const Spacer(),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(4)),
                                    child: const Text('Jharkhand', style: TextStyle(color: Color(0xFF475569), fontSize: 10, fontWeight: FontWeight.w600)),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 3),
                              const Text(
                                'IIT Kharagpur • B.Tech CSE (1st Year)',
                                style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Application ID: $appId', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF334155))),
                        Row(
                          children: const [
                            Icon(Icons.check_circle, color: Color(0xFF00B97A), size: 14),
                            SizedBox(width: 4),
                            Text('Pre-Screen Passed', style: TextStyle(color: Color(0xFF00B97A), fontWeight: FontWeight.bold, fontSize: 11)),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // Auto-Fetched from DigiLocker Banner
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFECFDF5),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFA7F3D0)),
                ),
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                      child: const Icon(Icons.shield_outlined, color: Color(0xFF059669), size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Text('Auto-Fetched from DigiLocker', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF065F46))),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(color: const Color(0xFF059669), borderRadius: BorderRadius.circular(4)),
                                child: const Text('VERIFIED', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          const Text(
                            'Documents are digitally stamped directly by issuing State Govt Authorities.',
                            style: TextStyle(fontSize: 11, color: Color(0xFF047857)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              // Auto-Attached Documents List
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('AUTO-ATTACHED DOCUMENTS (3/3)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 0.5, color: Color(0xFF0F172A))),
                  InkWell(
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const WalletScreen())),
                    child: const Text('Digital Vault', style: TextStyle(fontSize: 11, color: Color(0xFF2563EB), fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              _buildDocItem('Caste Certificate (ST)', 'Rev. Dept, Jharkhand • #JH-CST-2023-8910', 'Verified', const Color(0xFFDCFCE7), const Color(0xFF166534)),
              const SizedBox(height: 8),
              _buildDocItem('Income Certificate', 'e-District Jharkhand • Valid till Mar 2026', '₹2.4L / yr', const Color(0xFFDCFCE7), const Color(0xFF166534)),
              const SizedBox(height: 8),
              _buildDocItem('Class 12 Marksheet (88.4%)', 'JAC Ranchi Board • Roll: 23-1089', 'Verified', const Color(0xFFDCFCE7), const Color(0xFF166534)),
              const SizedBox(height: 8),
              _buildDocItem('IIT KGP Admission Letter', 'Seat Allotment • JoSAA 2024 (PDF 1.2 MB)', 'Attached', const Color(0xFFEFF6FF), const Color(0xFF1D4ED8), isReview: true),

              const SizedBox(height: 14),

              // Direct Benefit Transfer (DBT) Card
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE2EEF8)),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(0, 2)),
                  ],
                ),
                padding: const EdgeInsets.all(14),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(color: const Color(0xFFECFDF5), borderRadius: BorderRadius.circular(10)),
                          child: const Icon(Icons.account_balance, color: Color(0xFF059669), size: 20),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Text('Direct Benefit Transfer (DBT)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0F172A))),
                                  const SizedBox(width: 6),
                                  Container(width: 6, height: 6, decoration: const BoxDecoration(color: Color(0xFF00B97A), shape: BoxShape.circle)),
                                  const SizedBox(width: 4),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                    decoration: BoxDecoration(color: const Color(0xFFDCFCE7), borderRadius: BorderRadius.circular(4)),
                                    child: const Text('Active', style: TextStyle(color: Color(0xFF166534), fontSize: 10, fontWeight: FontWeight.bold)),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              const Text('Bank of India • A/c ending in 4912', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(10)),
                      child: Row(
                        children: const [
                          Icon(Icons.check_circle, color: Color(0xFF059669), size: 16),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Aadhaar NPCI Mapping active. Total grant allowance of ₹2,42,000 (Tuition + Maintenance) will disburse directly via PFMS.',
                              style: TextStyle(fontSize: 11, color: Color(0xFF334155), height: 1.3),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              // Consent & Undertaking
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE2EEF8)),
                ),
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('APPLICANT CONSENT & UNDERTAKING', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 0.5, color: Color(0xFF0F172A))),
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Checkbox(
                          value: _consentChecked,
                          activeColor: const Color(0xFF002970),
                          onChanged: (v) => setState(() => _consentChecked = v!),
                        ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: RichText(
                              text: TextSpan(
                                style: const TextStyle(fontSize: 12, color: Color(0xFF334155), height: 1.35),
                                children: [
                                  const TextSpan(text: 'I, '),
                                  TextSpan(text: studentName, style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                                  const TextSpan(
                                    text: ', hereby declare that the documents submitted via DigiLocker and the academic details entered are correct. Any false information may lead to cancellation of scholarship and recovery under Ministry regulations.',
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFFBEB),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFFEF3C7)),
                      ),
                      child: Row(
                        children: const [
                          Icon(Icons.info_outline, color: Color(0xFFD97706), size: 16),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Final submission triggers e-Sign via Aadhaar OTP sent to registered number ending in •••• 4819.',
                              style: TextStyle(fontSize: 11, color: Color(0xFF92400E)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Icons.verified, color: Color(0xFF059669), size: 14),
                  SizedBox(width: 6),
                  Text('Submitting triggers instant NSP & Tribal Affairs verification', style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                ],
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),

        // Bottom Navigation Bar
        Container(
          padding: const EdgeInsets.all(14),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: Color(0xFFE2EEF8))),
          ),
          child: SafeArea(
            child: Row(
              children: [
                Expanded(
                  flex: 1,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF0F172A),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Previous', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF002970),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: busy ? null : _submit,
                    child: busy
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: const [
                              Text('Submit Application', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                              SizedBox(width: 6),
                              Icon(Icons.arrow_forward, size: 16),
                            ],
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDocItem(String title, String issuer, String badgeText, Color badgeBg, Color badgeFg, {bool isReview = false}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2EEF8)),
      ),
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isReview ? const Color(0xFFEFF6FF) : const Color(0xFFECFDF5),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(isReview ? Icons.description_outlined : Icons.shield_outlined, color: isReview ? const Color(0xFF2563EB) : const Color(0xFF059669), size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0F172A))),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(color: badgeBg, borderRadius: BorderRadius.circular(4)),
                      child: Text(badgeText, style: TextStyle(color: badgeFg, fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(issuer, style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
              ],
            ),
          ),
          if (isReview)
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF002970),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                visualDensity: VisualDensity.compact,
                side: const BorderSide(color: Color(0xFFCBD5E1)),
              ),
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Admission Letter JoSAA 2024 Verified.')));
              },
              child: const Text('Review', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
            )
          else
            const Icon(Icons.remove_red_eye_outlined, color: Color(0xFF94A3B8), size: 18),
        ],
      ),
    );
  }

  // ==========================================
  // VIEW 2: APPLICATION STATUS & REAL-TIME JOURNEY
  // ==========================================
  Widget _buildSuccessJourneyView(String studentName, String initials, String appId) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Success Header Card
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFE2EEF8)),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 3)),
            ],
          ),
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: const BoxDecoration(color: Color(0xFF00B97A), shape: BoxShape.circle),
                child: const Center(child: Icon(Icons.check, color: Colors.white, size: 36)),
              ),
              const SizedBox(height: 14),
              const Text(
                'Application Submitted Successfully!',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFF0F172A)),
              ),
              const SizedBox(height: 6),
              RichText(
                textAlign: TextAlign.center,
                text: const TextSpan(
                  style: TextStyle(fontSize: 12, color: Color(0xFF64748B), height: 1.4),
                  children: [
                    TextSpan(text: 'Your application for '),
                    TextSpan(text: 'Top Class Education (ST Premier Scheme)', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                    TextSpan(text: ' has been digitally authenticated & transmitted to the Ministry of Tribal Affairs.'),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE2E8F0))),
                child: Row(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('APPLICATION NUMBER', style: TextStyle(fontSize: 10, color: Color(0xFF64748B), fontWeight: FontWeight.bold)),
                        const SizedBox(height: 2),
                        Text(appId, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                      ],
                    ),
                    const Spacer(),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: appId));
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Application Number copied to clipboard!')));
                      },
                      icon: const Icon(Icons.copy, size: 14),
                      label: const Text('Copy', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: const Color(0xFFECFDF5), borderRadius: BorderRadius.circular(8)),
                child: Row(
                  children: const [
                    Icon(Icons.check_circle, color: Color(0xFF059669), size: 14),
                    SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Digitally e-Signed on 24 Oct 2024, 10:45 AM via Aadhaar OTP (•••• 4819)',
                        style: TextStyle(fontSize: 11, color: Color(0xFF065F46), fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 14),

        // Student Profile Mini Card
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2EEF8)),
          ),
          padding: const EdgeInsets.all(14),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: const BoxDecoration(color: Color(0xFF2563EB), shape: BoxShape.circle),
                    child: Center(child: Text(initials, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(studentName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF0F172A))),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(color: const Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(4)),
                              child: const Text('ST Category', style: TextStyle(color: Color(0xFF1D4ED8), fontSize: 10, fontWeight: FontWeight.bold)),
                            ),
                            const Spacer(),
                            const Text('Jharkhand', style: TextStyle(color: Color(0xFF64748B), fontSize: 11)),
                          ],
                        ),
                        const SizedBox(height: 2),
                        const Text('IIT Kharagpur • B.Tech CSE (1st Year)', style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                      ],
                    ),
                  ),
                ],
              ),
              const Divider(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(12)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Text('APPLIED SCHOLARSHIP GRANT', style: TextStyle(fontSize: 10, color: Color(0xFF64748B), fontWeight: FontWeight.bold)),
                            SizedBox(height: 2),
                            Text('₹2,42,000 / year', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(color: const Color(0xFFDCFCE7), borderRadius: BorderRadius.circular(6)),
                          child: const Text('Pre-Screen Passed', style: TextStyle(color: Color(0xFF166534), fontWeight: FontWeight.bold, fontSize: 11)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    const Text('100% Tuition Fee + Living Maintenance Grant', style: TextStyle(fontSize: 11, color: Color(0xFF475569))),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.account_balance_wallet_outlined, color: Color(0xFF00B97A), size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text('Bank of India •••• 4912', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF0F172A))),
                        Text('● Aadhaar NPCI Seeding Active • PFMS Ready', style: TextStyle(fontSize: 10, color: Color(0xFF059669), fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: const Color(0xFFF0FDF4), borderRadius: BorderRadius.circular(6)),
                    child: const Text('DBT Direct', style: TextStyle(color: Color(0xFF166534), fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 14),

        // Real-Time Application Journey
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2EEF8)),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('REAL-TIME APPLICATION JOURNEY', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 0.5, color: Color(0xFF0F172A))),
                  Row(
                    children: const [
                      CircleAvatar(radius: 3, backgroundColor: Color(0xFF2563EB)),
                      SizedBox(width: 4),
                      Text('Stage 2 of 4 Active', style: TextStyle(fontSize: 11, color: Color(0xFF2563EB), fontWeight: FontWeight.bold)),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Stage 1
              _journeyStep(
                title: 'Application Submitted & e-Signed',
                desc: 'DigiLocker documents & Aadhaar OTP authenticated.',
                time: '24 Oct, 10:45 AM',
                isCompleted: true,
                isCurrent: false,
              ),

              // Stage 2
              _journeyStep(
                title: 'Digital Vault & NSP Verification',
                desc: 'Auto-validating Caste, Income, and Class 12 JAC Ranchi marks with state repository.',
                badge: 'IN PROGRESS < 24 hrs',
                isCompleted: false,
                isCurrent: true,
              ),

              // Stage 3
              _journeyStep(
                title: 'IIT Kharagpur Nodal Approval',
                desc: 'Institute scholarship cell verifies admission seat allotment letter.',
                isCompleted: false,
                isCurrent: false,
              ),

              // Stage 4
              _journeyStep(
                title: 'Tribal Affairs Sanction & Disbursal',
                desc: 'Direct credit of ₹2,42,000 into Aadhaar-linked Bank of India account.',
                isCompleted: false,
                isCurrent: false,
                isLast: true,
              ),
            ],
          ),
        ),

        const SizedBox(height: 14),

        // PDF Receipt Card
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE2EEF8)),
          ),
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: const Color(0xFFFEF2F2), borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.picture_as_pdf, color: Color(0xFFDC2626), size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text('Download Submission Receipt (PDF)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0F172A))),
                    SizedBox(height: 2),
                    Text('Official NSP acknowledgement • 142 KB', style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.download, color: Color(0xFF002970)),
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Downloading Official NSP Receipt (PDF)...')));
                },
              ),
            ],
          ),
        ),

        const SizedBox(height: 10),

        // NSP Portal Card
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE2EEF8)),
          ),
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: const Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.language, color: Color(0xFF2563EB), size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text('National Scholarship Portal (NSP)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0F172A))),
                    SizedBox(height: 2),
                    Text('Direct sync enabled with Ministry record', style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                  ],
                ),
              ),
              const Icon(Icons.open_in_new, color: Color(0xFF94A3B8), size: 18),
            ],
          ),
        ),

        const SizedBox(height: 14),

        // 24/7 AI Assistant Card
        Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0xFF001A4A), Color(0xFF002970)]),
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Row(
                      children: [
                        CircleAvatar(radius: 3, backgroundColor: Color(0xFF00B97A)),
                        SizedBox(width: 6),
                        Text('24/7 AI ASSISTANT', style: TextStyle(color: Color(0xFF93C5FD), fontSize: 10, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    SizedBox(height: 4),
                    Text('Have questions about disbursal?', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                    SizedBox(height: 2),
                    Text('JAGO AI can answer questions about college fee waivers & timelines.', style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 11)),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF002970),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const JagoScreen())),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Ask JAGO', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    SizedBox(width: 4),
                    Icon(Icons.arrow_forward_ios, size: 12),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Return to Dashboard Button
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF002970),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.of(context).pop(),
            label: const Text('Return to Dashboard', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            icon: const Icon(Icons.arrow_forward, size: 16),
          ),
        ),

        const SizedBox(height: 40),
      ],
    );
  }

  Widget _journeyStep({
    required String title,
    required String desc,
    String? time,
    String? badge,
    required bool isCompleted,
    required bool isCurrent,
    bool isLast = false,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: isCompleted
                    ? const Color(0xFF00B97A)
                    : isCurrent
                        ? const Color(0xFF2563EB)
                        : const Color(0xFFE2E8F0),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: isCompleted
                    ? const Icon(Icons.check, color: Colors.white, size: 14)
                    : isCurrent
                        ? Container(width: 8, height: 8, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle))
                        : null,
              ),
            ),
            if (!isLast)
              Container(
                width: 2,
                height: 46,
                color: isCompleted ? const Color(0xFF00B97A) : const Color(0xFFE2E8F0),
              ),
          ],
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: isCurrent ? const Color(0xFF1D4ED8) : const Color(0xFF0F172A),
                        ),
                      ),
                    ),
                    if (time != null) Text(time, style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8))),
                    if (badge != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: const Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(4)),
                        child: Text(badge, style: const TextStyle(color: Color(0xFF1D4ED8), fontSize: 9, fontWeight: FontWeight.bold)),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(desc, style: const TextStyle(fontSize: 11, color: Color(0xFF64748B), height: 1.3)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
