import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'api_config.dart';

class CalendarScreen extends StatefulWidget {
  final String email;

  const CalendarScreen({
    super.key,
    required this.email,
  });

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  DateTime visibleMonth = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime selectedDate = DateTime.now();
  Map<String, List<Map<String, dynamic>>> journalsByDay = {};
  Map<String, List<Map<String, dynamic>>> feelingsByDay = {};
  bool isLoading = true;

  String get _journalKey => 'journal_entries_${widget.email}';
  String get _feelingKey => 'feeling_entries_${widget.email}';

  @override
  void initState() {
    super.initState();
    _loadCalendarData();
  }

  Future<void> _loadCalendarData() async {
    setState(() {
      isLoading = true;
    });

    final localJournals = await _loadJournalEntriesFromDevice();
    final localFeelings = await _loadFeelingEntriesFromDevice();

    try {
      final backendData = await _loadCalendarDataFromBackend();
      _setCalendarEntries(
        _mergeEntries(localJournals, backendData.journals),
        _mergeEntries(localFeelings, backendData.feelings),
      );
    } catch (_) {
      _setCalendarEntries(localJournals, localFeelings);
    }
  }

  Future<CalendarData> _loadCalendarDataFromBackend() async {
    final journalsUrl = Uri.parse(
      '${ApiConfig.baseUrl}/journals?email=${Uri.encodeComponent(widget.email)}',
    );
    final feelingsUrl = Uri.parse(
      '${ApiConfig.baseUrl}/feelings?email=${Uri.encodeComponent(widget.email)}',
    );

    final responses = await Future.wait([
      http.get(journalsUrl).timeout(const Duration(seconds: 20)),
      http.get(feelingsUrl).timeout(const Duration(seconds: 20)),
    ]);

    final journalsResponse = responses[0];
    final feelingsResponse = responses[1];

    if (journalsResponse.statusCode < 200 ||
        journalsResponse.statusCode >= 300 ||
        feelingsResponse.statusCode < 200 ||
        feelingsResponse.statusCode >= 300) {
      throw Exception('Calendar backend request failed');
    }

    final journalsBody = jsonDecode(utf8.decode(journalsResponse.bodyBytes));
    final feelingsBody = jsonDecode(utf8.decode(feelingsResponse.bodyBytes));

    final journalEntries = List<Map<String, dynamic>>.from(
      (journalsBody['journals'] ?? []).map(
        (entry) => Map<String, dynamic>.from(entry),
      ),
    );
    final feelingEntries = List<Map<String, dynamic>>.from(
      (feelingsBody['feelings'] ?? []).map(
        (entry) => Map<String, dynamic>.from(entry),
      ),
    );

    return CalendarData(
      journals: journalEntries,
      feelings: feelingEntries,
    );
  }

  Future<List<Map<String, dynamic>>> _loadJournalEntriesFromDevice() async {
    final prefs = await SharedPreferences.getInstance();
    final journalRaw = prefs.getString(_journalKey);

    if (journalRaw == null || journalRaw.isEmpty) return [];

    return List<Map<String, dynamic>>.from(
      jsonDecode(journalRaw).map((entry) => Map<String, dynamic>.from(entry)),
    );
  }

  Future<List<Map<String, dynamic>>> _loadFeelingEntriesFromDevice() async {
    final prefs = await SharedPreferences.getInstance();
    final feelingRaw = prefs.getString(_feelingKey);

    if (feelingRaw == null || feelingRaw.isEmpty) return [];

    return List<Map<String, dynamic>>.from(
      jsonDecode(feelingRaw).map((entry) => Map<String, dynamic>.from(entry)),
    );
  }

  List<Map<String, dynamic>> _mergeEntries(
    List<Map<String, dynamic>> localEntries,
    List<Map<String, dynamic>> backendEntries,
  ) {
    final merged = <String, Map<String, dynamic>>{};

    for (final entry in backendEntries) {
      merged[_entryIdentity(entry)] = entry;
    }

    for (final entry in localEntries) {
      merged[_entryIdentity(entry)] = entry;
    }

    return merged.values.toList();
  }

  String _entryIdentity(Map<String, dynamic> entry) {
    final date = entry['date']?.toString() ?? '';
    final text = entry['text']?.toString() ?? '';
    final goodPercent = entry['goodPercent']?.toString() ?? '';
    final badPercent = entry['badPercent']?.toString() ?? '';
    return '$date|$text|$goodPercent|$badPercent';
  }

  void _setCalendarEntries(
    List<Map<String, dynamic>> journalEntries,
    List<Map<String, dynamic>> feelingEntries,
  ) {
    final nextJournals = <String, List<Map<String, dynamic>>>{};
    final nextFeelings = <String, List<Map<String, dynamic>>>{};

    for (final entry in journalEntries) {
      final key = _dayKeyFromIso(entry['date']?.toString());
      if (key == null) continue;
      nextJournals.putIfAbsent(key, () => []).add(entry);
    }

    for (final entry in feelingEntries) {
      final key = _dayKeyFromIso(entry['date']?.toString());
      if (key == null) continue;
      nextFeelings.putIfAbsent(key, () => []).add(entry);
    }

    if (!mounted) return;
    setState(() {
      journalsByDay = nextJournals;
      feelingsByDay = nextFeelings;
      isLoading = false;
    });
  }

  String? _dayKeyFromIso(String? iso) {
    if (iso == null || iso.isEmpty) return null;

    try {
      return _dayKey(DateTime.parse(iso).toLocal());
    } catch (_) {
      return null;
    }
  }

  String _dayKey(DateTime date) {
    final local = date.toLocal();
    final year = local.year.toString().padLeft(4, '0');
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  List<DateTime?> _calendarDays() {
    final firstDay = DateTime(visibleMonth.year, visibleMonth.month);
    final totalDays = DateTime(visibleMonth.year, visibleMonth.month + 1, 0).day;
    final emptyDays = firstDay.weekday - 1;
    final cells = <DateTime?>[];

    for (int i = 0; i < emptyDays; i++) {
      cells.add(null);
    }

    for (int day = 1; day <= totalDays; day++) {
      cells.add(DateTime(visibleMonth.year, visibleMonth.month, day));
    }

    while (cells.length % 7 != 0) {
      cells.add(null);
    }

    return cells;
  }

  void _changeMonth(int amount) {
    setState(() {
      visibleMonth = DateTime(visibleMonth.year, visibleMonth.month + amount);
    });
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  String _formatMonth(DateTime date) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];

    return '${months[date.month - 1]} ${date.year}';
  }

  String _formatSelectedDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    final selectedKey = _dayKey(selectedDate);
    final selectedJournals = journalsByDay[selectedKey] ?? [];
    final selectedFeelings = feelingsByDay[selectedKey] ?? [];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Calendar'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadCalendarData,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildMonthHeader(),
                  const SizedBox(height: 12),
                  _buildCalendarGrid(),
                  const SizedBox(height: 20),
                  Text(
                    _formatSelectedDate(selectedDate),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (selectedJournals.isEmpty && selectedFeelings.isEmpty)
                    _emptyState()
                  else ...[
                    for (final feeling in selectedFeelings)
                      _feelingCard(feeling),
                    for (final journal in selectedJournals)
                      _journalCard(journal),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _buildMonthHeader() {
    return Row(
      children: [
        IconButton(
          onPressed: () => _changeMonth(-1),
          icon: const Icon(Icons.chevron_left),
        ),
        Expanded(
          child: Center(
            child: Text(
              _formatMonth(visibleMonth),
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        IconButton(
          onPressed: () => _changeMonth(1),
          icon: const Icon(Icons.chevron_right),
        ),
      ],
    );
  }

  Widget _buildCalendarGrid() {
    const weekDays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final days = _calendarDays();

    return Column(
      children: [
        Row(
          children: weekDays
              .map(
                (day) => Expanded(
                  child: Center(
                    child: Text(
                      day,
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 8),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: days.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
          ),
          itemBuilder: (context, index) {
            final day = days[index];
            if (day == null) return const SizedBox.shrink();

            final key = _dayKey(day);
            final hasJournal = journalsByDay.containsKey(key);
            final hasFeeling = feelingsByDay.containsKey(key);
            final isSelected = _isSameDay(day, selectedDate);
            final isToday = _isSameDay(day, DateTime.now());

            return InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () {
                setState(() {
                  selectedDate = day;
                });
              },
              child: Container(
                decoration: BoxDecoration(
                  color: isSelected ? Colors.green.shade400 : Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isToday ? Colors.green : Colors.grey.shade300,
                    width: isToday ? 2 : 1,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '${day.day}',
                      style: TextStyle(
                        color: isSelected ? Colors.white : Colors.black,
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (hasFeeling)
                          _dot(
                            isSelected ? Colors.white : Colors.green,
                          ),
                        if (hasFeeling && hasJournal)
                          const SizedBox(width: 3),
                        if (hasJournal)
                          _dot(
                            isSelected ? Colors.white : Colors.orange,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _dot(Color color) {
    return Container(
      width: 6,
      height: 6,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
    );
  }

  Widget _emptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Text('No feelings or journal entries saved for this day.'),
    );
  }

  Widget _feelingCard(Map<String, dynamic> feeling) {
    final emotions = List<Map<String, dynamic>>.from(
      (feeling['emotions'] ?? []).map(
        (emotion) => Map<String, dynamic>.from(emotion),
      ),
    );

    final notedEmotions = emotions
        .where((emotion) => (emotion['note'] ?? '').toString().isNotEmpty)
        .toList();

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Feelings',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text('Good: ${feeling['goodPercent'] ?? 0}%'),
          Text('Bad: ${feeling['badPercent'] ?? 0}%'),
          if (notedEmotions.isNotEmpty) ...[
            const SizedBox(height: 10),
            for (final emotion in notedEmotions.take(5))
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  '${emotion['emoji']} ${emotion['label']} (${emotion['level']}/10): ${emotion['note']}',
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _journalCard(Map<String, dynamic> journal) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Journal',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(journal['text'] ?? ''),
        ],
      ),
    );
  }
}

class CalendarData {
  final List<Map<String, dynamic>> journals;
  final List<Map<String, dynamic>> feelings;

  CalendarData({
    required this.journals,
    required this.feelings,
  });
}
