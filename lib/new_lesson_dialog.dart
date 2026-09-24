import 'dart:math';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'google_calendar_sync_service.dart';
import 'scheduling_service.dart';

const _subjects = [
  'Matemática',
  'Física',
  'Química',
  'Biologia',
  'Ciências',
  'Português',
  'História',
  'Geografia',
  'Inglês',
];

Future<int?> showNewLessonDialog(BuildContext context) {
  return showDialog<int>(
    context: context,
    builder: (_) => const _NewLessonDialog(),
  );
}

class _NewLessonDialog extends StatefulWidget {
  const _NewLessonDialog();

  @override
  State<_NewLessonDialog> createState() => _NewLessonDialogState();
}

class _NewLessonDialogState extends State<_NewLessonDialog> {
  final _supabase = Supabase.instance.client;
  final _calendar = GoogleCalendarSyncService.instance;
  final _scheduling = SchedulingService.instance;
  final _newSubjectController = TextEditingController();

  List<String> _students = [];
  List<_PackageOption> _packages = [];
  List<String> _topics = [];
  String? _student;
  _PackageOption? _package;
  String _subject = 'Química';
  String? _topic;
  DateTime _firstDate = DateTime.now();
  TimeOfDay _singleTime = const TimeOfDay(hour: 14, minute: 0);
  bool _recurring = false;
  int _quantity = 1;
  List<_WeeklySlot> _weeklySlots = [];
  bool _loading = true;
  bool _saving = false;

  static const _weekdayNames = {
    DateTime.monday: 'Segunda-feira',
    DateTime.tuesday: 'Terça-feira',
    DateTime.wednesday: 'Quarta-feira',
    DateTime.thursday: 'Quinta-feira',
    DateTime.friday: 'Sexta-feira',
    DateTime.saturday: 'Sábado',
    DateTime.sunday: 'Domingo',
  };

  @override
  void initState() {
    super.initState();
    _weeklySlots = [
      _WeeklySlot(
        weekday: _firstDate.weekday,
        hour: _singleTime.hour,
        minute: _singleTime.minute,
      ),
    ];
    _initialize();
  }

  @override
  void dispose() {
    _newSubjectController.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    try {
      final response = await _supabase
          .from('alunos')
          .select('nome')
          .order('nome');
      _students = response
          .map<String>((item) => item['nome'].toString())
          .toList();
      _student = _students.isEmpty ? null : _students.first;
      await _loadPackages();
      await _loadTopics();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao preparar agendamento: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  DateTime? _parseDate(dynamic value) {
    final parts = value?.toString().split('/') ?? const [];
    if (parts.length != 3) return null;
    final day = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final year = int.tryParse(parts[2]);
    if (day == null || month == null || year == null) return null;
    return DateTime(year, month, day);
  }

  Future<void> _loadPackages() async {
    if (_student == null) return;
    final results = await Future.wait([
      _supabase.from('pacotes_professor').select().eq('ativo', true),
      _supabase.from('pacotes_comprados').select().eq('aluno', _student!),
      _supabase.from('aulas').select().eq('aluno', _student!),
    ]);
    final definitions = List<Map<String, dynamic>>.from(results[0]);
    final purchases = List<Map<String, dynamic>>.from(results[1]);
    final lessons = List<Map<String, dynamic>>.from(results[2]);
    final definitionsByName = {
      for (final item in definitions)
        item['nome_pacote']?.toString() ?? '': item,
    };
    final options = <_PackageOption>[];

    for (final definition in definitions) {
      final quantity = int.tryParse(definition['qtd_aulas'].toString()) ?? 1;
      if (quantity != 1) continue;
      options.add(
        _PackageOption(
          name: definition['nome_pacote'].toString(),
          duration: int.tryParse(definition['duracao_min'].toString()) ?? 60,
          available: 50,
          total: 1,
          value: double.tryParse(definition['valor_total'].toString()) ?? 0,
        ),
      );
    }

    for (final purchase in purchases) {
      if (purchase['status_pacote']?.toString() == 'Cancelado') continue;
      final name = purchase['pacote']?.toString() ?? 'Pacote';
      final definition = definitionsByName[name];
      final total =
          int.tryParse(purchase['qtd_aulas_total']?.toString() ?? '') ??
          int.tryParse(definition?['qtd_aulas']?.toString() ?? '') ??
          0;
      final start = _parseDate(purchase['data_inicio']);
      final end = _parseDate(purchase['data_fim']);
      final linked = lessons.where((lesson) {
        if (lesson['pacote_compra_id'] != null) {
          return lesson['pacote_compra_id'].toString() ==
              purchase['id'].toString();
        }
        if (lesson['pacote']?.toString() != name) return false;
        final date = _parseDate(lesson['data_aula']);
        if (date == null) return false;
        if (start != null && date.isBefore(start)) return false;
        if (end != null && date.isAfter(end)) return false;
        return true;
      });
      final allocated = linked.where((lesson) {
        return const [
          'Agendada',
          'Realizada',
          'Falta sem Aviso',
        ].contains(lesson['status_aula']);
      }).length;
      final available = (total - allocated).clamp(0, total).toInt();
      if (available <= 0) continue;
      options.add(
        _PackageOption(
          name: name,
          purchaseId: purchase['id'],
          duration:
              int.tryParse(purchase['duracao_min']?.toString() ?? '') ??
              int.tryParse(definition?['duracao_min']?.toString() ?? '') ??
              60,
          available: available,
          total: total,
          value: double.tryParse(purchase['valor_total'].toString()) ?? 0,
          end: end,
        ),
      );
    }

    if (!mounted) return;
    setState(() {
      _packages = options;
      _package = options.isEmpty ? null : options.first;
      _quantity = 1;
    });
  }

  Future<void> _loadTopics() async {
    final response = await _supabase
        .from('topicos')
        .select('assunto')
        .eq('disciplina', _subject);
    final topics = response
        .map<String>((item) => item['assunto'].toString())
        .toList();
    if (!mounted) return;
    setState(() {
      _topics = topics;
      _topic = topics.isEmpty ? null : topics.first;
    });
  }

  List<DateTime> _generateDates() {
    if (!_recurring) {
      return [
        DateTime(
          _firstDate.year,
          _firstDate.month,
          _firstDate.day,
          _singleTime.hour,
          _singleTime.minute,
        ),
      ];
    }

    final result = <DateTime>[];
    var day = DateTime(_firstDate.year, _firstDate.month, _firstDate.day);
    var guard = 0;
    while (result.length < _quantity && guard < 740) {
      final slots = _weeklySlots.where((item) => item.weekday == day.weekday);
      for (final slot in slots) {
        final date = DateTime(
          day.year,
          day.month,
          day.day,
          slot.hour,
          slot.minute,
        );
        if (!date.isBefore(_firstDate) && result.length < _quantity) {
          result.add(date);
        }
      }
      day = day.add(const Duration(days: 1));
      guard++;
    }
    result.sort();
    return result;
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

  String _dateLabel(DateTime date) {
    return '${_scheduling.formatDate(date)} às '
        '${_scheduling.formatTime(date)}';
  }

  Future<bool> _confirmPreview(List<DateTime> dates) async {
    return await showDialog<bool>(
          context: context,
          builder: (previewContext) => AlertDialog(
            title: Text(
              dates.length == 1
                  ? 'Confirmar aula'
                  : 'Confirmar ${dates.length} aulas',
            ),
            content: SizedBox(
              width: 480,
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: dates.length,
                itemBuilder: (_, index) => ListTile(
                  dense: true,
                  leading: CircleAvatar(
                    radius: 14,
                    child: Text('${index + 1}'),
                  ),
                  title: Text(_dateLabel(dates[index])),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(previewContext, false),
                child: const Text('Voltar e corrigir'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(previewContext, true),
                child: const Text('Confirmar agendamento'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _showConflicts(List<LessonConflict> conflicts) async {
    await showDialog<void>(
      context: context,
      builder: (conflictContext) => AlertDialog(
        title: const Text('Horários indisponíveis'),
        content: SizedBox(
          width: 500,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: conflicts.length,
            itemBuilder: (_, index) {
              final conflict = conflicts[index];
              return ListTile(
                leading: const Icon(Icons.event_busy, color: Colors.red),
                title: Text(_dateLabel(conflict.requested.start)),
                subtitle: Text(
                  'Conflita com ${conflict.existing['aluno'] ?? 'outra aula'} '
                  'às ${conflict.existing['horario'] ?? ''}.',
                ),
              );
            },
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(conflictContext),
            child: const Text('Corrigir horários'),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    if (_student == null || _package == null || _saving) return;
    if (_recurring && _weeklySlots.isEmpty) return;
    setState(() => _saving = true);
    try {
      final dates = _generateDates();
      if (dates.length != (_recurring ? _quantity : 1)) {
        throw Exception('Não foi possível montar todas as datas.');
      }
      final slots = dates
          .map(
            (date) => LessonSlot(
              start: date,
              durationMinutes: _package!.duration,
              label: _student,
            ),
          )
          .toList();
      final conflicts = await _scheduling.findConflicts(slots);
      if (conflicts.isNotEmpty) {
        if (mounted) await _showConflicts(conflicts);
        return;
      }
      if (!mounted || !await _confirmPreview(dates)) return;

      final seriesId = dates.length > 1 ? _uuid() : null;
      final records = dates
          .map(
            (date) => {
              'aluno': _student,
              'pacote': _package!.name,
              'pacote_compra_id': _package!.purchaseId,
              'duracao_min': _package!.duration,
              'serie_id': seriesId,
              'disciplina': _subject,
              'data_aula': _scheduling.formatDate(date),
              'horario': _scheduling.formatTime(date),
              'assunto': _topic ?? 'Geral',
              'status_aula': 'Agendada',
              'google_sync_status': 'pendente',
              'google_sync_action': 'upsert',
            },
          )
          .toList();
      final response = await _supabase.from('aulas').insert(records).select();
      final created = List<Map<String, dynamic>>.from(response);

      if (_package!.purchaseId == null) {
        await _supabase
            .from('cobrancas')
            .insert(
              dates
                  .map(
                    (date) => {
                      'aluno': _student,
                      'descricao':
                          'Aula Avulsa $_subject (${_scheduling.formatDate(date)}) '
                          '- $_student',
                      'valor': _package!.value,
                      'vencimento': DateTime.now().toIso8601String().substring(
                        0,
                        10,
                      ),
                      'status': 'Pendente',
                    },
                  )
                  .toList(),
            );
      }

      var syncFailures = 0;
      for (final lesson in created) {
        try {
          await _calendar.syncLesson(lesson);
        } catch (_) {
          syncFailures++;
        }
      }
      if (!mounted) return;
      Navigator.pop(context, created.length);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${created.length} aula(s) agendada(s). '
            '${syncFailures == 0 ? 'Google Agenda atualizado.' : '$syncFailures sincronização(ões) pendente(s).'}',
          ),
          duration: const Duration(seconds: 6),
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erro ao agendar: $error')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickSlotTime(int index) async {
    final slot = _weeklySlots[index];
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: slot.hour, minute: slot.minute),
    );
    if (picked == null) return;
    setState(() {
      _weeklySlots[index] = slot.copyWith(
        hour: picked.hour,
        minute: picked.minute,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final maxQuantity = _package?.available ?? 1;
    return AlertDialog(
      title: const Text('Agendar aula'),
      content: SizedBox(
        width: 560,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_students.isEmpty)
                      const Text('Cadastre um aluno antes de agendar.')
                    else
                      DropdownButtonFormField<String>(
                        value: _student,
                        decoration: const InputDecoration(labelText: 'Aluno'),
                        items: _students
                            .map(
                              (item) => DropdownMenuItem(
                                value: item,
                                child: Text(item),
                              ),
                            )
                            .toList(),
                        onChanged: (value) async {
                          setState(() => _student = value);
                          await _loadPackages();
                        },
                      ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<_PackageOption>(
                      value: _package,
                      decoration: const InputDecoration(
                        labelText: 'Pacote ou aula avulsa',
                      ),
                      items: _packages
                          .map(
                            (item) => DropdownMenuItem(
                              value: item,
                              child: Text(item.label),
                            ),
                          )
                          .toList(),
                      onChanged: (value) => setState(() {
                        _package = value;
                        _quantity = 1;
                      }),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: _subject,
                      decoration: const InputDecoration(
                        labelText: 'Disciplina',
                      ),
                      items: _subjects
                          .map(
                            (item) => DropdownMenuItem(
                              value: item,
                              child: Text(item),
                            ),
                          )
                          .toList(),
                      onChanged: (value) async {
                        if (value == null) return;
                        setState(() => _subject = value);
                        await _loadTopics();
                      },
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: _topic,
                      decoration: const InputDecoration(labelText: 'Assunto'),
                      items: _topics
                          .map(
                            (item) => DropdownMenuItem(
                              value: item,
                              child: Text(item),
                            ),
                          )
                          .toList(),
                      onChanged: (value) => setState(() => _topic = value),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _newSubjectController,
                            decoration: const InputDecoration(
                              labelText: 'Cadastrar novo assunto',
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () async {
                            final topic = _newSubjectController.text.trim();
                            if (topic.isEmpty) return;
                            await _supabase.from('topicos').insert({
                              'disciplina': _subject,
                              'assunto': topic,
                            });
                            _newSubjectController.clear();
                            await _loadTopics();
                            setState(() => _topic = topic);
                          },
                          icon: const Icon(Icons.add_circle),
                        ),
                      ],
                    ),
                    const Divider(height: 24),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Agendar várias aulas fixas'),
                      subtitle: const Text(
                        'Repete semanalmente nos dias e horários escolhidos.',
                      ),
                      value: _recurring,
                      onChanged: (value) => setState(() => _recurring = value),
                    ),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _firstDate,
                          firstDate: DateTime.now(),
                          lastDate: DateTime.now().add(
                            const Duration(days: 730),
                          ),
                        );
                        if (picked != null) {
                          setState(() => _firstDate = picked);
                        }
                      },
                      icon: const Icon(Icons.calendar_month),
                      label: Text(
                        '${_recurring ? 'A partir de' : 'Data'}: '
                        '${_scheduling.formatDate(_firstDate)}',
                      ),
                    ),
                    if (!_recurring) ...[
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: () async {
                          final picked = await showTimePicker(
                            context: context,
                            initialTime: _singleTime,
                          );
                          if (picked != null) {
                            setState(() => _singleTime = picked);
                          }
                        },
                        icon: const Icon(Icons.access_time),
                        label: Text('Horário: ${_singleTime.format(context)}'),
                      ),
                    ] else ...[
                      const SizedBox(height: 10),
                      DropdownButtonFormField<int>(
                        value: _quantity.clamp(1, maxQuantity).toInt(),
                        decoration: const InputDecoration(
                          labelText: 'Quantidade de aulas',
                        ),
                        items: List.generate(maxQuantity, (index) => index + 1)
                            .map(
                              (item) => DropdownMenuItem(
                                value: item,
                                child: Text('$item aula(s)'),
                              ),
                            )
                            .toList(),
                        onChanged: (value) =>
                            setState(() => _quantity = value ?? 1),
                      ),
                      const SizedBox(height: 8),
                      ...List.generate(_weeklySlots.length, (index) {
                        final slot = _weeklySlots[index];
                        return Card(
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: Row(
                              children: [
                                Expanded(
                                  child: DropdownButton<int>(
                                    isExpanded: true,
                                    value: slot.weekday,
                                    items: _weekdayNames.entries
                                        .map(
                                          (entry) => DropdownMenuItem(
                                            value: entry.key,
                                            child: Text(entry.value),
                                          ),
                                        )
                                        .toList(),
                                    onChanged: (value) => setState(() {
                                      _weeklySlots[index] = slot.copyWith(
                                        weekday: value,
                                      );
                                    }),
                                  ),
                                ),
                                TextButton(
                                  onPressed: () => _pickSlotTime(index),
                                  child: Text(
                                    '${slot.hour.toString().padLeft(2, '0')}:'
                                    '${slot.minute.toString().padLeft(2, '0')}',
                                  ),
                                ),
                                if (_weeklySlots.length > 1)
                                  IconButton(
                                    onPressed: () => setState(
                                      () => _weeklySlots.removeAt(index),
                                    ),
                                    icon: const Icon(Icons.remove_circle),
                                  ),
                              ],
                            ),
                          ),
                        );
                      }),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () => setState(() {
                            _weeklySlots.add(
                              _WeeklySlot(
                                weekday: (_weeklySlots.last.weekday % 7) + 1,
                                hour: _weeklySlots.last.hour,
                                minute: _weeklySlots.last.minute,
                              ),
                            );
                          }),
                          icon: const Icon(Icons.add),
                          label: const Text('Adicionar outro dia fixo'),
                        ),
                      ),
                    ],
                    if (_package != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          'Duração: ${_package!.duration} min • '
                          'Disponíveis para agendar: ${_package!.available}',
                        ),
                      ),
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        ElevatedButton.icon(
          onPressed: _loading || _saving || _student == null || _package == null
              ? null
              : _save,
          icon: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.preview),
          label: const Text('Revisar e agendar'),
        ),
      ],
    );
  }
}

class _PackageOption {
  const _PackageOption({
    required this.name,
    required this.duration,
    required this.available,
    required this.total,
    required this.value,
    this.purchaseId,
    this.end,
  });

  final String name;
  final dynamic purchaseId;
  final int duration;
  final int available;
  final int total;
  final double value;
  final DateTime? end;

  String get label =>
      purchaseId == null ? name : '$name • $available aula(s) para agendar';
}

class _WeeklySlot {
  const _WeeklySlot({
    required this.weekday,
    required this.hour,
    required this.minute,
  });

  final int weekday;
  final int hour;
  final int minute;

  _WeeklySlot copyWith({int? weekday, int? hour, int? minute}) {
    return _WeeklySlot(
      weekday: weekday ?? this.weekday,
      hour: hour ?? this.hour,
      minute: minute ?? this.minute,
    );
  }
}
