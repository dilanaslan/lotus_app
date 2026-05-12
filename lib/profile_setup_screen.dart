import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ProfileSetupScreen extends StatefulWidget {
  final String email;
  final String? name;
  final String? birthday;
  final String? gender;
  final String? location;

  const ProfileSetupScreen({
    super.key,
    required this.email,
    this.name,
    this.birthday,
    this.gender,
    this.location,
  });

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  final nameCtrl = TextEditingController();
  final birthdayCtrl = TextEditingController();
  final genderCtrl = TextEditingController();
  final locationCtrl = TextEditingController();
  final newHobbyCtrl = TextEditingController();

  bool isSaving = false;

  List<Map<String, dynamic>> hobbies = [
    {'title': 'Reading', 'rating': 1},
    {'title': 'Knitting', 'rating': 2},
    {'title': 'Growing Flowers', 'rating': 4},
  ];

  static const String baseUrl = 'http://10.0.2.2:8000';

  @override
  void initState() {
    super.initState();
    nameCtrl.text = widget.name ?? '';
    birthdayCtrl.text = widget.birthday ?? '';
    genderCtrl.text = widget.gender ?? '';
    locationCtrl.text = widget.location ?? '';
  }

  @override
  void dispose() {
    nameCtrl.dispose();
    birthdayCtrl.dispose();
    genderCtrl.dispose();
    locationCtrl.dispose();
    newHobbyCtrl.dispose();
    super.dispose();
  }

  void _showAddHobby() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Hobby'),
        content: TextField(
          controller: newHobbyCtrl,
          decoration: const InputDecoration(hintText: 'Hobby name'),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              newHobbyCtrl.clear();
            },
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final text = newHobbyCtrl.text.trim();
              if (text.isNotEmpty) {
                setState(() {
                  hobbies.add({'title': text, 'rating': 0});
                });
              }
              Navigator.pop(ctx);
              newHobbyCtrl.clear();
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  Future<void> _saveProfileToPrefs(Map<String, dynamic> profile) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('profiles_by_email');

    Map<String, dynamic> allProfiles = {};
    if (raw != null && raw.isNotEmpty) {
      allProfiles = Map<String, dynamic>.from(jsonDecode(raw));
    }

    allProfiles[widget.email] = profile;

    await prefs.setString('profiles_by_email', jsonEncode(allProfiles));
    await prefs.setString('last_login_email', widget.email);
  }

  Future<void> _sendProfileToBackend(Map<String, dynamic> profile) async {
    final response = await http
        .post(
      Uri.parse('$baseUrl/save-profile'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(profile),
    )
        .timeout(const Duration(seconds: 5));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Profile save failed: ${response.statusCode} ${response.body}',
      );
    }
  }

  Future<void> _saveProfile() async {
    if (isSaving) return;

    setState(() {
      isSaving = true;
    });

    final updatedData = <String, dynamic>{
      "email": widget.email,
      "name": nameCtrl.text.trim(),
      "birthday": birthdayCtrl.text.trim(),
      "gender": genderCtrl.text.trim(),
      "location": locationCtrl.text.trim(),
      "hobbies": hobbies,
      "savedAt": DateTime.now().toIso8601String(),
    };

    try {
      await _saveProfileToPrefs(updatedData);

      try {
        await _sendProfileToBackend(updatedData);
      } catch (e) {
        debugPrint('Profile backend save error: $e');
      }

      if (!mounted) return;
      Navigator.pop(context, updatedData);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Kayit hatasi: $e")),
      );
    } finally {
      if (mounted) {
        setState(() {
          isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Your Profile'),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _field('Your Name', nameCtrl),
            _field('Your Birthday', birthdayCtrl),
            _field('Your Gender', genderCtrl),
            _field('Where you live?', locationCtrl),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: const [
                Text(
                  'Your Hobbies',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  'Enjoyment level',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...hobbies.map((h) => _hobbyRow(h)),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: _showAddHobby,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  vertical: 12,
                  horizontal: 14,
                ),
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: const [
                    Icon(Icons.edit, size: 18),
                    SizedBox(width: 10),
                    Text('Add new hobby'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 30),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: isSaving ? null : _saveProfile,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.greenAccent,
                ),
                child: Text(
                  isSaving ? 'Saving...' : 'Save',
                  style: const TextStyle(color: Colors.black),
                ),
              ),
            ),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  Widget _field(String label, TextEditingController ctrl) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: TextField(
        controller: ctrl,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  Widget _hobbyRow(Map<String, dynamic> h) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(child: Text(h['title'])),
          Row(
            children: List.generate(5, (index) {
              final filled = index < (h['rating'] as int);
              return IconButton(
                icon: Icon(
                  filled ? Icons.star : Icons.star_border,
                ),
                onPressed: () {
                  setState(() {
                    h['rating'] = index + 1;
                  });
                },
              );
            }),
          ),
        ],
      ),
    );
  }
}

