import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

enum TripFactBasis {
  userConfirmed,
  generalKnowledge,
  planningSuggestion,
  needsVerification;

  String get wireName => switch (this) {
    userConfirmed => 'user_confirmed',
    generalKnowledge => 'general_knowledge',
    planningSuggestion => 'planning_suggestion',
    needsVerification => 'needs_verification',
  };

  static TripFactBasis fromWire(Object? value) => values.firstWhere(
    (item) => item.wireName == value,
    orElse: () => TripFactBasis.planningSuggestion,
  );
}

final class TripStop {
  const TripStop({
    required this.name,
    required this.time,
    required this.durationMinutes,
    required this.summary,
    this.guideScript = '',
    this.visitTips = const [],
    this.basis = TripFactBasis.planningSuggestion,
    this.fixed = false,
    this.completed = false,
  });

  final String name;
  final String time;
  final int durationMinutes;
  final String summary;
  final String guideScript;
  final List<String> visitTips;
  final TripFactBasis basis;
  final bool fixed;
  final bool completed;

  TripStop copyWith({
    String? name,
    String? time,
    int? durationMinutes,
    String? summary,
    String? guideScript,
    List<String>? visitTips,
    TripFactBasis? basis,
    bool? fixed,
    bool? completed,
  }) => TripStop(
    name: name ?? this.name,
    time: time ?? this.time,
    durationMinutes: durationMinutes ?? this.durationMinutes,
    summary: summary ?? this.summary,
    guideScript: guideScript ?? this.guideScript,
    visitTips: visitTips ?? this.visitTips,
    basis: basis ?? this.basis,
    fixed: fixed ?? this.fixed,
    completed: completed ?? this.completed,
  );

  Map<String, Object> toJson() => {
    'name': name,
    'time': time,
    'durationMinutes': durationMinutes,
    'summary': summary,
    'guideScript': guideScript,
    'visitTips': visitTips,
    'basis': basis.wireName,
    'fixed': fixed,
    'completed': completed,
  };

  factory TripStop.fromJson(Map<String, Object?> json) => TripStop(
    name: _requiredString(json, 'name'),
    time: _requiredString(json, 'time'),
    durationMinutes: _boundedInt(json, 'durationMinutes', min: 5, max: 480),
    summary: _requiredString(json, 'summary'),
    guideScript: (json['guideScript'] as String?)?.trim() ?? '',
    visitTips: _stringList(json['visitTips']),
    basis: TripFactBasis.fromWire(json['basis']),
    fixed: json['fixed'] as bool? ?? false,
    completed: json['completed'] as bool? ?? false,
  );
}

final class TripPlan {
  const TripPlan({
    required this.title,
    required this.destination,
    required this.date,
    required this.stops,
    this.summary = '',
    this.assumptions = const [],
    this.verificationItems = const [],
    this.currentIndex = 0,
    this.promptVersion = '',
  });

  final String title;
  final String destination;
  final String date;
  final String summary;
  final List<String> assumptions;
  final List<String> verificationItems;
  final List<TripStop> stops;
  final int currentIndex;
  final String promptVersion;

  bool get isEmpty => stops.isEmpty;

  TripPlan copyWith({
    String? title,
    String? destination,
    String? date,
    String? summary,
    List<String>? assumptions,
    List<String>? verificationItems,
    List<TripStop>? stops,
    int? currentIndex,
    String? promptVersion,
  }) => TripPlan(
    title: title ?? this.title,
    destination: destination ?? this.destination,
    date: date ?? this.date,
    summary: summary ?? this.summary,
    assumptions: assumptions ?? this.assumptions,
    verificationItems: verificationItems ?? this.verificationItems,
    stops: stops ?? this.stops,
    currentIndex: currentIndex ?? this.currentIndex,
    promptVersion: promptVersion ?? this.promptVersion,
  );

  Map<String, Object> toJson() => {
    'title': title,
    'destination': destination,
    'date': date,
    'summary': summary,
    'assumptions': assumptions,
    'verificationItems': verificationItems,
    'currentIndex': currentIndex,
    'promptVersion': promptVersion,
    'stops': stops.map((stop) => stop.toJson()).toList(),
  };

  factory TripPlan.fromJson(Map<String, Object?> json) {
    final stops = (json['stops'] as List? ?? const [])
        .map((item) => TripStop.fromJson((item as Map).cast<String, Object?>()))
        .toList();
    if (stops.length > 12) {
      throw const FormatException('A trip may contain at most 12 stops');
    }
    final rawIndex = json['currentIndex'] as int? ?? 0;
    return TripPlan(
      title: _requiredString(json, 'title'),
      destination:
          (json['destination'] as String?)?.trim() ??
          (json['title'] as String).trim(),
      date: (json['date'] as String?)?.trim() ?? '',
      summary: (json['summary'] as String?)?.trim() ?? '',
      assumptions: _stringList(json['assumptions']),
      verificationItems: _stringList(json['verificationItems']),
      currentIndex: stops.isEmpty ? 0 : rawIndex.clamp(0, stops.length - 1),
      promptVersion: (json['promptVersion'] as String?)?.trim() ?? '',
      stops: stops,
    );
  }

  static const empty = TripPlan(
    title: '',
    destination: '',
    date: '',
    stops: [],
  );

  static const demo = TripPlan(
    title: '只有河南 · 一日路线',
    destination: '只有河南 · 戏剧幻城',
    date: '2026-10-03',
    summary: '围绕三场已确认演出安排的一日路线。',
    promptVersion: 'legacy-demo',
    verificationItems: ['出发前按门票或现场公告重新核对演出时间。'],
    stops: [
      TripStop(
        name: '入口与夯土墙',
        time: '10:00',
        durationMinutes: 20,
        summary: '先熟悉园区方向，观察建筑与黄土地景观。',
      ),
      TripStop(
        name: '李家村剧场',
        time: '10:40',
        durationMinutes: 70,
        summary: '从普通人的命运进入河南近代历史。',
        fixed: true,
        basis: TripFactBasis.userConfirmed,
      ),
      TripStop(
        name: '火车站剧场',
        time: '13:20',
        durationMinutes: 60,
        summary: '围绕迁徙、离别与归乡感受时代记忆。',
        fixed: true,
        basis: TripFactBasis.userConfirmed,
      ),
      TripStop(
        name: '幻城剧场',
        time: '15:30',
        durationMinutes: 80,
        summary: '观看核心剧目，建议提前确认当日演出时间。',
        fixed: true,
        basis: TripFactBasis.userConfirmed,
      ),
      TripStop(
        name: '麦田与夜景',
        time: '18:00',
        durationMinutes: 40,
        summary: '放慢节奏回顾全天内容，并根据体力自由调整。',
      ),
    ],
  );
}

final class ConfirmedEvent {
  const ConfirmedEvent({required this.name, required this.time});
  final String name;
  final String time;

  Map<String, String> toJson() => {'name': name, 'time': time};
}

enum TripPace {
  relaxed('轻松'),
  balanced('适中'),
  packed('尽量多看');

  const TripPace(this.label);
  final String label;
}

final class TripRequest {
  const TripRequest({
    required this.destination,
    required this.date,
    required this.arrivalTime,
    required this.departureTime,
    required this.pace,
    this.companion = '成人',
    this.confirmedEvents = const [],
    this.notes = '',
  });

  final String destination;
  final String date;
  final String arrivalTime;
  final String departureTime;
  final TripPace pace;
  final String companion;
  final List<ConfirmedEvent> confirmedEvents;
  final String notes;

  Map<String, Object> toJson() => {
    'destination': destination,
    'date': date,
    'arrival_time': arrivalTime,
    'departure_time': departureTime,
    'pace': pace.label,
    'companion': companion,
    'confirmed_events': confirmedEvents.map((event) => event.toJson()).toList(),
    'notes': notes,
  };
}

final class TripPlanStore {
  static const _key = 'offlineTripPlanV1';

  Future<TripPlan> load() async {
    final raw = (await SharedPreferences.getInstance()).getString(_key);
    if (raw == null) return TripPlan.empty;
    try {
      return TripPlan.fromJson(
        (jsonDecode(raw) as Map).cast<String, Object?>(),
      );
    } catch (_) {
      return TripPlan.empty;
    }
  }

  Future<void> save(TripPlan plan) async {
    await (await SharedPreferences.getInstance()).setString(
      _key,
      jsonEncode(plan.toJson()),
    );
  }
}

String _requiredString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('Trip field "$key" is required');
  }
  return value.trim();
}

int _boundedInt(
  Map<String, Object?> json,
  String key, {
  required int min,
  required int max,
}) {
  final value = json[key];
  if (value is! num || value.toInt() < min || value.toInt() > max) {
    throw FormatException('Trip field "$key" must be between $min and $max');
  }
  return value.toInt();
}

List<String> _stringList(Object? value) {
  if (value == null) return const [];
  if (value is! List) throw const FormatException('Expected a string list');
  return value
      .whereType<String>()
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}
