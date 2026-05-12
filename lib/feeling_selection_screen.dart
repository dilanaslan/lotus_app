import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'api_config.dart';

final List<Map<String, dynamic>> emotions = [
  {"emoji": "😊", "label": "Happy", "type": "good"},
  {"emoji": "😍", "label": "Loved", "type": "good"},
  {"emoji": "😎", "label": "Confident", "type": "good"},
  {"emoji": "🥳", "label": "Excited", "type": "good"},
  {"emoji": "😇", "label": "Calm", "type": "good"},
  {"emoji": "🤗", "label": "Grateful", "type": "good"},
  {"emoji": "🌈", "label": "Hopeful", "type": "good"},
  {"emoji": "💪", "label": "Motivated", "type": "good"},
  {"emoji": "🧘", "label": "Peaceful", "type": "good"},
  {"emoji": "✨", "label": "Inspired", "type": "good"},
  {"emoji": "😔", "label": "Sad", "type": "bad"},
  {"emoji": "😡", "label": "Angry", "type": "bad"},
  {"emoji": "😰", "label": "Anxious", "type": "bad"},
  {"emoji": "😴", "label": "Tired", "type": "bad"},
  {"emoji": "😕", "label": "Confused", "type": "bad"},
  {"emoji": "😞", "label": "Disappointed", "type": "bad"},
  {"emoji": "😣", "label": "Stressed", "type": "bad"},
  {"emoji": "😶", "label": "Numb", "type": "bad"},
  {"emoji": "😓", "label": "Overwhelmed", "type": "bad"},
  {"emoji": "💔", "label": "Lonely", "type": "bad"},
];

class EmotionSelectionScreen extends StatefulWidget {
  final String email;

  const EmotionSelectionScreen({
    super.key,
    required this.email,
  });

  @override
  State<EmotionSelectionScreen> createState() => _EmotionSelectionScreenState();
}

class _EmotionSelectionScreenState extends State<EmotionSelectionScreen> {
  late final List<double> emotionLevels;
  late final List<TextEditingController> noteControllers;
  bool isSaving = false;

  String get _feelingKey => 'feeling_entries_${widget.email}';

  @override
  void initState() {
    super.initState();
    emotionLevels = List<double>.filled(emotions.length, 5);
    noteControllers = List.generate(
      emotions.length,
          (_) => TextEditingController(),
    );
    _loadLastFeelingData();
  }

  @override
  void dispose() {
    for (final controller in noteControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _loadLastFeelingData() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_feelingKey);

    if (raw == null || raw.isEmpty) return;

    final List<dynamic> allEntries = jsonDecode(raw);
    if (allEntries.isEmpty) return;

    final last = Map<String, dynamic>.from(allEntries.last);
    final levels = List<Map<String, dynamic>>.from(last["emotions"] ?? []);

    if (levels.length != emotions.length) return;

    setState(() {
      for (int i = 0; i < levels.length; i++) {
        emotionLevels[i] = (levels[i]["level"] as num).toDouble();
        noteControllers[i].text = (levels[i]["note"] ?? "").toString();
      }
    });
  }

  Future<void> _sendFeelingsToBackend(Map<String, dynamic> entry) async {
    final response = await http
        .post(
      Uri.parse('${ApiConfig.baseUrl}/save-feelings'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(entry),
    )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Feelings save failed: ${response.statusCode} ${response.body}',
      );
    }
  }

  Future<void> _saveFeelingData() async {
    setState(() {
      isSaving = true;
    });

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_feelingKey);

    List<dynamic> allEntries = [];
    if (raw != null && raw.isNotEmpty) {
      allEntries = jsonDecode(raw);
    }

    final emotionData = List.generate(emotions.length, (i) {
      return {
        "emoji": emotions[i]["emoji"],
        "label": emotions[i]["label"],
        "type": emotions[i]["type"],
        "level": emotionLevels[i].round(),
        "note": noteControllers[i].text.trim(),
      };
    });

    final good = emotionData.where((e) => e["type"] == "good").toList();
    final bad = emotionData.where((e) => e["type"] == "bad").toList();

    final goodAverage =
        good.fold<int>(0, (sum, e) => sum + (e["level"] as int)) / good.length;
    final badAverage =
        bad.fold<int>(0, (sum, e) => sum + (e["level"] as int)) / bad.length;

    final entry = {
      "email": widget.email,
      "date": DateTime.now().toIso8601String(),
      "emotions": emotionData,
      "goodPercent": (goodAverage * 10).round(),
      "badPercent": (badAverage * 10).round(),
    };

    try {
      await _sendFeelingsToBackend(entry);

      allEntries.add(entry);
      await prefs.setString(_feelingKey, jsonEncode(allEntries));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Feelings saved")),
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

  Widget _emotionCard(int i) {
    final emotion = emotions[i];
    final isGood = emotion["type"] == "good";

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                emotion["emoji"],
                style: const TextStyle(fontSize: 28),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  emotion["label"],
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                "${emotionLevels[i].round()}/10",
                style: TextStyle(
                  color: isGood ? Colors.green.shade700 : Colors.red.shade700,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Slider(
            value: emotionLevels[i],
            min: 1,
            max: 10,
            divisions: 9,
            activeColor: isGood ? Colors.green : Colors.red,
            onChanged: (value) {
              setState(() {
                emotionLevels[i] = value;
              });
            },
          ),
          const SizedBox(height: 4),
          TextField(
            controller: noteControllers[i],
            maxLines: 2,
            decoration: InputDecoration(
              hintText: "${emotion["label"]} ile ilgili kisa bir not yaz...",
              filled: true,
              fillColor: Colors.grey.shade50,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final goodCurrent = List.generate(
      emotions.length,
          (i) => emotions[i]["type"] == "good" ? emotionLevels[i].round() : 0,
    ).where((e) => e > 0).toList();

    final badCurrent = List.generate(
      emotions.length,
          (i) => emotions[i]["type"] == "bad" ? emotionLevels[i].round() : 0,
    ).where((e) => e > 0).toList();

    final goodPercent = goodCurrent.isEmpty
        ? 0
        : ((goodCurrent.reduce((a, b) => a + b) / goodCurrent.length) * 10)
        .round();

    final badPercent = badCurrent.isEmpty
        ? 0
        : ((badCurrent.reduce((a, b) => a + b) / badCurrent.length) * 10)
        .round();

    return Scaffold(
      appBar: AppBar(
        title: const Text("How do you feel?"),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Current summary",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                Text("Good feelings percentage: $goodPercent%"),
                const SizedBox(height: 6),
                Text("Bad feelings percentage: $badPercent%"),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              itemCount: emotions.length,
              itemBuilder: (context, i) => _emotionCard(i),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: isSaving ? null : _saveFeelingData,
                child: Text(isSaving ? "Saving..." : "Save feelings"),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
