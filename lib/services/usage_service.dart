import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

// ── Data model ────────────────────────────────────────────────────────────────

class UsageLimits {
  final double daily;
  final double weekly;

  const UsageLimits({this.daily = 5.0, this.weekly = 25.0});

  UsageLimits copyWith({double? daily, double? weekly}) =>
      UsageLimits(daily: daily ?? this.daily, weekly: weekly ?? this.weekly);
}

class UsageSummary {
  final double dailySpent;
  final double weeklySpent;
  final UsageLimits limits;

  const UsageSummary({
    required this.dailySpent,
    required this.weeklySpent,
    required this.limits,
  });

  double get dailyPct => limits.daily > 0 ? (dailySpent / limits.daily).clamp(0, 1) : 0;
  double get weeklyPct => limits.weekly > 0 ? (weeklySpent / limits.weekly).clamp(0, 1) : 0;
}

// ── Service ───────────────────────────────────────────────────────────────────

class UsageService {
  static const _keyLimitDaily  = 'budget_daily';
  static const _keyLimitWeekly = 'budget_weekly';
  static const _keyLog         = 'spending_log';

  // Each entry: { sessionId, date (yyyy-MM-dd), cost }
  static List<Map<String, dynamic>> _log = [];
  static UsageLimits _limits = const UsageLimits();
  static bool _loaded = false;

  static Future<void> _ensureLoaded() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    _limits = UsageLimits(
      daily:  prefs.getDouble(_keyLimitDaily)  ?? 5.0,
      weekly: prefs.getDouble(_keyLimitWeekly) ?? 25.0,
    );
    final raw = prefs.getString(_keyLog);
    if (raw != null) {
      try {
        final list = jsonDecode(raw) as List<dynamic>;
        _log = list.cast<Map<String, dynamic>>();
      } catch (_) {}
    }
    _loaded = true;
  }

  static Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyLimitDaily,  _limits.daily);
    await prefs.setDouble(_keyLimitWeekly, _limits.weekly);
    await prefs.setString(_keyLog, jsonEncode(_log));
  }

  // Call whenever the session screen sees an updated cost value.
  static Future<void> recordCost(String sessionId, double cost) async {
    await _ensureLoaded();
    final today = _dateKey(DateTime.now());
    final idx = _log.indexWhere((e) => e['sessionId'] == sessionId);
    if (idx == -1) {
      _log.add({'sessionId': sessionId, 'date': today, 'cost': cost});
    } else {
      _log[idx]['cost'] = cost; // replace with latest cumulative total
    }
    // Keep only last 8 days to cap storage size
    final cutoff = DateTime.now().subtract(const Duration(days: 8));
    _log.removeWhere((e) {
      final d = DateTime.tryParse(e['date'] as String? ?? '');
      return d != null && d.isBefore(cutoff);
    });
    await _save();
  }

  static Future<UsageSummary> getSummary() async {
    await _ensureLoaded();
    final now = DateTime.now();
    final today = _dateKey(now);
    final weekStart = _weekStart(now);

    double daily = 0;
    double weekly = 0;
    for (final entry in _log) {
      final cost = (entry['cost'] as num?)?.toDouble() ?? 0;
      final date = DateTime.tryParse(entry['date'] as String? ?? '');
      if (date == null) continue;
      if (_dateKey(date) == today) daily += cost;
      if (!date.isBefore(weekStart)) weekly += cost;
    }
    return UsageSummary(dailySpent: daily, weeklySpent: weekly, limits: _limits);
  }

  static Future<void> setLimits(UsageLimits limits) async {
    await _ensureLoaded();
    _limits = limits;
    await _save();
  }

  static UsageLimits get currentLimits => _limits;

  static String _dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static DateTime _weekStart(DateTime d) {
    // Monday as start of week
    final weekday = d.weekday; // 1 = Mon
    return DateTime(d.year, d.month, d.day - (weekday - 1));
  }
}
