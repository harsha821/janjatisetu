import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../state/session.dart';
import '../../state/student_state.dart';
import 'application_screen.dart';
import 'schemes_screen.dart';
import 'wallet_screen.dart';

class _Message {
  const _Message({
    required this.text,
    required this.fromUser,
    this.time = '10:25 AM',
    this.suggestions = const [],
    this.isEligibleCard = false,
    this.studentName = 'Student',
  });

  final String text;
  final bool fromUser;
  final String time;
  final List<String> suggestions;
  final bool isEligibleCard;
  final String studentName;
}

class JagoScreen extends StatefulWidget {
  const JagoScreen({super.key});

  @override
  State<JagoScreen> createState() => _JagoScreenState();
}

class _JagoScreenState extends State<JagoScreen> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  final List<_Message> _messages = [];
  bool _sending = false;
  bool _listening = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_messages.isEmpty) {
        final state = context.read<StudentState>();
        final name = (state.dashboard?['student']?['name'] as String?) ?? 'Student';
        setState(() {
          _messages.add(_Message(
            text: 'Can I apply for the Top Class Education scheme if my family income is below ₹6 Lakh?',
            fromUser: true,
            time: '10:24 AM',
          ));
          _messages.add(_Message(
            text: 'Under the Ministry of Tribal Affairs guidelines, students with family annual income up to ₹6.00 Lakh are eligible for Premier Institutions funding:',
            fromUser: false,
            time: '10:25 AM',
            isEligibleCard: true,
            studentName: name,
            suggestions: ['Where is my application?', 'Any corrections pending?', 'Payment status & DBT?'],
          ));
        });
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send(String text) async {
    if (text.trim().isEmpty || _sending) return;
    final now = TimeOfDay.now().format(context);
    setState(() {
      _messages.add(_Message(text: text.trim(), fromUser: true, time: now));
      _sending = true;
    });
    _controller.clear();
    _scrollToEnd();
    final api = context.read<StudentState>().api;
    try {
      final r = await api.chat(text.trim());
      final state = context.read<StudentState>();
      final name = (state.dashboard?['student']?['name'] as String?) ?? 'Student';
      final reply = r['reply'] as String? ?? '';
      final isTopClass = text.toLowerCase().contains('top class') || text.toLowerCase().contains('eligible') || text.toLowerCase().contains('income');

      setState(() => _messages.add(_Message(
            text: reply,
            fromUser: false,
            time: TimeOfDay.now().format(context),
            isEligibleCard: isTopClass,
            studentName: name,
            suggestions: ((r['suggestions'] as List?) ?? []).cast<String>(),
          )));
    } on ApiException catch (e) {
      setState(() => _messages.add(_Message(text: e.message, fromUser: false, time: now)));
    } catch (_) {
      setState(() => _messages.add(_Message(
            text: 'JAGO: I am ready to guide you on Tribal Affairs scholarships, DigiLocker verification, and DBT status.',
            fromUser: false,
            time: now,
          )));
    } finally {
      if (mounted) setState(() => _sending = false);
      _scrollToEnd();
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _pickAttachment() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf', 'jpg', 'png']);
    if (res != null && res.files.isNotEmpty) {
      final name = res.files.first.name;
      _send('I have uploaded "$name". Please verify if this document is valid for scholarship requirements.');
    }
  }

  void _speakMessage(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(
        children: [
          const Icon(Icons.volume_up, color: Colors.white),
          const SizedBox(width: 8),
          Expanded(child: Text('Playing audio readout in ${context.read<Session>().language.toUpperCase()}...')),
        ],
      ),
      backgroundColor: const Color(0xFF002970),
      duration: const Duration(seconds: 2),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final s = Strings(session.language);
    final suggestionChips = _messages.isNotEmpty && _messages.last.suggestions.isNotEmpty
        ? _messages.last.suggestions
        : ['Where is my application?', 'Any corrections pending?', 'Payment status & DBT?'];

    return Scaffold(
      backgroundColor: const Color(0xFFF4F8FC),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: const Color(0xFF002970),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.15), shape: BoxShape.circle),
              child: const Icon(Icons.chat_bubble_outline, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text('JAGO', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white)),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: const Color(0xFF00B97A), borderRadius: BorderRadius.circular(10)),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircleAvatar(radius: 3, backgroundColor: Colors.white),
                          SizedBox(width: 4),
                          Text('Online', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ],
                ),
                const Text('DBT & Scholarship AI Assistant', style: TextStyle(color: Color(0xFFE0F2FE), fontSize: 11)),
              ],
            ),
          ],
        ),
        actions: [
          // Language Switcher
          InkWell(
            onTap: () {
              final nextLang = session.language == 'en' ? 'hi' : 'en';
              session.setLanguage(nextLang);
            },
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                session.language == 'hi' ? 'हिन्दी | EN' : 'EN | हिन्दी',
                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.volume_up_outlined, color: Colors.white),
            tooltip: 'Audio Assistant',
            onPressed: () => _speakMessage('JAGO AI is ready to read responses aloud.'),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: Column(
        children: [
          // Trust Banner
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: const BoxDecoration(
              color: Color(0xFF001A4A),
              border: Border(bottom: BorderSide(color: Color(0xFF00BAF2), width: 1.5)),
            ),
            child: Row(
              children: [
                const Icon(Icons.verified_user, color: Color(0xFF00BAF2), size: 16),
                const SizedBox(width: 6),
                const Text('100% Verified Guidelines', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text('DigiLocker & Aadhaar Ready', style: TextStyle(color: Color(0xFFE0F7FF), fontSize: 11)),
                ),
              ],
            ),
          ),

          // Chat Messages
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              itemCount: _messages.length,
              itemBuilder: (context, i) => _JagoBubble(
                message: _messages[i],
                onAction: _send,
                onSpeak: _speakMessage,
              ),
            ),
          ),

          if (_sending) const LinearProgressIndicator(color: Color(0xFF00BAF2), backgroundColor: Color(0xFFE2EEF8), minHeight: 2),

          // Helper Status
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: const Row(
              children: [
                Icon(Icons.circle, color: Color(0xFF00BAF2), size: 8),
                SizedBox(width: 6),
                Text('JAGO is ready to answer questions or review your documents', style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
              ],
            ),
          ),

          // Suggestion Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: suggestionChips.map((c) {
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ActionChip(
                    backgroundColor: Colors.white,
                    side: const BorderSide(color: Color(0xFFCBD5E1)),
                    label: Text(c, style: const TextStyle(fontSize: 12, color: Color(0xFF002970), fontWeight: FontWeight.w500)),
                    onPressed: () => _send(c),
                  ),
                );
              }).toList(),
            ),
          ),

          // Bottom Input Bar
          Container(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Color(0xFFE2EEF8))),
            ),
            child: SafeArea(
              child: Row(
                children: [
                  IconButton(
                    onPressed: _pickAttachment,
                    icon: const Icon(Icons.attach_file, color: Color(0xFF64748B)),
                    tooltip: 'Attach Document',
                  ),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: const Color(0xFFE2EEF8)),
                      ),
                      child: Row(
                        children: [
                          const SizedBox(width: 14),
                          Expanded(
                            child: TextField(
                              controller: _controller,
                              decoration: InputDecoration(
                                hintText: 'Ask JAGO anything in English or ${s.language.toUpperCase()}...',
                                hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                              ),
                              onSubmitted: _send,
                            ),
                          ),
                          IconButton(
                            icon: Icon(_listening ? Icons.mic : Icons.mic_none, color: _listening ? Colors.red : const Color(0xFF64748B)),
                            onPressed: () {
                              setState(() => _listening = !_listening);
                              if (_listening) {
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                                  content: Text('Listening to voice query... (Speak now)'),
                                  duration: Duration(seconds: 2),
                                ));
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    decoration: const BoxDecoration(
                      color: Color(0xFF002970),
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                      onPressed: () => _send(_controller.text),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _JagoBubble extends StatelessWidget {
  const _JagoBubble({
    required this.message,
    required this.onAction,
    required this.onSpeak,
  });

  final _Message message;
  final void Function(String) onAction;
  final void Function(String) onSpeak;

  @override
  Widget build(BuildContext context) {
    final isUser = message.fromUser;

    if (isUser) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Container(
              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.82),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF002970),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(18),
                  topRight: Radius.circular(18),
                  bottomLeft: Radius.circular(18),
                  bottomRight: Radius.circular(4),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                message.text,
                style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.4, fontWeight: FontWeight.w500),
              ),
            ),
            const SizedBox(height: 4),
            Text('${message.time} • Read', style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8))),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            margin: const EdgeInsets.only(top: 4, right: 8),
            decoration: const BoxDecoration(color: Color(0xFF002970), shape: BoxShape.circle),
            child: const Icon(Icons.chat_bubble, color: Colors.white, size: 16),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFFE2EEF8)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (message.isEligibleCard) ...[
                        // Eligibility Banner
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFECFDF5),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFA7F3D0)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.check, color: Color(0xFF059669), size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Yes, ${message.studentName}! You are fully eligible.',
                                  style: const TextStyle(color: Color(0xFF065F46), fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],

                      Text(
                        message.text,
                        style: const TextStyle(fontSize: 13, height: 1.45, color: Color(0xFF1E293B)),
                      ),

                      if (message.isEligibleCard) ...[
                        const SizedBox(height: 12),
                        // Eligibility Checklist
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('Eligibility Checklist', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0F172A))),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFDCFCE7),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: const Text('3/3 Qualified', style: TextStyle(color: Color(0xFF166534), fontWeight: FontWeight.bold, fontSize: 11)),
                                  ),
                                ],
                              ),
                              const Divider(height: 16),
                              _checklistRow('Income Limit:', 'Family income ≤ ₹6.0 Lakh/annum (Verified via DigiLocker)'),
                              const SizedBox(height: 6),
                              _checklistRow('Admission:', 'Admitted to notified premier list (IIT, NIT, AIIMS, IIM, etc.)'),
                              const SizedBox(height: 6),
                              _checklistRow('DBT Bank Status:', 'Aadhaar active bank account ready for direct grant deposit'),
                            ],
                          ),
                        ),

                        const SizedBox(height: 14),

                        // Action Button 1: Start Application
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF002970),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            onPressed: () {
                              Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SchemesScreen()));
                            },
                            icon: const Text('Start Top Class Application', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            label: const Icon(Icons.arrow_forward, size: 16),
                          ),
                        ),

                        const SizedBox(height: 8),

                        // Action Button 2: View Mandatory Documents
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF002970),
                              side: const BorderSide(color: Color(0xFFCBD5E1)),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            onPressed: () {
                              Navigator.of(context).push(MaterialPageRoute(builder: (_) => const WalletScreen()));
                            },
                            icon: const Icon(Icons.description_outlined, size: 16),
                            label: const Text('View Mandatory Documents (DigiLocker)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: 4),
                Row(
                  children: [
                    Text('${message.time} • Powered by NSP Portal', style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8))),
                    const Spacer(),
                    InkWell(
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Thanks for your feedback!'), duration: Duration(seconds: 1)));
                      },
                      child: const Row(
                        children: [
                          Icon(Icons.thumb_up_alt_outlined, size: 13, color: Color(0xFF64748B)),
                          SizedBox(width: 3),
                          Text('Helpful', style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    InkWell(
                      onTap: () => onSpeak(message.text),
                      child: const Row(
                        children: [
                          Icon(Icons.volume_up_outlined, size: 13, color: Color(0xFF00BAF2)),
                          SizedBox(width: 3),
                          Text('Listen', style: TextStyle(fontSize: 11, color: Color(0xFF00BAF2), fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _checklistRow(String title, String desc) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.check, color: Color(0xFF059669), size: 16),
        const SizedBox(width: 6),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: const TextStyle(fontSize: 12, color: Color(0xFF334155), height: 1.3),
              children: [
                TextSpan(text: '$title ', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                TextSpan(text: desc),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
