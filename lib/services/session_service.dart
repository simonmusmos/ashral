import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/constants.dart';
import 'user_service.dart';

class SessionService {
  static Future<List<Map<String, dynamic>>> getSessions() async {
    final userId = UserService.instance.userId;
    try {
      final response = await http.get(
        Uri.parse('$kBackendUrl/users/$userId/sessions'),
        headers: {'Content-Type': 'application/json'},
      );
      debugPrint('SessionService.getSessions: ${response.statusCode} → ${response.body}');
      if (response.statusCode != 200) return [];
      final body = jsonDecode(response.body);
      final list = body['sessions'] as List<dynamic>? ?? [];
      return list.cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('SessionService.getSessions failed: $e');
      return [];
    }
  }

  static Future<void> joinSession({
    required String sessionId,
    String? customName,
  }) async {
    final userId = UserService.instance.userId;

    final response = await http.post(
      Uri.parse('$kBackendUrl/sessions/$sessionId/join'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'userId': userId, 'customName': customName}),
    );

    debugPrint('SessionService.joinSession: ${response.statusCode} → ${response.body}');

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception('Server returned ${response.statusCode}: ${response.body}');
    }
  }

  static Future<void> renameSession(
      String sessionId, String? customName) async {
    final userId = UserService.instance.userId;
    final response = await http.patch(
      Uri.parse('$kBackendUrl/sessions/$sessionId/members/$userId'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'customName': customName}),
    );
    if (response.statusCode != 200 && response.statusCode != 204) {
      throw Exception(
          'Server returned ${response.statusCode}: ${response.body}');
    }
  }

  static Future<void> leaveSession(String sessionId) async {
    final userId = UserService.instance.userId;

    final response = await http.delete(
      Uri.parse('$kBackendUrl/sessions/$sessionId/leave'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'userId': userId}),
    );

    if (response.statusCode != 200 && response.statusCode != 204) {
      throw Exception('Server returned ${response.statusCode}: ${response.body}');
    }
  }

}
