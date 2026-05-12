import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'api_config.dart';

class ChatService {
  static Future<String> sendMessage({
    required String email,
    required String message,
  }) async {
    final response = await http
        .post(
      Uri.parse("${ApiConfig.baseUrl}/chat"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({
        "email": email,
        "text": message,
      }),
    )
        .timeout(const Duration(seconds: 120));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data["response"] ?? "No response";
    } else {
      throw Exception('Server error: ${response.statusCode} ${response.body}');
    }
  }
}

class ChatMessage {
  final String text;
  final bool isUser;

  ChatMessage({
    required this.text,
    this.isUser = false,
  });
}

class ChatScreen extends StatefulWidget {
  final String email;

  const ChatScreen({
    super.key,
    required this.email,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final List<ChatMessage> messages = [];
  final TextEditingController inputCtrl = TextEditingController();
  bool loading = false;

  @override
  void initState() {
    super.initState();
    messages.add(
      ChatMessage(
        text: "Hi, I'm Lotus. I'm here to listen. How are you feeling today?",
        isUser: false,
      ),
    );
  }

  @override
  void dispose() {
    inputCtrl.dispose();
    super.dispose();
  }

  Future<void> sendMessageToBackend(String message) async {
    setState(() => loading = true);

    try {
      final response = await ChatService.sendMessage(
        email: widget.email,
        message: message,
      );

      if (!mounted) return;

      setState(() {
        messages.add(ChatMessage(text: response, isUser: false));
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        messages.add(
          ChatMessage(
            text: 'Baglanti hatasi: $e',
            isUser: false,
          ),
        );
      });
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  void onSend() {
    final txt = inputCtrl.text.trim();
    if (txt.isEmpty || loading) return;

    setState(() {
      messages.add(ChatMessage(text: txt, isUser: true));
      inputCtrl.clear();
    });

    sendMessageToBackend(txt);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Lotus'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: messages.length,
              itemBuilder: (ctx, i) {
                final m = messages[i];
                return Align(
                  alignment:
                  m.isUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: m.isUser
                          ? Colors.green.shade100
                          : Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(m.text),
                  ),
                );
              },
            ),
          ),
          if (loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: CircularProgressIndicator(),
            ),
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: inputCtrl,
                    decoration: const InputDecoration(
                      hintText: 'Mesajini yaz...',
                    ),
                    minLines: 1,
                    maxLines: 4,
                    onSubmitted: (_) => onSend(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: loading ? null : onSend,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
