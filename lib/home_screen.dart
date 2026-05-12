import 'package:flutter/material.dart';

import 'calendar_screen.dart';
import 'chat_screen.dart';
import 'feeling_selection_screen.dart';
import 'journal_screen.dart';
import 'profile_setup_screen.dart';

class HomeScreen extends StatefulWidget {
  final String name;
  final String email;
  final Function(Map<String, dynamic>) onProfileUpdated;
  final String? birthday;
  final String? gender;
  final String? location;

  const HomeScreen({
    super.key,
    required this.name,
    required this.email,
    required this.onProfileUpdated,
    this.birthday,
    this.gender,
    this.location,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late String name;

  @override
  void initState() {
    super.initState();
    name = widget.name;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Welcome back, $name 🌿'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _menuButton(context, 'Chat with Lotus'),
            _menuButton(context, 'Write your journal'),
            _menuButton(context, 'Select your feelings'),
            _menuButton(context, 'View your calendar'),
            _menuButton(context, 'Update your profile'),
          ],
        ),
      ),
    );
  }

  Widget _menuButton(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: InkWell(
        onTap: () async {
          if (text == 'Chat with Lotus') {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => ChatScreen(email: widget.email),
              ),
            );
          } else if (text == 'Write your journal') {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => JournalScreen(email: widget.email),
              ),
            );
          } else if (text == 'Select your feelings') {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => EmotionSelectionScreen(email: widget.email),
              ),
            );
          } else if (text == 'View your calendar') {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => CalendarScreen(email: widget.email),
              ),
            );
          } else if (text == 'Update your profile') {
            final result = await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ProfileSetupScreen(
                  email: widget.email,
                  name: name,
                  birthday: widget.birthday,
                  gender: widget.gender,
                  location: widget.location,
                ),
              ),
            );

            if (result != null) {
              setState(() {
                name = result["name"] ?? name;
              });
              widget.onProfileUpdated(result);
            }
          }
        },
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Text(text),
        ),
      ),
    );
  }
}
