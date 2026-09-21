import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../state/session.dart';
import '../../state/student_state.dart';

class _Message {
  const _Message({required this.text, required this.fromUser, this.suggestions = const []});

  final String text;
  final bool fromUser;
  final List<String> suggestions;
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

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send(String text) async {
    if (text.trim().isEmpty || _sending) return;
    setState(() {
      _messages.add(_Message(text: text.trim(), fromUser: true));
      _sending = true;
    });
    _controller.clear();
    _scrollToEnd();
    final api = context.read<StudentState>().api;
    try {
      final r = await api.chat(text.trim());
      setState(() => _messages.add(_Message(
            text: r['reply'] as String? ?? '',
            fromUser: false,
            suggestions: ((r['suggestions'] as List?) ?? []).cast<String>(),
          )));
    } on ApiException catch (e) {
      setState(() => _messages.add(_Message(text: e.message, fromUser: false)));
    } catch (_) {
      setState(() => _messages.add(const _Message(text: 'JAGO needs an internet connection to answer. Try again once you are online.', fromUser: false)));
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

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final s = Strings(session.language);
    final suggestionChips = _messages.isNotEmpty ? _messages.last.suggestions : const ['Which schemes can I apply for?', 'What documents do I need?', 'Where is my application?', 'Any corrections pending?'];

    return Scaffold(
      appBar: AppBar(title: const Row(children: [
        CircleAvatar(radius: 14, backgroundColor: Colors.white, child: Icon(Icons.forum_outlined, size: 16, color: AppColors.primary)),
        SizedBox(width: 8),
        Text('JAGO'),
      ])),
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        session.language == 'hi'
                            ? 'जोहार! मुझसे पात्रता, दस्तावेज़, स्थिति, सुधार या भुगतान के बारे में पूछें।'
                            : 'Johar! Ask me about eligibility, documents, application status, corrections or payments.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.grey),
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length,
                    itemBuilder: (context, i) => _Bubble(message: _messages[i], onSuggestion: _send),
                  ),
          ),
          if (_sending) const Padding(padding: EdgeInsets.only(bottom: 8), child: LinearProgressIndicator(minHeight: 2)),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  ...suggestionChips.map((c) => ActionChip(label: Text(c, style: const TextStyle(fontSize: 12)), onPressed: () => _send(c))),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: InputDecoration(hintText: s.askJago),
                    onSubmitted: _send,
                    textInputAction: TextInputAction.send,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(onPressed: () => _send(_controller.text), icon: const Icon(Icons.send)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message, required this.onSuggestion});

  final _Message message;
  final void Function(String) onSuggestion;

  @override
  Widget build(BuildContext context) {
    final mine = message.fromUser;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        decoration: BoxDecoration(
          color: mine ? AppColors.primary : Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(14),
            topRight: const Radius.circular(14),
            bottomLeft: Radius.circular(mine ? 14 : 2),
            bottomRight: Radius.circular(mine ? 2 : 14),
          ),
        ),
        child: Text(message.text, style: TextStyle(color: mine ? Colors.white : Colors.black87)),
      ),
    );
  }
}
