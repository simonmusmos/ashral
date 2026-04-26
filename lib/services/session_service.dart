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

  static Future<Map<String, dynamic>> getSessionDetail(
      String sessionId) async {
    final userId = UserService.instance.userId;
    final response = await http.get(
      Uri.parse('$kBackendUrl/sessions/$sessionId?userId=$userId'),
      headers: {'Content-Type': 'application/json'},
    );
    debugPrint(
        'SessionService.getSessionDetail: ${response.statusCode} → ${response.body}');
    if (response.statusCode != 200) {
      throw Exception('Server returned ${response.statusCode}');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    // Accept both { "session": {...} } and the object directly
    return (body['session'] as Map<String, dynamic>?) ?? body;
  }

  static Future<List<Map<String, dynamic>>> fetchSessionOutput(
      String sessionId, {
    int limit = 200,
  }) async {
    final response = await http.get(
      Uri.parse('$kBackendUrl/sessions/$sessionId/output?limit=$limit'),
      headers: {'Content-Type': 'application/json'},
    );
    debugPrint(
        'SessionService.fetchSessionOutput: ${response.statusCode} → ${response.body.length} bytes');
    if (response.statusCode == 404) {
      final body = jsonDecode(response.body) as Map<String, dynamic>?;
      final code = body?['code'] as String?;
      if (code == 'SESSION_EXPIRED') throw Exception('Session expired');
      throw Exception('Session not found');
    }
    if (response.statusCode != 200) {
      throw Exception('Server returned ${response.statusCode}');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final chunks = body['chunks'] as List<dynamic>? ?? [];
    return chunks.cast<Map<String, dynamic>>();
  }

  static Future<String> resolveShortId(String shortId) async {
    final response = await http.get(
      Uri.parse('$kBackendUrl/sessions/short/$shortId'),
      headers: {'Content-Type': 'application/json'},
    );
    if (response.statusCode == 404) {
      throw Exception('Session not found. Check the code and try again.');
    }
    if (response.statusCode != 200) {
      throw Exception('Server returned ${response.statusCode}');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return body['sessionId'] as String;
  }

  static Future<void> respondToAction({
    required String sessionId,
    required String action,
  }) async {
    final userId = UserService.instance.userId;
    final response = await http.post(
      Uri.parse('$kBackendUrl/sessions/$sessionId/respond'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'userId': userId, 'action': action}),
    );
    if (response.statusCode != 200 && response.statusCode != 204) {
      throw Exception(
          'Server returned ${response.statusCode}: ${response.body}');
    }
  }

}
