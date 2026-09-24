import 'package:supabase_flutter/supabase_flutter.dart';

class LessonSlot {
  const LessonSlot({
    required this.start,
    required this.durationMinutes,
    this.label,
  });

  final DateTime start;
  final int durationMinutes;
  final String? label;

  DateTime get end => start.add(Duration(minutes: durationMinutes));
}

class LessonConflict {
  const LessonConflict({required this.requested, required this.existing});

  final LessonSlot requested;
  final Map<String, dynamic> existing;
}

class SchedulingService {
  SchedulingService._();

  static final SchedulingService instance = SchedulingService._();
  final SupabaseClient _supabase = Supabase.instance.client;

  DateTime? parseLessonStart(Map<String, dynamic> lesson) {
    final dateParts = lesson['data_aula']?.toString().split('/') ?? const [];
    final timeParts = lesson['horario']?.toString().split(':') ?? const [];
    if (dateParts.length != 3 || timeParts.length < 2) return null;
    final day = int.tryParse(dateParts[0]);
    final month = int.tryParse(dateParts[1]);
    final year = int.tryParse(dateParts[2]);
    final hour = int.tryParse(timeParts[0]);
    final minute = int.tryParse(timeParts[1]);
    if ([day, month, year, hour, minute].contains(null)) return null;
    return DateTime(year!, month!, day!, hour!, minute!);
  }

  String formatDate(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/'
      '${date.month.toString().padLeft(2, '0')}/${date.year}';

  String formatTime(DateTime date) =>
      '${date.hour.toString().padLeft(2, '0')}:'
      '${date.minute.toString().padLeft(2, '0')}';

  Future<int> packageDuration(String? packageName) async {
    if (packageName == null || packageName.isEmpty) return 60;
    try {
      final package = await _supabase
          .from('pacotes_professor')
          .select('duracao_min')
          .eq('nome_pacote', packageName)
          .maybeSingle();
      final duration = int.tryParse(package?['duracao_min']?.toString() ?? '');
      if (duration != null && duration > 0) return duration;
    } catch (_) {}

    final match = RegExp(r'(\d+)h(?:(\d+))?').firstMatch(packageName);
    if (match != null) {
      final hours = int.tryParse(match.group(1) ?? '') ?? 0;
      final minutes = int.tryParse(match.group(2) ?? '') ?? 0;
      if (hours * 60 + minutes > 0) return hours * 60 + minutes;
    }
    return 60;
  }

  Future<int> lessonDuration(Map<String, dynamic> lesson) async {
    final stored = int.tryParse(lesson['duracao_min']?.toString() ?? '');
    if (stored != null && stored > 0) return stored;
    return packageDuration(lesson['pacote']?.toString());
  }

  bool overlaps(LessonSlot first, LessonSlot second) {
    return first.start.isBefore(second.end) && second.start.isBefore(first.end);
  }

  Future<List<LessonConflict>> findConflicts(
    List<LessonSlot> requested, {
    int? excludeLessonId,
    Set<dynamic> excludeLessonIds = const {},
  }) async {
    final conflicts = <LessonConflict>[];

    for (var i = 0; i < requested.length; i++) {
      for (var j = i + 1; j < requested.length; j++) {
        if (overlaps(requested[i], requested[j])) {
          conflicts.add(
            LessonConflict(
              requested: requested[j],
              existing: {
                'aluno': requested[i].label ?? 'Outra aula desta sequência',
                'data_aula': formatDate(requested[i].start),
                'horario': formatTime(requested[i].start),
                'duracao_min': requested[i].durationMinutes,
              },
            ),
          );
        }
      }
    }

    final dates = requested.map((slot) => formatDate(slot.start)).toSet();
    for (final date in dates) {
      final response = await _supabase
          .from('aulas')
          .select()
          .eq('data_aula', date)
          .eq('status_aula', 'Agendada');
      for (final raw in response) {
        final existing = Map<String, dynamic>.from(raw);
        if ((excludeLessonId != null && existing['id'] == excludeLessonId) ||
            excludeLessonIds.any(
              (id) => id.toString() == existing['id']?.toString(),
            )) {
          continue;
        }
        final start = parseLessonStart(existing);
        if (start == null) continue;
        final duration = await lessonDuration(existing);
        final existingSlot = LessonSlot(
          start: start,
          durationMinutes: duration,
          label: existing['aluno']?.toString(),
        );
        for (final slot in requested.where(
          (item) => formatDate(item.start) == date,
        )) {
          if (overlaps(slot, existingSlot)) {
            conflicts.add(LessonConflict(requested: slot, existing: existing));
          }
        }
      }
    }
    return conflicts;
  }

  Future<int> completePastLessons() async {
    try {
      final result = await _supabase.rpc('finalizar_aulas_passadas');
      return int.tryParse(result?.toString() ?? '') ?? 0;
    } catch (_) {
      // Compatibilidade enquanto a migração ainda não foi executada.
    }

    final response = await _supabase
        .from('aulas')
        .select()
        .eq('status_aula', 'Agendada');
    var completed = 0;
    for (final raw in response) {
      final lesson = Map<String, dynamic>.from(raw);
      final start = parseLessonStart(lesson);
      if (start == null) continue;
      final duration = await lessonDuration(lesson);
      if (DateTime.now().isBefore(start.add(Duration(minutes: duration)))) {
        continue;
      }
      try {
        await _supabase
            .from('aulas')
            .update({
              'status_aula': 'Realizada',
              'confirmacao_automatica': true,
              'realizada_em': DateTime.now().toIso8601String(),
            })
            .eq('id', lesson['id']);
      } catch (_) {
        await _supabase
            .from('aulas')
            .update({'status_aula': 'Realizada'})
            .eq('id', lesson['id']);
      }
      completed++;
    }
    return completed;
  }

  Future<void> undoAutomaticCompletion(int lessonId) async {
    await _supabase
        .from('aulas')
        .update({
          'status_aula': 'Revisar',
          'confirmacao_automatica': false,
          'realizada_em': null,
        })
        .eq('id', lessonId);
  }
}
