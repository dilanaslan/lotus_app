import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'api_config.dart';
import 'navigation_screen.dart';
import 'profile_setup_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController emailCtrl = TextEditingController();

  @override
  void dispose() {
    emailCtrl.dispose();
    super.dispose();
  }

  bool isValidEmail(String email) {
    final regex = RegExp(r'^[\w\-.]+@([\w-]+\.)+[\w-]{2,4}$');
    return regex.hasMatch(email);
  }

  Future<Map<String, dynamic>?> _getSavedProfile(String email) async {
    final localProfile = await _getSavedProfileFromDevice(email);
    if (localProfile != null) return localProfile;

    return _getSavedProfileFromBackend(email);
  }

  Future<Map<String, dynamic>?> _getSavedProfileFromDevice(String email) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('profiles_by_email');

    if (raw == null || raw.isEmpty) return null;

    final Map<String, dynamic> allProfiles =
    Map<String, dynamic>.from(jsonDecode(raw));

    final profile = allProfiles[email];
    if (profile == null) return null;

    return Map<String, dynamic>.from(profile);
  }

  Future<Map<String, dynamic>?> _getSavedProfileFromBackend(String email) async {
    try {
      final url = Uri.parse(
        '${ApiConfig.baseUrl}/user-memory?email=${Uri.encodeComponent(email)}',
      );
      final response = await http.get(url).timeout(const Duration(seconds: 20));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return null;
      }

      final data = jsonDecode(utf8.decode(response.bodyBytes));
      final profile = data['profile'];
      if (profile == null) return null;

      final profileMap = Map<String, dynamic>.from(profile);

      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('profiles_by_email');
      Map<String, dynamic> allProfiles = {};
      if (raw != null && raw.isNotEmpty) {
        allProfiles = Map<String, dynamic>.from(jsonDecode(raw));
      }
      allProfiles[email] = profileMap;
      await prefs.setString('profiles_by_email', jsonEncode(allProfiles));

      return profileMap;
    } catch (_) {
      return null;
    }
  }

  Future<void> _continueWithEmail() async {
    final email = emailCtrl.text.trim();

    if (!isValidEmail(email)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Geçerli bir e-mail girin')),
      );
      return;
    }

    final savedProfile = await _getSavedProfile(email);

    if (!mounted) return;

    if (savedProfile != null) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => MainNavigationScreen(
            userName: (savedProfile["name"] ?? "").toString().trim().isEmpty
                ? "User"
                : savedProfile["name"],
            email: email,
          ),
        ),
      );
      return;
    }

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProfileSetupScreen(email: email),
      ),
    );

    if (!mounted) return;

    if (result != null) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => MainNavigationScreen(
            userName: result["name"]?.toString().trim().isEmpty ?? true
                ? "User"
                : result["name"],
            email: email,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 30),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: 10),
                SizedBox(
                  height: 140,
                  child: Image.asset('assets/lotus.png'),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Lotus',
                  style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Create an account',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Enter your email to sign up for this app',
                  style: TextStyle(color: Colors.black54),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    hintText: 'email@domain.com',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 16,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _continueWithEmail,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black,
                    ),
                    child: const Text(
                      'Continue',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: const [
                    Expanded(child: Divider()),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Text('or'),
                    ),
                    Expanded(child: Divider()),
                  ],
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: OutlinedButton.icon(
                    icon: Image.asset('assets/google.png', height: 20),
                    label: const Text('Continue with Google'),
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Google auth: demo')),
                      );
                    },
                    style: OutlinedButton.styleFrom(
                      backgroundColor: Colors.grey.shade100,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: OutlinedButton.icon(
                    icon: Image.asset('assets/apple.png', height: 20),
                    label: const Text('Continue with Apple'),
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Apple auth: demo')),
                      );
                    },
                    style: OutlinedButton.styleFrom(
                      backgroundColor: Colors.grey.shade100,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
