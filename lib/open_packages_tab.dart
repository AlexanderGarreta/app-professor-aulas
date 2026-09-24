import 'dart:math';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'google_calendar_sync_service.dart';
import 'scheduling_service.dart';

class OpenPackagesTab extends StatefulWidget {
  const OpenPackagesTab({super.key});

  @override
  State<OpenPackagesTab> createState() => _OpenPackagesTabState();
}

class _OpenPackagesTabState extends State<OpenPackagesTab> {
  final _supabase = Supabase.instance.client;
  final _scheduling = SchedulingService.instance;
  final _calendar = GoogleCalendarSyncService.instance;
  final _searchController = TextEditingController();
  List<_PackageCycle> _cycles = [];
  List<Map<String, dynamic>> _todayLessons = [];
  int _lateCharges = 0;
  bool _loading = true;
  String _filter = 'Todos';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  DateTime? _date(dynamic value) {
    final text = value?.toString() ?? '';
    final parts = text.split('/');
    if (parts.length == 3) {
      final day = int.tryParse(parts[0]);
      final month = int.tryParse(parts[1]);
      final year = int.tryParse(parts[2]);
      if (day != null && month != null && year != null) {
        return DateTime(year, month, day);
      }
    }
    return DateTime.tryParse(text);
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      await _scheduling.completePastLessons();
      final results = await Future.wait([
        _supabase.from('pacotes_comprados').select(),
        _supabase.from('pacotes_professor').select(),
        _supabase.from('aulas').select(),
        _supabase.from('cobrancas').select(),
      ]);
      final purchases = List<Map<String, dynamic>>.from(results[0]);
      final definitions = List<Map<String, dynamic>>.from(results[1]);
      final lessons = List<Map<String, dynamic>>.from(results[2]);
      final charges = List<Map<String, dynamic>>.from(results[3]);
      final definitionByName = {
        for (final item in definitions)
          item['nome_pacote']?.toString() ?? '': item,
      };
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final cycles = <_PackageCycle>[];

      for (final purchase in purchases) {
        if (purchase['status_pacote']?.toString() == 'Cancelado') continue;
        final id = purchase['id'];
        final student = purchase['aluno']?.toString() ?? 'Aluno';
        final packageName = purchase['pacote']?.toString() ?? 'Pacote';
        final start = _date(purchase['data_inicio']);
        final end = _date(purchase['data_fim']);
        final definition = definitionByName[packageName];
        final total =
            int.tryParse(purchase['qtd_aulas_total']?.toString() ?? '') ??
            int.tryParse(definition?['qtd_aulas']?.toString() ?? '') ??
            0;

        final cycleLessons =
            lessons.where((lesson) {
              final linkedId = lesson['pacote_compra_id'];
              if (linkedId != null) return linkedId.toString() == id.toString();
              if (lesson['aluno']?.toString() != student ||
                  lesson['pacote']?.toString() != packageName) {
                return false;
              }
              final lessonDate = _date(lesson['data_aula']);
              if (lessonDate == null) return false;
              if (start != null && lessonDate.isBefore(start)) return false;
              if (end != null && lessonDate.isAfter(end)) return false;
              return true;
            }).toList()..sort((a, b) {
              final aStart = _scheduling.parseLessonStart(a);
              final bStart = _scheduling.parseLessonStart(b);
              if (aStart == null || bStart == null) return 0;
              return aStart.compareTo(bStart);
            });

        final completed = cycleLessons
            .where((item) => item['status_aula'] == 'Realizada')
            .length;
        final absences = cycleLessons
            .where((item) => item['status_aula'] == 'Falta sem Aviso')
            .length;
        final scheduled = cycleLessons
            .where((item) => item['status_aula'] == 'Agendada')
            .length;
        final consumed = completed + absences;
        final remaining = (total - consumed).clamp(0, total).toInt();
        final available = (total - consumed - scheduled)
            .clamp(0, total)
            .toInt();
        if (remaining <= 0) continue;

        final cycleCharges = charges.where((charge) {
          if (charge['pacote_compra_id'] != null) {
            return charge['pacote_compra_id'].toString() == id.toString();
          }
          final description = charge['descricao']?.toString() ?? '';
          return charge['aluno']?.toString() == student &&
              description.contains(packageName);
        }).toList();
        final paymentPending = cycleCharges.any(
          (charge) => charge['status']?.toString() != 'Pago',
        );
        final nextLessons = cycleLessons.where((lesson) {
          final lessonStart = _scheduling.parseLessonStart(lesson);
          return lesson['status_aula'] == 'Agendada' &&
              lessonStart != null &&
              !lessonStart.isBefore(now);
        }).toList();

        cycles.add(
          _PackageCycle(
            raw: purchase,
            student: student,
            name: packageName,
            start: start,
            end: end,
            total: total,
            completed: completed,
            absences: absences,
            scheduled: scheduled,
            remaining: remaining,
            availableToSchedule: available,
            paymentPending: paymentPending,
            lessons: cycleLessons,
            nextLesson: nextLessons.isEmpty ? null : nextLessons.first,
          ),
        );
      }

      cycles.sort((a, b) {
        if (a.end == null && b.end == null) return 0;
        if (a.end == null) return 1;
        if (b.end == null) return -1;
        return a.end!.compareTo(b.end!);
      });

      final lateCharges = charges.where((charge) {
        if (charge['status']?.toString() == 'Pago') return false;
        final due = _date(charge['vencimento']);
        return due != null && due.isBefore(today);
      }).length;
      final todayLessons = lessons.where((lesson) {
        final date = _date(lesson['data_aula']);
        return date == today && lesson['status_aula'] == 'Agendada';
      }).toList();

      if (!mounted) return;
      setState(() {
        _cycles = cycles;
        _lateCharges = lateCharges;
        _todayLessons = todayLessons;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao carregar pacotes: $error')),
      );
    }
  }

  List<_PackageCycle> get _filteredCycles {
    final now = DateTime.now();
    final search = _searchController.text.trim().toLowerCase();
    return _cycles.where((cycle) {
      if (search.isNotEmpty &&
          !cycle.student.toLowerCase().contains(search) &&
          !cycle.name.toLowerCase().contains(search)) {
        return false;
      }
      switch (_filter) {
        case 'Acabando':
          return cycle.remaining <= 2;
        case 'Vencendo':
          return cycle.end != null &&
              !cycle.end!.isBefore(now) &&
              cycle.end!.difference(now).inDays <= 7;
        case 'Vencidos':
          return cycle.end != null && cycle.end!.isBefore(now);
        default:
          return true;
      }
    }).toList();
  }

  String _shortDate(DateTime? date) {
    if (date == null) return '-';
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  Future<void> _showLessons(_PackageCycle cycle) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('${cycle.student} • ${cycle.name}'),
        content: SizedBox(
          width: 600,
          child: cycle.lessons.isEmpty
              ? const Text('Nenhuma aula vinculada a este ciclo.')
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: cycle.lessons.length,
                  itemBuilder: (_, index) {
                    final lesson = cycle.lessons[index];
                    final automatic = lesson['confirmacao_automatica'] == true;
                    return ListTile(
                      dense: true,
                      leading: Icon(
                        lesson['status_aula'] == 'Realizada'
                            ? Icons.check_circle
                            : lesson['status_aula'] == 'Falta sem Aviso'
                            ? Icons.person_off
                            : Icons.event,
                        color: lesson['status_aula'] == 'Realizada'
                            ? Colors.green
                            : lesson['status_aula'] == 'Falta sem Aviso'
                            ? Colors.red
                            : Colors.indigo,
                      ),
                      title: Text(
                        '${lesson['data_aula']} às ${lesson['horario']}',
                      ),
                      subtitle: Text(
                        '${lesson['disciplina'] ?? ''} • '
                        '${lesson['status_aula']}'
                        '${automatic ? ' (automática)' : ''}',
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }

  String _uuid() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    String hex(int value) => value.toRadixString(16).padLeft(2, '0');
    final text = bytes.map(hex).join();
    return '${text.substring(0, 8)}-${text.substring(8, 12)}-'
        '${text.substring(12, 16)}-${text.substring(16, 20)}-'
        '${text.substring(20)}';
  }

  Future<void> _renewCycle(_PackageCycle cycle) async {
    final todayRaw = DateTime.now();
    final today = DateTime(todayRaw.year, todayRaw.month, todayRaw.day);
    final proposedStart = cycle.end == null
        ? today
        : cycle.end!.add(const Duration(days: 1)).isAfter(today)
        ? cycle.end!.add(const Duration(days: 1))
        : today;
    final cycleDays = cycle.start != null && cycle.end != null
        ? cycle.end!.difference(cycle.start!).inDays
        : 30;
    final proposedEnd = proposedStart.add(Duration(days: cycleDays));
    final duration =
        int.tryParse(cycle.raw['duracao_min']?.toString() ?? '') ??
        (cycle.lessons.isEmpty
            ? 60
            : await _scheduling.lessonDuration(cycle.lessons.first));

    final fixedLessons = cycle.lessons
        .where((lesson) => lesson['serie_id'] != null)
        .toList();
    final patterns = <String, ({int weekday, int hour, int minute})>{};
    for (final lesson in fixedLessons) {
      final start = _scheduling.parseLessonStart(lesson);
      if (start == null) continue;
      patterns['${start.weekday}-${start.hour}-${start.minute}'] = (
        weekday: start.weekday,
        hour: start.hour,
        minute: start.minute,
      );
    }

    final dates = <DateTime>[];
    if (patterns.isNotEmpty) {
      var day = proposedStart;
      var guard = 0;
      while (dates.length < cycle.total && guard < 740) {
        for (final pattern in patterns.values) {
          if (pattern.weekday != day.weekday || dates.length >= cycle.total) {
            continue;
          }
          dates.add(
            DateTime(
              day.year,
              day.month,
              day.day,
              pattern.hour,
              pattern.minute,
            ),
          );
        }
        day = day.add(const Duration(days: 1));
        guard++;
      }
      dates.sort();
      final conflicts = await _scheduling.findConflicts(
        dates
            .map(
              (date) => LessonSlot(
                start: date,
                durationMinutes: duration,
                label: cycle.student,
              ),
            )
            .toList(),
      );
      if (conflicts.isNotEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Renovação não criada: ${conflicts.length} horário(s) fixo(s) '
              'estão ocupados. Ajuste esses horários pela Agenda.',
            ),
            duration: const Duration(seconds: 7),
          ),
        );
        return;
      }
    }

    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Renovar pacote de ${cycle.student}'),
        content: Text(
          '${cycle.name}\n'
          'Novo ciclo: ${_shortDate(proposedStart)} a '
          '${_shortDate(proposedEnd)}\n'
          'Quantidade: ${cycle.total} aulas\n\n'
          '${dates.isEmpty ? 'O pacote será criado sem aulas agendadas.' : '${dates.length} aulas manterão os dias e horários fixos do ciclo anterior.'}\n\n'
          'As duas cobranças de 50% também serão criadas.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Confirmar renovação'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final value =
          double.tryParse(cycle.raw['valor_total']?.toString() ?? '') ?? 0;
      final purchase = await _supabase
          .from('pacotes_comprados')
          .insert({
            'aluno': cycle.student,
            'pacote': cycle.name,
            'data_inicio': _scheduling.formatDate(proposedStart),
            'data_fim': _scheduling.formatDate(proposedEnd),
            'valor_total': value,
            'qtd_aulas_total': cycle.total,
            'duracao_min': duration,
            'status_pacote': 'Aberto',
          })
          .select()
          .single();
      await _supabase.from('cobrancas').insert([
        {
          'aluno': cycle.student,
          'descricao': 'Sinal 50% - ${cycle.name} (${cycle.student})',
          'valor': value / 2,
          'vencimento': proposedStart.toIso8601String().substring(0, 10),
          'status': 'Pendente',
          'pacote_compra_id': purchase['id'],
        },
        {
          'aluno': cycle.student,
          'descricao': 'Quitação 50% - ${cycle.name} (${cycle.student})',
          'valor': value / 2,
          'vencimento': proposedEnd.toIso8601String().substring(0, 10),
          'status': 'Pendente',
          'pacote_compra_id': purchase['id'],
        },
      ]);

      if (dates.isNotEmpty) {
        final template = fixedLessons.first;
        final seriesId = _uuid();
        final created = await _supabase
            .from('aulas')
            .insert(
              dates
                  .map(
                    (date) => {
                      'aluno': cycle.student,
                      'pacote': cycle.name,
                      'pacote_compra_id': purchase['id'],
                      'duracao_min': duration,
                      'serie_id': seriesId,
                      'disciplina': template['disciplina'] ?? 'Geral',
                      'assunto': template['assunto'] ?? 'Geral',
                      'data_aula': _scheduling.formatDate(date),
                      'horario': _scheduling.formatTime(date),
                      'status_aula': 'Agendada',
                      'google_sync_status': 'pendente',
                      'google_sync_action': 'upsert',
                    },
                  )
                  .toList(),
            )
            .select();
        for (final raw in created) {
          try {
            await _calendar.syncLesson(Map<String, dynamic>.from(raw));
          } catch (_) {}
        }
      }
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pacote renovado com sucesso.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erro ao renovar pacote: $error')));
    }
  }

  Widget _summaryCard(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          child: Column(
            children: [
              Icon(icon, color: color),
              const SizedBox(height: 4),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(label, textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final nearEnd = _cycles.where((cycle) => cycle.remaining <= 2).length;
    final cycles = _filteredCycles;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(10),
        children: [
          Row(
            children: [
              _summaryCard(
                'Aulas hoje',
                '${_todayLessons.length}',
                Icons.today,
                Colors.indigo,
              ),
              _summaryCard(
                'Pacotes acabando',
                '$nearEnd',
                Icons.hourglass_bottom,
                Colors.orange,
              ),
              _summaryCard(
                'Cobranças atrasadas',
                '$_lateCharges',
                Icons.warning_amber,
                Colors.red,
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _searchController,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              labelText: 'Buscar aluno ou pacote',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: ['Todos', 'Acabando', 'Vencendo', 'Vencidos']
                  .map(
                    (filter) => Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(filter),
                        selected: _filter == filter,
                        onSelected: (_) => setState(() => _filter = filter),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
          const SizedBox(height: 6),
          if (cycles.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: Text('Nenhum pacote neste filtro.')),
            )
          else
            ...cycles.map((cycle) {
              final progress = cycle.total > 0
                  ? ((cycle.completed + cycle.absences) / cycle.total)
                        .clamp(0.0, 1.0)
                        .toDouble()
                  : 0.0;
              final expired =
                  cycle.end != null && cycle.end!.isBefore(DateTime.now());
              return Card(
                margin: const EdgeInsets.symmetric(vertical: 6),
                child: InkWell(
                  onTap: () => _showLessons(cycle),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                cycle.student,
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            if (expired)
                              const Chip(
                                label: Text('Vencido'),
                                backgroundColor: Color(0xffffdddd),
                              )
                            else if (cycle.remaining <= 2)
                              const Chip(
                                label: Text('Acabando'),
                                backgroundColor: Color(0xffffedcc),
                              ),
                          ],
                        ),
                        Text(cycle.name),
                        Text(
                          'Ciclo: ${_shortDate(cycle.start)} a '
                          '${_shortDate(cycle.end)}',
                        ),
                        const SizedBox(height: 10),
                        LinearProgressIndicator(value: progress),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 14,
                          runSpacing: 4,
                          children: [
                            Text('Realizadas: ${cycle.completed}'),
                            Text('Faltas: ${cycle.absences}'),
                            Text('Agendadas: ${cycle.scheduled}'),
                            Text('Restantes: ${cycle.remaining}'),
                            Text(
                              'Faltam agendar: ${cycle.availableToSchedule}',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: cycle.availableToSchedule > 0
                                    ? Colors.orange.shade800
                                    : Colors.green.shade700,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          cycle.nextLesson == null
                              ? 'Próxima aula: não agendada'
                              : 'Próxima aula: '
                                    '${cycle.nextLesson!['data_aula']} às '
                                    '${cycle.nextLesson!['horario']}',
                        ),
                        Text(
                          cycle.paymentPending
                              ? 'Pagamento: pendente'
                              : 'Pagamento: em dia',
                          style: TextStyle(
                            color: cycle.paymentPending
                                ? Colors.red
                                : Colors.green,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton.icon(
                              onPressed: () => _renewCycle(cycle),
                              icon: const Icon(Icons.autorenew),
                              label: const Text('Renovar'),
                            ),
                            const SizedBox(width: 6),
                            const Text('Toque no cartão para ver as aulas'),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}

class _PackageCycle {
  const _PackageCycle({
    required this.raw,
    required this.student,
    required this.name,
    required this.start,
    required this.end,
    required this.total,
    required this.completed,
    required this.absences,
    required this.scheduled,
    required this.remaining,
    required this.availableToSchedule,
    required this.paymentPending,
    required this.lessons,
    required this.nextLesson,
  });

  final Map<String, dynamic> raw;
  final String student;
  final String name;
  final DateTime? start;
  final DateTime? end;
  final int total;
  final int completed;
  final int absences;
  final int scheduled;
  final int remaining;
  final int availableToSchedule;
  final bool paymentPending;
  final List<Map<String, dynamic>> lessons;
  final Map<String, dynamic>? nextLesson;
}
