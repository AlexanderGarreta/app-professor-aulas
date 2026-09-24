import 'dart:convert';

import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

class CalendarSyncSummary {
  const CalendarSyncSummary({
    required this.synced,
    required this.deleted,
    required this.failed,
  });

  final int synced;
  final int deleted;
  final int failed;
}

class GoogleCalendarSyncService {
  GoogleCalendarSyncService._();

  static final GoogleCalendarSyncService instance =
      GoogleCalendarSyncService._();

  static const _calendarId = 'primary';
  static const _calendarApi = 'https://www.googleapis.com/calendar/v3';

  final SupabaseClient _supabase = Supabase.instance.client;
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    serverClientId: '908171140799-8gv332dambrnn0l835kej1mdlaoksks1.apps.googleusercontent.com',
    scopes: const ['https://www.googleapis.com/auth/calendar.events'],
  );

  GoogleSignInAccount? get currentUser => _googleSignIn.currentUser;

  Future<GoogleSignInAccount?> restoreSession() async {
    try {
      return _googleSignIn.currentUser ?? await _googleSignIn.signInSilently();
    } catch (_) {
      return null;
    }
  }

  Future<GoogleSignInAccount> connect() async {
    GoogleSignInAccount? account = _googleSignIn.currentUser;
    account ??= await _googleSignIn.signInSilently();
    account ??= await _googleSignIn.signIn();

    if (account == null) {
      throw Exception('Login do Google cancelado.');
    }

    final headers = await account.authHeaders;
    if (headers['Authorization'] == null) {
      throw Exception('Não foi possível autorizar o Google Agenda.');
    }
    return account;
  }

  Future<Map<String, String>> _headers() async {
    final account = await connect();
    final authHeaders = await account.authHeaders;
    final authorization = authHeaders['Authorization'];
    if (authorization == null || authorization.isEmpty) {
      throw Exception('O Google não forneceu um token de acesso.');
    }
    return {'Authorization': authorization, 'Content-Type': 'application/json'};
  }

  DateTime? parseLessonDate(Map<String, dynamic> lesson) {
    final dateText = lesson['data_aula']?.toString();
    final timeText = lesson['horario']?.toString() ?? '00:00';
    if (dateText == null) return null;

    final dateParts = dateText.split('/');
    final timeParts = timeText.split(':');
    if (dateParts.length != 3 || timeParts.length < 2) return null;

    final day = int.tryParse(dateParts[0]);
    final month = int.tryParse(dateParts[1]);
    final year = int.tryParse(dateParts[2]);
    final hour = int.tryParse(timeParts[0]);
    final minute = int.tryParse(timeParts[1]);
    if ([day, month, year, hour, minute].contains(null)) return null;

    return DateTime(year!, month!, day!, hour!, minute!);
  }

  Future<int> lessonDuration(
    String? packageName, {
    dynamic storedDuration,
  }) async {
    final savedMinutes = int.tryParse(storedDuration?.toString() ?? '');
    if (savedMinutes != null && savedMinutes > 0) return savedMinutes;
    if (packageName == null || packageName.isEmpty) return 60;
    try {
      final package = await _supabase
          .from('pacotes_professor')
          .select('duracao_min')
          .eq('nome_pacote', packageName)
          .maybeSingle();
      final minutes = int.tryParse(package?['duracao_min']?.toString() ?? '');
      if (minutes != null && minutes > 0) return minutes;
    } catch (_) {
      // A duração também pode ser inferida do nome do pacote.
    }

    final match = RegExp(r'(\d+)h(?:(\d+))?').firstMatch(packageName);
    if (match != null) {
      final hours = int.tryParse(match.group(1) ?? '') ?? 0;
      final minutes = int.tryParse(match.group(2) ?? '') ?? 0;
      final total = hours * 60 + minutes;
      if (total > 0) return total;
    }
    return 60;
  }

  String _eventTitle(Map<String, dynamic> lesson) {
    final status = lesson['status_aula']?.toString();
    final prefix = status == 'Falta sem Aviso' ? '[FALTA] ' : '';
    return '${prefix}Aula de ${lesson['disciplina'] ?? 'Aula'} - '
        '${lesson['aluno'] ?? ''}';
  }

  void _ensureAccountMatches(
    Map<String, dynamic> lesson,
    GoogleSignInAccount account,
  ) {
    final originalEmail = lesson['google_account_email']?.toString();
    if (originalEmail != null &&
        originalEmail.isNotEmpty &&
        originalEmail.toLowerCase() != account.email.toLowerCase()) {
      throw Exception(
        'Esta aula foi sincronizada com $originalEmail. Conecte essa conta '
        'antes de alterar ou excluir o evento.',
      );
    }
  }

  Future<Map<String, dynamic>> _eventBody(Map<String, dynamic> lesson) async {
    final start = parseLessonDate(lesson);
    if (start == null) {
      throw Exception('Data ou horário da aula inválidos.');
    }
    final duration = await lessonDuration(
      lesson['pacote']?.toString(),
      storedDuration: lesson['duracao_min'],
    );
    final end = start.add(Duration(minutes: duration));
    return {
      'summary': _eventTitle(lesson),
      'description':
          'Assunto: ${lesson['assunto'] ?? 'Geral'} | '
          'Modalidade: ${lesson['pacote'] ?? 'Avulsa'} | '
          'Gerenciado pelo ProfEconomy',
      'start': {
        'dateTime': start.toIso8601String(),
        'timeZone': 'America/Sao_Paulo',
      },
      'end': {
        'dateTime': end.toIso8601String(),
        'timeZone': 'America/Sao_Paulo',
      },
      'extendedProperties': {
        'private': {'profeconomy_aula_id': lesson['id'].toString()},
      },
    };
  }

  Future<void> _setSyncState(
    int lessonId,
    String status, {
    String? eventId,
    String? error,
    String? accountEmail,
  }) async {
    final values = <String, dynamic>{
      'google_sync_status': status,
      'google_sync_error': error,
      'google_synced_at': status == 'sincronizado'
          ? DateTime.now().toIso8601String()
          : null,
    };
    if (eventId != null) values['google_event_id'] = eventId;
    if (accountEmail != null) values['google_account_email'] = accountEmail;
    await _supabase.from('aulas').update(values).eq('id', lessonId);
  }

  Future<List<Map<String, dynamic>>> _listEvents(
    Map<String, String> headers,
    Map<String, String> query,
  ) async {
    final uri = Uri.parse('$_calendarApi/calendars/$_calendarId/events')
        .replace(queryParameters: query);
    final response = await http.get(uri, headers: headers);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Google Agenda recusou a consulta (${response.statusCode}): '
        '${response.body}',
      );
    }
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    return List<Map<String, dynamic>>.from(decoded['items'] ?? const []);
  }

  Future<String?> _findExistingEvent(
    Map<String, dynamic> lesson,
    Map<String, String> headers,
  ) async {
    final lessonId = lesson['id'].toString();

    final tagged = await _listEvents(headers, {
      'privateExtendedProperty': 'profeconomy_aula_id=$lessonId',
      'singleEvents': 'true',
      'maxResults': '10',
    });
    if (tagged.length == 1) return tagged.first['id']?.toString();
    if (tagged.length > 1) {
      throw Exception('Mais de um evento do Google está ligado a esta aula.');
    }

    // Compatibilidade com eventos criados antes de o ProfEconomy guardar o ID.
    final start = parseLessonDate(lesson);
    if (start == null) return null;
    final duration = await lessonDuration(
      lesson['pacote']?.toString(),
      storedDuration: lesson['duracao_min'],
    );
    final end = start.add(Duration(minutes: duration));
    final candidates = await _listEvents(headers, {
      'timeMin': start
          .subtract(const Duration(minutes: 2))
          .toUtc()
          .toIso8601String(),
      'timeMax': end.add(const Duration(minutes: 2)).toUtc().toIso8601String(),
      'singleEvents': 'true',
      'orderBy': 'startTime',
      'maxResults': '10',
      'q': lesson['aluno']?.toString() ?? '',
    });

    final expectedTitle = _eventTitle(lesson).replaceFirst('[FALTA] ', '');
    final matches = candidates.where((event) {
      final rawTitle = event['summary']?.toString();
      final title = rawTitle?.replaceFirst('[FALTA] ', '');
      final startData = event['start'];
      final eventStart = startData is Map
          ? startData['dateTime']?.toString()
          : null;
      final parsedStart = eventStart == null
          ? null
          : DateTime.tryParse(eventStart);
      if (parsedStart == null || title != expectedTitle) return false;
      final localStart = parsedStart.toLocal();
      return localStart.year == start.year &&
          localStart.month == start.month &&
          localStart.day == start.day &&
          localStart.hour == start.hour &&
          localStart.minute == start.minute;
    }).toList();

    if (matches.length == 1) return matches.first['id']?.toString();
    if (matches.length > 1) {
      throw Exception(
        'Foram encontrados eventos duplicados no Google. Revisão necessária.',
      );
    }
    return null;
  }

  Future<String> syncLesson(Map<String, dynamic> lesson) async {
    final lessonId = int.tryParse(lesson['id']?.toString() ?? '');
    if (lessonId == null) throw Exception('Aula sem identificador.');

    await _setSyncState(lessonId, 'sincronizando');
    try {
      final account = await connect();
      _ensureAccountMatches(lesson, account);
      final headers = await _headers();
      final body = await _eventBody(lesson);
      String? eventId = lesson['google_event_id']?.toString();

      if (eventId != null && eventId.isNotEmpty) {
        final uri = Uri.parse(
          '$_calendarApi/calendars/$_calendarId/events/'
          '${Uri.encodeComponent(eventId)}',
        );
        final response = await http.patch(
          uri,
          headers: headers,
          body: jsonEncode(body),
        );
        if (response.statusCode >= 200 && response.statusCode < 300) {
          await _setSyncState(
            lessonId,
            'sincronizado',
            eventId: eventId,
            accountEmail: account.email,
          );
          return eventId;
        }
        if (response.statusCode != 404 && response.statusCode != 410) {
          throw Exception(
            'Google Agenda recusou a atualização '
            '(${response.statusCode}): ${response.body}',
          );
        }
        eventId = null;
      }

      eventId = await _findExistingEvent(lesson, headers);
      if (eventId == null || eventId.isEmpty) {
        final uri = Uri.parse('$_calendarApi/calendars/$_calendarId/events');
        final response = await http.post(
          uri,
          headers: headers,
          body: jsonEncode(body),
        );
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw Exception(
            'Google Agenda recusou o evento '
            '(${response.statusCode}): ${response.body}',
          );
        }
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        eventId = decoded['id']?.toString();
      } else {
        final uri = Uri.parse(
          '$_calendarApi/calendars/$_calendarId/events/'
          '${Uri.encodeComponent(eventId)}',
        );
        final response = await http.patch(
          uri,
          headers: headers,
          body: jsonEncode(body),
        );
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw Exception(
            'Falha ao vincular o evento existente '
            '(${response.statusCode}): ${response.body}',
          );
        }
      }

      if (eventId == null || eventId.isEmpty) {
        throw Exception('O Google não retornou o ID do evento.');
      }

      await _setSyncState(
        lessonId,
        'sincronizado',
        eventId: eventId,
        accountEmail: account.email,
      );
      return eventId;
    } catch (error) {
      await _setSyncState(lessonId, 'erro', error: error.toString());
      rethrow;
    }
  }

  Future<void> deleteLessonEvent(Map<String, dynamic> lesson) async {
    final lessonId = int.tryParse(lesson['id']?.toString() ?? '');
    if (lessonId == null) throw Exception('Aula sem identificador.');

    await _setSyncState(lessonId, 'sincronizando');
    try {
      final account = await connect();
      _ensureAccountMatches(lesson, account);
      final headers = await _headers();
      String? eventId = lesson['google_event_id']?.toString();
      if (eventId == null || eventId.isEmpty) {
        eventId = await _findExistingEvent(lesson, headers);
      }

      if (eventId != null && eventId.isNotEmpty) {
        final uri = Uri.parse(
          '$_calendarApi/calendars/$_calendarId/events/'
          '${Uri.encodeComponent(eventId)}',
        );
        final response = await http.delete(uri, headers: headers);
        if (response.statusCode != 204 &&
            response.statusCode != 404 &&
            response.statusCode != 410) {
          throw Exception(
            'Google Agenda recusou a exclusão '
            '(${response.statusCode}): ${response.body}',
          );
        }
      }

      await _supabase
          .from('aulas')
          .update({
            'google_event_id': null,
            'google_sync_status': 'sincronizado',
            'google_sync_error': null,
            'google_synced_at': DateTime.now().toIso8601String(),
            'google_account_email': account.email,
          })
          .eq('id', lessonId);
    } catch (error) {
      await _setSyncState(lessonId, 'erro', error: error.toString());
      rethrow;
    }
  }

  Future<void> requestLessonDeletion(Map<String, dynamic> lesson) async {
    final lessonId = int.tryParse(lesson['id']?.toString() ?? '');
    if (lessonId == null) throw Exception('Aula sem identificador.');

    final updated = await _supabase
        .from('aulas')
        .update({
          'status_aula': 'Exclusão pendente',
          'google_sync_action': 'delete',
          'google_sync_status': 'pendente',
          'google_sync_error': null,
        })
        .eq('id', lessonId)
        .select()
        .single();

    await deleteLessonEvent(updated);
    await _supabase.from('aulas').delete().eq('id', lessonId);
  }

  Future<CalendarSyncSummary> syncPendingLessons() async {
    final response = await _supabase.from('aulas').select();
    final lessons = List<Map<String, dynamic>>.from(response);
    var synced = 0;
    var deleted = 0;
    var failed = 0;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    for (final lesson in lessons) {
      final action = lesson['google_sync_action']?.toString() ?? 'upsert';
      try {
        if (action == 'delete' ||
            lesson['status_aula'] == 'Exclusão pendente') {
          await deleteLessonEvent(lesson);
          await _supabase.from('aulas').delete().eq('id', lesson['id']);
          deleted++;
          continue;
        }

        final date = parseLessonDate(lesson);
        final isFuture = date != null && !date.isBefore(today);
        final needsSync =
            lesson['google_sync_status'] != 'sincronizado' ||
            lesson['google_event_id'] == null;
        final hasKnownEvent = lesson['google_event_id'] != null;
        final canSync = isFuture || hasKnownEvent;
        if (action == 'upsert' && canSync && needsSync) {
          await syncLesson(lesson);
          synced++;
        }
      } catch (_) {
        failed++;
      }
    }

    return CalendarSyncSummary(
      synced: synced,
      deleted: deleted,
      failed: failed,
    );
  }
}
