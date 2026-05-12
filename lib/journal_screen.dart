import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class JournalScreen extends StatefulWidget {
  final String email;

  const JournalScreen({
    super.key,
    required this.email,
  });

  @override
  State<JournalScreen> createState() => _JournalScreenState();
}

class _JournalScreenState extends State<JournalScreen> {
  final TextEditingController journalCtrl = TextEditingController();

  List<Map<String, dynamic>> saved = [];
  bool isSaving = false;

  static const String baseUrl = 'http://10.0.2.2:8000';

  String get _journalKey => 'journal_entries_${widget.email}';

  @override
  void initState() {
    super.initState();
    loadData();
  }

  @override
  void dispose() {
    journalCtrl.dispose();
    super.dispose();
  }

  Future<void> saveData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_journalKey, jsonEncode(saved));
  }

  Future<void> loadData() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString(_journalKey);

    if (data != null && data.isNotEmpty) {
      setState(() {
        saved = List<Map<String, dynamic>>.from(jsonDecode(data));
      });
    }
  }

  Future<void> _sendJournalToBackend(Map<String, dynamic> entry) async {
    final response = await http
        .post(
      Uri.parse('$baseUrl/save-journal'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(entry),
    )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Journal save failed: ${response.statusCode} ${response.body}',
      );
    }
  }

  Future<void> addEntry() async {
    final text = journalCtrl.text.trim();

    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please write something first.")),
      );
      return;
    }

    setState(() {
      isSaving = true;
    });

    final entry = <String, dynamic>{
      "email": widget.email,
      "text": text,
      "date": DateTime.now().toIso8601String(),
    };

    try {
      await _sendJournalToBackend(entry);

      setState(() {
        saved.insert(0, entry);
        journalCtrl.clear();
      });

      await saveData();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Journal saved successfully")),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Baglanti hatasi: $e")),
      );
    } finally {
      if (mounted) {
        setState(() {
          isSaving = false;
        });
      }
    }
  }

  void showEntryDetail(Map<String, dynamic> entry) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Journal Entry"),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Date: ${entry['date']}"),
              const SizedBox(height: 12),
              const Text(
                "Text:",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Text(entry['text'] ?? ''),
              const SizedBox(height: 16),
              Text("Email: ${entry['email']}"),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Close"),
          ),
        ],
      ),
    );
  }

  String formatDate(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      return "${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year} "
          "${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
    } catch (_) {
      return iso;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Journal'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Expanded(
              flex: 2,
              child: TextField(
                controller: journalCtrl,
                expands: true,
                maxLines: null,
                decoration: InputDecoration(
                  hintText: "Write your journal...",
                  filled: true,
                  fillColor: Colors.green.shade50,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: isSaving ? null : addEntry,
                child: Text(isSaving ? "Saving..." : "Save"),
              ),
            ),
            const SizedBox(height: 16),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                "Saved entries",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              flex: 3,
              child: saved.isEmpty
                  ? const Center(
                child: Text("No saved journal entries yet."),
              )
                  : ListView.separated(
                itemCount: saved.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final entry = saved[index];

                  return InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => showEntryDetail(entry),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            formatDate(entry["date"] ?? ""),
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            entry["text"] ?? "",
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
