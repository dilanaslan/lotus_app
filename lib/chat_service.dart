import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_config.dart';

class ChatService {
  static Future<String> sendMessage({
    required String email,
    required String message,
  }) async {
    try {
      final response = await http
          .post(
        Uri.parse("${ApiConfig.baseUrl}/chat"),
        headers: {
          "Content-Type": "application/json; charset=UTF-8",
        },
        body: jsonEncode({
          "email": email,
          "text": message,
        }),
      )
          .timeout(const Duration(seconds: 120));

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
