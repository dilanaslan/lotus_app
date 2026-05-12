import 'dart:convert';

import 'package:http/http.dart' as http;

class ChatService {
  static const String baseUrl = "http://10.0.2.2:8000";

  static Future<String> sendMessage({
    required String email,
    required String message,
  }) async {
    try {
      final response = await http
          .post(
        Uri.parse("$baseUrl/chat"),
        headers: {
          "Content-Type": "application/json; charset=UTF-8",
        },
        body: jsonEncode({
          "email": email,
          "text": message,
        }),
      )
          .timeout(const Duration(seconds: 2000));

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        return data["response"] ?? "Yanit alinamadi.";
      }

      return "Sunucu hatasi: ${response.statusCode} ${utf8.decode(response.bodyBytes)}";
    } catch (e) {
      return "Baglanti hatasi: Sunucu acik mi? ($e)";
    }
  }
}
