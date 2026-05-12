import 'package:flutter/material.dart';

class ProfileScreen extends StatefulWidget {
  final String email;

  final String? name;
  final String? birthday;
  final String? gender;
  final String? location;

  // 🔥 EKLENDİ: update callback
  final Function(Map<String, dynamic>) onProfileUpdated;

  const ProfileScreen({
    super.key,
    required this.email,
    required this.onProfileUpdated,
    this.name,
    this.birthday,
    this.gender,
    this.location,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late TextEditingController nameCtrl;
  late TextEditingController birthdayCtrl;
  late TextEditingController genderCtrl;
  late TextEditingController locationCtrl;

  @override
  void initState() {
    super.initState();

    nameCtrl = TextEditingController(text: widget.name ?? '');
    birthdayCtrl = TextEditingController(text: widget.birthday ?? '');
    genderCtrl = TextEditingController(text: widget.gender ?? '');
    locationCtrl = TextEditingController(text: widget.location ?? '');
  }

  @override
  void dispose() {
    nameCtrl.dispose();
    birthdayCtrl.dispose();
    genderCtrl.dispose();
    locationCtrl.dispose();
    super.dispose();
  }

  void _saveProfile() {
    final updatedData = {
      "name": nameCtrl.text.trim(),
      "birthday": birthdayCtrl.text.trim(),
      "gender": genderCtrl.text.trim(),
      "location": locationCtrl.text.trim(),
    };

    // 🔥 MAIN NAVIGATION'A GÖNDER
    widget.onProfileUpdated(updatedData);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Profile updated')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Your Name',
                border: OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 12),

            TextField(
              controller: birthdayCtrl,
              decoration: const InputDecoration(
                labelText: 'Birthday',
                border: OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 12),

            TextField(
              controller: genderCtrl,
              decoration: const InputDecoration(
                labelText: 'Gender',
                border: OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 12),

            TextField(
              controller: locationCtrl,
              decoration: const InputDecoration(
                labelText: 'Location',
                border: OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 20),

            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _saveProfile,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.greenAccent.shade100,
                ),
                child: const Text(
                  'Save',
                  style: TextStyle(color: Colors.black),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}