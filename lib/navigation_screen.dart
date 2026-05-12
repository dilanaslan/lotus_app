import 'package:flutter/material.dart';
import 'calendar_screen.dart';
import 'home_screen.dart';
import 'chat_screen.dart';
import 'journal_screen.dart';
import 'profile_screen.dart';
import 'feeling_selection_screen.dart';

class MainNavigationScreen extends StatefulWidget {
  final String userName;
  final String email;

  const MainNavigationScreen({
    super.key,
    required this.userName,
    required this.email,
  });

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int currentIndex = 0;

  late String name;
  String? birthday;
  String? gender;
  String? location;

  @override
  void initState() {
    super.initState();
    name = widget.userName;
  }

  void updateProfile(Map<String, dynamic> data) {
    setState(() {
      name = data["name"] ?? name;
      birthday = data["birthday"];
      gender = data["gender"];
      location = data["location"];
    });
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomeScreen(
        name: name,
        email: widget.email,
        onProfileUpdated: updateProfile,
        birthday: birthday,
        gender: gender,
        location: location,
      ),
      EmotionSelectionScreen(email: widget.email),
      CalendarScreen(email: widget.email),
      ChatScreen(email: widget.email),
      JournalScreen(email: widget.email),
      ProfileScreen(
        name: name,
        email: widget.email,
        birthday: birthday,
        gender: gender,
        location: location,
        onProfileUpdated: updateProfile,
      ),
    ];

    return Scaffold(
      body: pages[currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: currentIndex,
        onTap: (i) => setState(() => currentIndex = i),
        type: BottomNavigationBarType.fixed,
        selectedItemColor: Colors.green.shade400,
        unselectedItemColor: Colors.grey,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: ''),
          BottomNavigationBarItem(icon: Icon(Icons.emoji_emotions_outlined), label: ''),
          BottomNavigationBarItem(icon: Icon(Icons.calendar_month_outlined), label: ''),
          BottomNavigationBarItem(icon: Icon(Icons.chat_bubble_outline), label: ''),
          BottomNavigationBarItem(icon: Icon(Icons.book_outlined), label: ''),
          BottomNavigationBarItem(icon: Icon(Icons.person_outline), label: ''),
        ],
      ),
    );
  }
}
