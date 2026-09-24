import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'google_calendar_sync_service.dart';
import 'new_lesson_dialog.dart';
import 'open_packages_tab.dart';
import 'scheduling_service.dart';

const List<String> DISCIPLINAS = [
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

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Supabase.initialize(
      url: 'https://xymynrsjqjynixrfewie.supabase.co',
      anonKey: 'sb_publishable_U4cKYvkIA1m_pOa5zzkx1w_cawQ2wwR',
    );
  } catch (e) {
    debugPrint("Erro ao iniciar Supabase: $e");
  }
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Assistente do Professor',
      theme: ThemeData(primarySwatch: Colors.indigo),
      home: const HomeMobilePage(),
    );
  }
}

// Máscara de Telefone Brasileira: (00) 00000-0000
class PhoneInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text.replaceAll(RegExp(r'\D'), '');
    String formatted = '';
    if (text.isNotEmpty) {
      formatted += '(${text.substring(0, text.length >= 2 ? 2 : text.length)}';
    }
    if (text.length >= 3) {
      formatted += ') ${text.substring(2, text.length >= 7 ? 7 : text.length)}';
    }
    if (text.length >= 8) {
      formatted +=
          '-${text.substring(7, text.length >= 11 ? 11 : text.length)}';
    }
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

class HomeMobilePage extends StatefulWidget {
  const HomeMobilePage({super.key});

  @override
  State<HomeMobilePage> createState() => _HomeMobilePageState();
}

class _HomeMobilePageState extends State<HomeMobilePage> {
  int _indiceAtual = 0;

  final List<Widget> _telas = [
    const TelaAgendaMobile(),
    const TelaPrecosMobile(),
    const TelaAlunosMobile(),
    const TelaGestaoMasterMobile(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _telas[_indiceAtual],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _indiceAtual,
        type: BottomNavigationBarType.fixed,
        onTap: (index) {
          setState(() {
            _indiceAtual = index;
          });
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.calendar_today),
            label: 'Agenda',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.attach_money),
            label: 'Preços',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Alunos'),
          BottomNavigationBarItem(
            icon: Icon(Icons.assessment),
            label: 'Gestão',
          ),
        ],
      ),
    );
  }
}

// ================= TELA 1: AGENDA & GOOGLE CALENDAR API =================
class TelaAgendaMobile extends StatefulWidget {
  const TelaAgendaMobile({super.key});

  @override
  State<TelaAgendaMobile> createState() => _TelaAgendaMobileState();
}

class _TelaAgendaMobileState extends State<TelaAgendaMobile> {
  final supabase = Supabase.instance.client;
  final calendarSync = GoogleCalendarSyncService.instance;
  final scheduling = SchedulingService.instance;
  List<Map<String, dynamic>> aulas = [];
  bool carregando = true;
  bool sincronizando = false;
  String? contaGoogle;

  @override
  void initState() {
    super.initState();
    carregarAulas();
    restaurarSincronizacao();
  }

  Future<void> restaurarSincronizacao() async {
    final account = await calendarSync.restoreSession();
    if (!mounted || account == null) return;
    setState(() => contaGoogle = account.email);
    await sincronizarGoogle();
  }

  Future<void> carregarAulas() async {
    if (mounted) setState(() => carregando = true);
    try {
      await scheduling.completePastLessons();
      final response = await supabase
          .from('aulas')
          .select()
          .eq('status_aula', 'Agendada');

      List<Map<String, dynamic>> lista = List<Map<String, dynamic>>.from(
        response,
      );

      lista.sort((a, b) {
        try {
          DateTime dtA = DateTime.parse(
            a['data_aula'].split('/').reversed.join('-'),
          );
          DateTime dtB = DateTime.parse(
            b['data_aula'].split('/').reversed.join('-'),
          );
          int cmp = dtA.compareTo(dtB);
          if (cmp != 0) return cmp;
          return (a['horario'] ?? '00:00').compareTo(b['horario'] ?? '00:00');
        } catch (_) {
          return 0;
        }
      });

      if (!mounted) return;
      setState(() {
        aulas = lista;
        carregando = false;
      });
    } catch (_) {
      if (mounted) setState(() => carregando = false);
    }
  }

  Future<void> sincronizarGoogle() async {
    if (sincronizando) return;
    setState(() => sincronizando = true);
    try {
      final resumo = await calendarSync.syncPendingLessons();
      contaGoogle = calendarSync.currentUser?.email;
      await carregarAulas();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Sincronização concluída: ${resumo.synced} enviadas, '
            '${resumo.deleted} excluídas e ${resumo.failed} com erro.',
          ),
          duration: const Duration(seconds: 6),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Erro ao sincronizar: $e')));
    } finally {
      if (mounted) setState(() => sincronizando = false);
    }
  }

  Widget iconeSincronizacao(Map<String, dynamic> aula) {
    final status = aula['google_sync_status']?.toString() ?? 'pendente';
    switch (status) {
      case 'sincronizado':
        return const Tooltip(
          message: 'Sincronizada com o Google Agenda',
          child: Icon(Icons.cloud_done, color: Colors.green, size: 20),
        );
      case 'sincronizando':
        return const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      case 'erro':
        return Tooltip(
          message:
              aula['google_sync_error']?.toString() ?? 'Erro de sincronização',
          child: const Icon(Icons.cloud_off, color: Colors.red, size: 20),
        );
      default:
        return const Tooltip(
          message: 'Sincronização pendente',
          child: Icon(Icons.cloud_sync, color: Colors.orange, size: 20),
        );
    }
  }

  Future<void> excluirAula(Map<String, dynamic> aula) async {
    var aulasParaExcluir = <Map<String, dynamic>>[aula];
    final serieId = aula['serie_id']?.toString();
    if (serieId != null && serieId.isNotEmpty) {
      final escopo = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Excluir aulas fixas'),
          content: const Text(
            'Esta aula faz parte de uma sequência. O que deseja excluir?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, 'uma'),
              child: const Text('Somente esta'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, 'futuras'),
              child: const Text('Esta e as próximas'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, 'todas'),
              child: const Text('Toda a sequência'),
            ),
          ],
        ),
      );
      if (escopo == null) return;

      final response = await supabase
          .from('aulas')
          .select()
          .eq('serie_id', serieId);
      final serie = List<Map<String, dynamic>>.from(response);
      final inicioSelecionado = scheduling.parseLessonStart(aula);
      aulasParaExcluir = serie.where((item) {
        if (escopo == 'todas') return true;
        if (escopo == 'uma') return item['id'] == aula['id'];
        final inicio = scheduling.parseLessonStart(item);
        return inicioSelecionado != null &&
            inicio != null &&
            !inicio.isBefore(inicioSelecionado);
      }).toList();
    }

    final escolha = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir aula'),
        content: Text(
          'Você excluirá ${aulasParaExcluir.length} aula(s). '
          'Deseja excluir também do Google Agenda?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'somente_app'),
            child: const Text('Somente do app'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, 'app_google'),
            child: const Text('Excluir dos dois'),
          ),
        ],
      ),
    );
    if (escolha == null) return;

    try {
      if (escolha == 'somente_app') {
        await supabase
            .from('aulas')
            .delete()
            .inFilter(
              'id',
              aulasParaExcluir.map((item) => item['id']).toList(),
            );
      } else {
        for (final item in aulasParaExcluir) {
          await calendarSync.requestLessonDeletion(item);
        }
      }
      await carregarAulas();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aula excluída com sucesso.')),
      );
    } catch (e) {
      await carregarAulas();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'A exclusão ficou pendente. Use o botão Sincronizar quando houver '
            'internet. Detalhes: $e',
          ),
          duration: const Duration(seconds: 8),
        ),
      );
    }
  }

  Future<void> mudarStatusComRegra(int id, String novoStatus) async {
    try {
      final resAula = await supabase
          .from('aulas')
          .select()
          .eq('id', id)
          .maybeSingle();
      if (resAula == null) return;

      String aluno = resAula['aluno'];
      String pacote = resAula['pacote'] ?? 'Avulsa';
      String dataAula = resAula['data_aula'] ?? '';

      if (novoStatus == 'Falta sem Aviso') {
        double valorFalta = 110.0;
        final resPac = await supabase
            .from('pacotes_professor')
            .select()
            .eq('nome_pacote', pacote)
            .maybeSingle();
        if (resPac != null) {
          double total =
              double.tryParse(resPac['valor_total'].toString()) ?? 110.0;
          int qtd = int.tryParse(resPac['qtd_aulas'].toString()) ?? 1;
          valorFalta = total / (qtd > 0 ? qtd : 1);
        }

        await supabase.from('cobrancas').insert({
          'aluno': aluno,
          'descricao': 'Falta s/ Aviso ($dataAula) - $pacote',
          'valor': valorFalta,
          'vencimento': DateTime.now().toString().substring(0, 10),
          'status': 'Pendente',
        });

        final aulaAtualizada = await supabase
            .from('aulas')
            .update({
              'status_aula': 'Falta sem Aviso',
              'google_sync_status': 'pendente',
              'google_sync_action': 'upsert',
              'google_sync_error': null,
            })
            .eq('id', id)
            .select()
            .single();
        try {
          await calendarSync.syncLesson(aulaAtualizada);
        } catch (_) {
          // A aula permanece marcada para uma nova tentativa de sincronização.
        }
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Falta registrada, mantida no histórico e convertida em cobrança.',
            ),
          ),
        );
      } else if (novoStatus == 'Cancelada com Reposição') {
        await supabase.from('creditos_reposicao').insert({
          'aluno': aluno,
          'detalhes': 'Reposição gerada por cancelamento em $dataAula',
          'status': 'Disponível',
        });
        await calendarSync.requestLessonDeletion(resAula);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Crédito de reposição gerado e aula removida do app e do Google.',
            ),
          ),
        );
      } else if (novoStatus == 'Cancelada sem Cobrança') {
        await calendarSync.requestLessonDeletion(resAula);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Aula cancelada no app e no Google Agenda.'),
          ),
        );
      } else {
        await supabase
            .from('aulas')
            .update({'status_aula': 'Realizada'})
            .eq('id', id);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Aula marcada como Realizada!')),
        );
      }

      carregarAulas();
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erro: $e')));
    }
  }

  void abrirModalNovaAula() async {
    List<Map<String, dynamic>> listaAlunos = [];
    try {
      final resAlunos = await supabase.from('alunos').select('nome');
      listaAlunos = List<Map<String, dynamic>>.from(resAlunos);
    } catch (_) {}

    if (!mounted) return;

    String? alunoSelecionado = listaAlunos.isNotEmpty
        ? listaAlunos.first['nome']?.toString()
        : null;
    List<String> modalidadesAluno = ['Avulsa 1h'];
    String? modalidadeSelecionada = 'Avulsa 1h';
    String disciplina = 'Química';
    DateTime dataSel = DateTime.now();
    TimeOfDay horaSel = const TimeOfDay(hour: 14, minute: 0);

    List<String> assuntosDisponiveis = [];
    String? assuntoSelecionado;
    final novoAssuntoCtrl = TextEditingController();

    Future<void> carregarAssuntosDinamicos(
      String disc,
      StateSetter setStateModal,
    ) async {
      try {
        final resTopicos = await supabase
            .from('topicos')
            .select('assunto')
            .eq('disciplina', disc);
        List<String> tops = resTopicos
            .map<String>((t) => t['assunto'].toString())
            .toList();
        setStateModal(() {
          assuntosDisponiveis = tops;
          assuntoSelecionado = tops.isNotEmpty ? tops.first : null;
        });
      } catch (_) {}
    }

    Future<void> atualizarModalidades(
      String aluno,
      StateSetter setStateModal,
    ) async {
      List<String> opcs = [];
      try {
        final resPacs = await supabase
            .from('pacotes_professor')
            .select('nome_pacote, qtd_aulas')
            .eq('ativo', true);
        for (var p in resPacs) {
          if ((p['qtd_aulas'] ?? 1) == 1) opcs.add(p['nome_pacote'].toString());
        }
        final resComprados = await supabase
            .from('pacotes_comprados')
            .select('pacote')
            .eq('aluno', aluno);
        for (var c in resComprados) {
          String pac = c['pacote'].toString();
          if (!opcs.contains(pac)) opcs.add(pac);
        }
      } catch (_) {}

      if (opcs.isEmpty) opcs.add('Avulsa 1h');
      setStateModal(() {
        modalidadesAluno = opcs;
        modalidadeSelecionada = opcs.first;
      });
    }

    if (alunoSelecionado != null) {
      await atualizarModalidades(alunoSelecionado, (fn) => fn());
    }
    await carregarAssuntosDinamicos(disciplina, (fn) => fn());

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateModal) => AlertDialog(
          title: const Text('Agendar Nova Aula'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                listaAlunos.isEmpty
                    ? const Text(
                        'Cadastre alunos primeiro.',
                        style: TextStyle(color: Colors.red),
                      )
                    : DropdownButtonFormField<String>(
                        value: alunoSelecionado,
                        decoration: const InputDecoration(labelText: 'Aluno'),
                        items: listaAlunos
                            .map(
                              (a) => DropdownMenuItem(
                                value: a['nome'].toString(),
                                child: Text(a['nome'].toString()),
                              ),
                            )
                            .toList(),
                        onChanged: (v) async {
                          setStateModal(() => alunoSelecionado = v);
                          if (v != null)
                            await atualizarModalidades(v, setStateModal);
                        },
                      ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: modalidadeSelecionada,
                  decoration: const InputDecoration(
                    labelText: 'Modalidade (Avulsa ou Pacote)',
                  ),
                  items: modalidadesAluno
                      .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                      .toList(),
                  onChanged: (v) =>
                      setStateModal(() => modalidadeSelecionada = v),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: disciplina,
                  decoration: const InputDecoration(labelText: 'Disciplina'),
                  items: DISCIPLINAS
                      .map((d) => DropdownMenuItem(value: d, child: Text(d)))
                      .toList(),
                  onChanged: (v) async {
                    if (v != null) {
                      setStateModal(() => disciplina = v);
                      await carregarAssuntosDinamicos(v, setStateModal);
                    }
                  },
                ),
                const SizedBox(height: 10),
                assuntosDisponiveis.isEmpty
                    ? const Text(
                        'Nenhum assunto cadastrado para esta disciplina.',
                      )
                    : DropdownButtonFormField<String>(
                        value: assuntoSelecionado,
                        decoration: const InputDecoration(
                          labelText: 'Assunto do Acervo',
                        ),
                        items: assuntosDisponiveis
                            .map(
                              (as) =>
                                  DropdownMenuItem(value: as, child: Text(as)),
                            )
                            .toList(),
                        onChanged: (v) =>
                            setStateModal(() => assuntoSelecionado = v),
                      ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: novoAssuntoCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Ou cadastrar novo assunto',
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add_circle, color: Colors.indigo),
                      onPressed: () async {
                        String novo = novoAssuntoCtrl.text.trim();
                        if (novo.isNotEmpty) {
                          try {
                            await supabase.from('topicos').insert({
                              'disciplina': disciplina,
                              'assunto': novo,
                            });
                            novoAssuntoCtrl.clear();
                            await carregarAssuntosDinamicos(
                              disciplina,
                              setStateModal,
                            );
                            setStateModal(() => assuntoSelecionado = novo);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Assunto adicionado e salvo com sucesso!',
                                  ),
                                ),
                              );
                            }
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Erro ao salvar assunto: $e'),
                                ),
                              );
                            }
                          }
                        }
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: dataSel,
                      firstDate: DateTime(2025),
                      lastDate: DateTime(2030),
                    );
                    if (picked != null) setStateModal(() => dataSel = picked);
                  },
                  icon: const Icon(Icons.calendar_month),
                  label: Text('Data: ${dataSel.toString().substring(0, 10)}'),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () async {
                    final picked = await showTimePicker(
                      context: context,
                      initialTime: horaSel,
                    );
                    if (picked != null) setStateModal(() => horaSel = picked);
                  },
                  icon: const Icon(Icons.access_time),
                  label: Text('Horário: ${horaSel.format(context)}'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: listaAlunos.isEmpty || alunoSelecionado == null
                  ? null
                  : () async {
                      String assuntoFinal = assuntoSelecionado ?? 'Geral';
                      if (modalidadeSelecionada != null &&
                          !modalidadeSelecionada!.startsWith('Avulsa')) {
                        final resPacInfo = await supabase
                            .from('pacotes_professor')
                            .select('qtd_aulas')
                            .eq('nome_pacote', modalidadeSelecionada!)
                            .maybeSingle();
                        if (resPacInfo != null) {
                          int qtdMax =
                              int.tryParse(
                                resPacInfo['qtd_aulas'].toString(),
                              ) ??
                              1;
                          final resAulasCad = await supabase
                              .from('aulas')
                              .select('id')
                              .eq('aluno', alunoSelecionado!)
                              .eq('pacote', modalidadeSelecionada!);
                          int jaCadastradas = resAulasCad.length;
                          if (jaCadastradas >= qtdMax) {
                            if (!context.mounted) return;
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Limite de aulas deste pacote esgotado!',
                                ),
                              ),
                            );
                            return;
                          }
                        }
                      }

                      String dataStr =
                          "${dataSel.day.toString().padLeft(2, '0')}/${dataSel.month.toString().padLeft(2, '0')}/${dataSel.year}";
                      String horaStr =
                          "${horaSel.hour.toString().padLeft(2, '0')}:${horaSel.minute.toString().padLeft(2, '0')}";

                      if (modalidadeSelecionada != null &&
                          modalidadeSelecionada!.startsWith('Avulsa')) {
                        double valAvulsa = 110.0;
                        final resPac = await supabase
                            .from('pacotes_professor')
                            .select('valor_total')
                            .eq('nome_pacote', modalidadeSelecionada!)
                            .maybeSingle();
                        if (resPac != null)
                          valAvulsa =
                              double.tryParse(
                                resPac['valor_total'].toString(),
                              ) ??
                              110.0;

                        await supabase.from('cobrancas').insert({
                          'aluno': alunoSelecionado,
                          'descricao':
                              'Aula Avulsa $disciplina ($dataStr) - $alunoSelecionado',
                          'valor': valAvulsa,
                          'vencimento': DateTime.now().toString().substring(
                            0,
                            10,
                          ),
                          'status': 'Pendente',
                        });
                      }

                      final aulaCriada = await supabase
                          .from('aulas')
                          .insert({
                            'aluno': alunoSelecionado,
                            'pacote': modalidadeSelecionada ?? 'Avulsa',
                            'disciplina': disciplina,
                            'data_aula': dataStr,
                            'horario': horaStr,
                            'assunto': assuntoFinal,
                            'status_aula': 'Agendada',
                            'google_sync_status': 'pendente',
                            'google_sync_action': 'upsert',
                          })
                          .select()
                          .single();

                      String mensagemFinal = 'Aula agendada com sucesso.';
                      try {
                        await calendarSync.syncLesson(aulaCriada);
                        mensagemFinal =
                            'Aula agendada e salva no Google Agenda!';
                      } catch (e) {
                        debugPrint("Erro ao enviar para Google Agenda: $e");
                        mensagemFinal =
                            'Aula salva no app. A sincronização com o Google ficou '
                            'pendente; use o botão de nuvem para tentar novamente.';
                      }

                      if (!mounted) return;
                      Navigator.pop(context);
                      carregarAulas();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(mensagemFinal),
                          duration: const Duration(seconds: 6),
                        ),
                      );
                    },
              child: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> abrirNovoAgendamento() async {
    final quantidade = await showNewLessonDialog(context);
    if (quantidade != null) await carregarAulas();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Agenda (Aulas Futuras)'),
            if (contaGoogle != null)
              Text(
                contaGoogle!,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.normal,
                ),
              ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Atualizar lista de aulas',
            onPressed: carregarAulas,
          ),
          IconButton(
            icon: sincronizando
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.cloud_sync),
            tooltip: 'Sincronizar com Google Agenda',
            onPressed: sincronizando ? null : sincronizarGoogle,
          ),
          IconButton(
            icon: const Icon(Icons.login),
            tooltip: 'Conectar Google Conta',
            onPressed: () async {
              try {
                final account = await calendarSync.connect();
                if (!context.mounted) return;
                setState(() => contaGoogle = account.email);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Conta ${account.email} conectada com sucesso!',
                    ),
                  ),
                );
              } catch (e) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text('Erro ao conectar: $e')));
              }
            },
          ),
        ],
      ),
      body: carregando
          ? const Center(child: CircularProgressIndicator())
          : aulas.isEmpty
          ? const Center(child: Text('Nenhuma aula agendada.'))
          : ListView.builder(
              itemCount: aulas.length,
              itemBuilder: (context, index) {
                final a = aulas[index];
                return Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '${a['aluno']}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            Flexible(
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  iconeSincronizacao(a),
                                  const SizedBox(width: 6),
                                  Flexible(
                                    child: Text(
                                      '${a['data_aula']} às ${a['horario']}',
                                      textAlign: TextAlign.end,
                                      style: const TextStyle(
                                        color: Colors.blueGrey,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Disciplina: ${a['disciplina']} | Assunto: ${a['assunto']}',
                        ),
                        Text('Modalidade: ${a['pacote']}'),
                        const Divider(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton.icon(
                              onPressed: () =>
                                  mudarStatusComRegra(a['id'], 'Realizada'),
                              icon: const Icon(
                                Icons.check,
                                color: Colors.indigo,
                                size: 18,
                              ),
                              label: const Text('Realizada'),
                            ),
                            PopupMenuButton<String>(
                              onSelected: (val) {
                                if (val == 'Excluir Aula') {
                                  excluirAula(a);
                                } else {
                                  mudarStatusComRegra(a['id'], val);
                                }
                              },
                              itemBuilder: (context) => [
                                const PopupMenuItem(
                                  value: 'Falta sem Aviso',
                                  child: Text('Falta (Gera Cobrança)'),
                                ),
                                const PopupMenuItem(
                                  value: 'Cancelada com Reposição',
                                  child: Text('Cancelar c/ Reposição'),
                                ),
                                const PopupMenuItem(
                                  value: 'Cancelada sem Cobrança',
                                  child: Text('Cancelar s/ Cobrança'),
                                ),
                                const PopupMenuDivider(),
                                const PopupMenuItem(
                                  value: 'Excluir Aula',
                                  child: Text(
                                    'Excluir aula',
                                    style: TextStyle(color: Colors.red),
                                  ),
                                ),
                              ],
                              child: const Text(
                                'Outros',
                                style: TextStyle(
                                  color: Colors.red,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: abrirNovoAgendamento,
        icon: const Icon(Icons.add),
        label: const Text('Nova Aula'),
      ),
    );
  }
}

// ================= TELA 2: PREÇOS & PACOTES =================
class TelaPrecosMobile extends StatelessWidget {
  const TelaPrecosMobile({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Gestão de Preços'),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.list), text: 'Modalidades'),
              Tab(icon: Icon(Icons.add_box), text: 'Nova Modalidade'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [AbaListaPrecosMobile(), AbaCriarPacoteMobile()],
        ),
      ),
    );
  }
}

class AbaListaPrecosMobile extends StatefulWidget {
  const AbaListaPrecosMobile({super.key});

  @override
  State<AbaListaPrecosMobile> createState() => _AbaListaPrecosMobileState();
}

class _AbaListaPrecosMobileState extends State<AbaListaPrecosMobile> {
  final supabase = Supabase.instance.client;
  List<Map<String, dynamic>> pacotes = [];
  bool carregando = true;

  @override
  void initState() {
    super.initState();
    carregarPacotes();
  }

  Future<void> carregarPacotes() async {
    try {
      final response = await supabase
          .from('pacotes_professor')
          .select()
          .eq('ativo', true)
          .order('id', ascending: true);
      if (!mounted) return;
      setState(() {
        pacotes = List<Map<String, dynamic>>.from(response);
        carregando = false;
      });
    } catch (_) {
      if (mounted) setState(() => carregando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: carregando
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: pacotes.length,
              itemBuilder: (context, index) {
                final p = pacotes[index];
                return Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  child: ListTile(
                    title: Text(
                      p['nome_pacote'],
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      'Tipo: ${p['periodicidade'] ?? 'Avulsa'} | Aulas: ${p['qtd_aulas']} | ${p['duracao_min']} min',
                    ),
                    trailing: Text(
                      "R\$ ${double.parse(p['valor_total'].toString()).toStringAsFixed(2)}",
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                        fontSize: 15,
                      ),
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: carregarPacotes,
        tooltip: 'Atualizar',
        child: const Icon(Icons.refresh),
      ),
    );
  }
}

class AbaCriarPacoteMobile extends StatefulWidget {
  const AbaCriarPacoteMobile({super.key});

  @override
  State<AbaCriarPacoteMobile> createState() => _AbaCriarPacoteMobileState();
}

class _AbaCriarPacoteMobileState extends State<AbaCriarPacoteMobile> {
  final supabase = Supabase.instance.client;
  final List<String> periodicidades = [
    "Avulsa",
    "Semanal",
    "Quinzenal",
    "Mensal",
    "Bimestral",
    "Trimestral",
    "Semestral",
  ];
  final List<String> duracoes = [
    "30",
    "45",
    "60",
    "75",
    "90",
    "105",
    "120",
    "135",
    "150",
    "165",
    "180",
  ];

  String tipoSel = "Mensal";
  int qtdAulas = 4;
  String duracaoSel = "60";
  final _valorController = TextEditingController();
  bool salvando = false;

  String formatarDuracao(String minStr) {
    int m = int.tryParse(minStr) ?? 60;
    int h = m ~/ 60;
    int r = m % 60;
    if (h > 0 && r > 0) return '${h}h${r.toString().padLeft(2, '0')}';
    if (h > 0) return '${h}h';
    return '${r}min';
  }

  String get nomeAutomatico =>
      '$tipoSel ${qtdAulas}x ${formatarDuracao(duracaoSel)}';

  void sugerirPreco() {
    double baseHora = 110.0;
    double duracaoH = (int.tryParse(duracaoSel) ?? 60) / 60.0;
    double bruto = qtdAulas * baseHora * duracaoH;
    double desconto = qtdAulas > 1 ? (0.03 * qtdAulas).clamp(0.0, 0.25) : 0.0;
    double piso = qtdAulas * baseHora * duracaoH * 0.75;
    double sugerido = bruto * (1.0 - desconto);
    if (sugerido < piso) sugerido = piso;
    _valorController.text = sugerido.toStringAsFixed(2);
  }

  Future<void> salvarModalidade() async {
    final valorStr = _valorController.text.trim();
    if (valorStr.isEmpty) return;

    setState(() => salvando = true);
    try {
      await supabase.from('pacotes_professor').insert({
        'nome_pacote': nomeAutomatico,
        'periodicidade': tipoSel,
        'qtd_aulas': qtdAulas,
        'duracao_min': int.parse(duracaoSel),
        'valor_total': double.parse(valorStr),
        'ativo': true,
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Modalidade "$nomeAutomatico" criada!')),
      );
      _valorController.clear();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Erro: $e')));
    } finally {
      if (mounted) setState(() => salvando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<String>(
            value: tipoSel,
            decoration: const InputDecoration(
              labelText: 'Tipo / Periodicidade',
              border: OutlineInputBorder(),
            ),
            items: periodicidades
                .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                .toList(),
            onChanged: (v) => setState(() => tipoSel = v!),
          ),
          const SizedBox(height: 12),
          TextField(
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Quantidade de Aulas (1 = Avulsa)',
              border: OutlineInputBorder(),
            ),
            controller: TextEditingController(text: qtdAulas.toString())
              ..selection = TextSelection.fromPosition(
                TextPosition(offset: qtdAulas.toString().length),
              ),
            onChanged: (v) => setState(() => qtdAulas = int.tryParse(v) ?? 1),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: duracaoSel,
            decoration: const InputDecoration(
              labelText: 'Duração da Aula',
              border: OutlineInputBorder(),
            ),
            items: duracoes
                .map(
                  (d) => DropdownMenuItem(value: d, child: Text('$d minutos')),
                )
                .toList(),
            onChanged: (v) => setState(() => duracaoSel = v!),
          ),
          const SizedBox(height: 12),
          InputDecorator(
            decoration: const InputDecoration(
              labelText: 'Nome Automático da Modalidade',
              border: OutlineInputBorder(),
            ),
            child: Text(
              nomeAutomatico,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: Colors.indigo,
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _valorController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Valor Total (R\$)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: sugerirPreco,
                  icon: const Icon(Icons.lightbulb),
                  label: const Text('Sugerir Preço'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  onPressed: salvando ? null : salvarModalidade,
                  child: Text(salvando ? 'Salvando...' : 'Salvar'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ================= TELA 3: ALUNOS =================
class TelaAlunosMobile extends StatelessWidget {
  const TelaAlunosMobile({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Gestão de Alunos'),
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(icon: Icon(Icons.group), text: 'Lista & Prontuário'),
              Tab(icon: Icon(Icons.person_add), text: 'Cadastrar'),
              Tab(icon: Icon(Icons.card_giftcard), text: 'Comprar Pacote'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            AbaListaAlunosMobile(),
            AbaCadastrarAlunoMobile(),
            AbaComprarPacoteMobile(),
          ],
        ),
      ),
    );
  }
}

class AbaCadastrarAlunoMobile extends StatefulWidget {
  const AbaCadastrarAlunoMobile({super.key});

  @override
  State<AbaCadastrarAlunoMobile> createState() =>
      _AbaCadastrarAlunoMobileState();
}

class _AbaCadastrarAlunoMobileState extends State<AbaCadastrarAlunoMobile> {
  final supabase = Supabase.instance.client;
  final _nomeController = TextEditingController();
  final _respController = TextEditingController();
  final _wppAlunoController = TextEditingController();
  final _wppRespController = TextEditingController();
  bool salvando = false;

  final List<String> _anos = [
    "5º Ano - Fund.",
    "6º Ano - Fund.",
    "7º Ano - Fund.",
    "8º Ano - Fund.",
    "9º Ano - Fund.",
    "1ª Série - EM",
    "2ª Série - EM",
    "3ª Série - EM",
    "Pré-Vestibular / Superior",
  ];
  String _anoSelecionado = "3ª Série - EM";

  Future<void> salvarAluno() async {
    final nome = _nomeController.text.trim();
    if (nome.isEmpty) return;

    setState(() => salvando = true);
    try {
      await supabase.from('alunos').insert({
        'nome': nome,
        'ano_escolar': _anoSelecionado,
        'responsavel': _respController.text.trim(),
        'whatsapp_aluno': _wppAlunoController.text.trim(),
        'whatsapp_resp': _wppRespController.text.trim(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Aluno $nome salvo!')));
      _nomeController.clear();
      _respController.clear();
      _wppAlunoController.clear();
      _wppRespController.clear();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Erro: $e')));
    } finally {
      if (mounted) setState(() => salvando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _nomeController,
            decoration: const InputDecoration(
              labelText: 'Nome do Aluno',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _anoSelecionado,
            decoration: const InputDecoration(
              labelText: 'Ano Escolar',
              border: OutlineInputBorder(),
            ),
            items: _anos
                .map((a) => DropdownMenuItem(value: a, child: Text(a)))
                .toList(),
            onChanged: (v) {
              if (v != null) setState(() => _anoSelecionado = v);
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _respController,
            decoration: const InputDecoration(
              labelText: 'Responsável',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _wppAlunoController,
            keyboardType: TextInputType.phone,
            inputFormatters: [PhoneInputFormatter()],
            decoration: const InputDecoration(
              labelText: 'WhatsApp Aluno',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _wppRespController,
            keyboardType: TextInputType.phone,
            inputFormatters: [PhoneInputFormatter()],
            decoration: const InputDecoration(
              labelText: 'WhatsApp Responsável',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: salvando ? null : salvarAluno,
            child: Text(salvando ? 'Salvando...' : 'Salvar Aluno'),
          ),
        ],
      ),
    );
  }
}

class AbaListaAlunosMobile extends StatefulWidget {
  const AbaListaAlunosMobile({super.key});

  @override
  State<AbaListaAlunosMobile> createState() => _AbaListaAlunosMobileState();
}

class _AbaListaAlunosMobileState extends State<AbaListaAlunosMobile> {
  final supabase = Supabase.instance.client;
  List<Map<String, dynamic>> alunos = [];
  bool carregando = true;

  final List<String> _anos = [
    "5º Ano - Fund.",
    "6º Ano - Fund.",
    "7º Ano - Fund.",
    "8º Ano - Fund.",
    "9º Ano - Fund.",
    "1ª Série - EM",
    "2ª Série - EM",
    "3ª Série - EM",
    "Pré-Vestibular / Superior",
  ];

  @override
  void initState() {
    super.initState();
    carregarAlunos();
  }

  Future<void> carregarAlunos() async {
    try {
      final res = await supabase
          .from('alunos')
          .select()
          .order('nome', ascending: true);
      if (!mounted) return;
      setState(() {
        alunos = List<Map<String, dynamic>>.from(res);
        carregando = false;
      });
    } catch (_) {
      if (mounted) setState(() => carregando = false);
    }
  }

  DateTime? _parseData(dynamic valor) {
    final texto = valor?.toString().trim() ?? '';
    if (texto.isEmpty) return null;

    final iso = DateTime.tryParse(texto);
    if (iso != null) return DateTime(iso.year, iso.month, iso.day);

    final partes = texto.split('/');
    if (partes.length != 3) return null;

    final dia = int.tryParse(partes[0]);
    final mes = int.tryParse(partes[1]);
    final ano = int.tryParse(partes[2]);
    if (dia == null || mes == null || ano == null) return null;
    return DateTime(ano, mes, dia);
  }

  String _formatarData(DateTime? data) {
    if (data == null) return '-';
    final dia = data.day.toString().padLeft(2, '0');
    final mes = data.month.toString().padLeft(2, '0');
    return '$dia/$mes/${data.year}';
  }

  Future<void> abrirProntuario(Map<String, dynamic> aluno) async {
    final nome = aluno['nome']?.toString() ?? '';
    List<Map<String, dynamic>> aulas = [];
    List<Map<String, dynamic>> compras = [];
    List<Map<String, dynamic>> definicoes = [];

    try {
      final resultados = await Future.wait([
        supabase.from('aulas').select().eq('aluno', nome),
        supabase.from('pacotes_comprados').select().eq('aluno', nome),
        supabase.from('pacotes_professor').select('nome_pacote, qtd_aulas'),
      ]);
      aulas = List<Map<String, dynamic>>.from(resultados[0]);
      compras = List<Map<String, dynamic>>.from(resultados[1]);
      definicoes = List<Map<String, dynamic>>.from(resultados[2]);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao carregar prontuário: $e')),
      );
      return;
    }

    final quantidadesPorPacote = <String, int>{};
    for (final definicao in definicoes) {
      final nomePacote = definicao['nome_pacote']?.toString();
      if (nomePacote != null) {
        quantidadesPorPacote[nomePacote] =
            int.tryParse(definicao['qtd_aulas']?.toString() ?? '') ?? 0;
      }
    }

    final hojeAgora = DateTime.now();
    final hoje = DateTime(hojeAgora.year, hojeAgora.month, hojeAgora.day);
    final pacotesAbertos = <Map<String, dynamic>>[];

    for (final compra in compras) {
      final nomePacote = compra['pacote']?.toString() ?? 'Pacote';
      final inicio = _parseData(compra['data_inicio']);
      final fim = _parseData(compra['data_fim']);
      final quantidadeTotal = quantidadesPorPacote[nomePacote] ?? 0;

      final aulasDoCiclo = aulas.where((aula) {
        if (aula['pacote']?.toString() != nomePacote) return false;
        final dataAula = _parseData(aula['data_aula']);
        if (dataAula == null) return false;
        if (inicio != null && dataAula.isBefore(inicio)) return false;
        if (fim != null && dataAula.isAfter(fim)) return false;
        return true;
      }).toList();

      final realizadas = aulasDoCiclo
          .where((aula) => aula['status_aula'] == 'Realizada')
          .length;
      final faltas = aulasDoCiclo
          .where((aula) => aula['status_aula'] == 'Falta sem Aviso')
          .length;
      final utilizadas = realizadas + faltas;
      var restantes = quantidadeTotal - utilizadas;
      if (restantes < 0) restantes = 0;

      final vigente = fim == null || !fim.isBefore(hoje);
      if (vigente && restantes > 0) {
        pacotesAbertos.add({
          'nome': nomePacote,
          'inicio': inicio,
          'fim': fim,
          'total': quantidadeTotal,
          'realizadas': realizadas,
          'faltas': faltas,
          'utilizadas': utilizadas,
          'restantes': restantes,
        });
      }
    }

    pacotesAbertos.sort((a, b) {
      final fimA = a['fim'] as DateTime?;
      final fimB = b['fim'] as DateTime?;
      if (fimA == null && fimB == null) return 0;
      if (fimA == null) return 1;
      if (fimB == null) return -1;
      return fimA.compareTo(fimB);
    });

    final total = aulas.length;
    final feitas = aulas.where((a) => a['status_aula'] == 'Realizada').length;

    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Prontuário: $nome'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Ano Escolar: ${aluno['ano_escolar'] ?? '-'}'),
                Text('Responsável: ${aluno['responsavel'] ?? '-'}'),
                Text('WhatsApp Aluno: ${aluno['whatsapp_aluno'] ?? '-'}'),
                Text('WhatsApp Responsável: ${aluno['whatsapp_resp'] ?? '-'}'),
                const Divider(height: 24),
                Text(
                  'Histórico geral: $feitas realizadas de $total cadastradas',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Pacotes em aberto',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                if (pacotesAbertos.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('Nenhum pacote em aberto para este aluno.'),
                  )
                else
                  ...pacotesAbertos.map((pacote) {
                    final totalPacote = pacote['total'] as int;
                    final utilizadas = pacote['utilizadas'] as int;
                    final progresso = totalPacote > 0
                        ? (utilizadas / totalPacote).clamp(0.0, 1.0).toDouble()
                        : 0.0;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              pacote['nome'].toString(),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Ciclo: ${_formatarData(pacote['inicio'] as DateTime?)} '
                              'a ${_formatarData(pacote['fim'] as DateTime?)}',
                            ),
                            const SizedBox(height: 8),
                            LinearProgressIndicator(value: progresso),
                            const SizedBox(height: 8),
                            Text('Aulas realizadas: ${pacote['realizadas']}'),
                            Text('Faltas consumidas: ${pacote['faltas']}'),
                            Text('Aulas restantes: ${pacote['restantes']}'),
                            Text('Total do ciclo: ${pacote['total']}'),
                          ],
                        ),
                      ),
                    );
                  }),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }

  Future<void> editarAluno(Map<String, dynamic> aluno) async {
    final nomeOriginal = aluno['nome']?.toString() ?? '';
    final nomeCtrl = TextEditingController(text: aluno['nome'] ?? '');
    final respCtrl = TextEditingController(text: aluno['responsavel'] ?? '');
    final wppAlunoCtrl = TextEditingController(
      text: aluno['whatsapp_aluno'] ?? '',
    );
    final wppRespCtrl = TextEditingController(
      text: aluno['whatsapp_resp'] ?? '',
    );
    String anoSel = aluno['ano_escolar'] ?? '3ª Série - EM';

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateModal) => AlertDialog(
          title: Text('Editar Aluno: ${aluno['nome']}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nomeCtrl,
                  decoration: const InputDecoration(labelText: 'Nome'),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: _anos.contains(anoSel) ? anoSel : _anos.first,
                  decoration: const InputDecoration(labelText: 'Ano Escolar'),
                  items: _anos
                      .map((a) => DropdownMenuItem(value: a, child: Text(a)))
                      .toList(),
                  onChanged: (v) => setStateModal(() => anoSel = v!),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: respCtrl,
                  decoration: const InputDecoration(labelText: 'Responsável'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: wppAlunoCtrl,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [PhoneInputFormatter()],
                  decoration: const InputDecoration(
                    labelText: 'WhatsApp Aluno',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: wppRespCtrl,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [PhoneInputFormatter()],
                  decoration: const InputDecoration(
                    labelText: 'WhatsApp Responsável',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              onPressed: () async {
                final nome = aluno['nome']?.toString() ?? 'este aluno';
                var quantidadeAulas = 0;
                var quantidadePacotes = 0;

                try {
                  final resultados = await Future.wait([
                    supabase.from('aulas').select().eq('aluno', nomeOriginal),
                    supabase
                        .from('pacotes_comprados')
                        .select()
                        .eq('aluno', nomeOriginal),
                  ]);
                  quantidadeAulas = (resultados[0] as List).length;
                  quantidadePacotes = (resultados[1] as List).length;
                } catch (_) {
                  // A confirmação continua disponível mesmo se a contagem falhar.
                }

                if (!context.mounted) return;
                final confirmar = await showDialog<bool>(
                  context: context,
                  builder: (confirmContext) => AlertDialog(
                    title: Text('Excluir $nome?'),
                    content: Text(
                      'O aluno será removido da lista de alunos.\n\n'
                      'Histórico preservado:\n'
                      '• $quantidadeAulas aula(s) cadastrada(s)\n'
                      '• $quantidadePacotes pacote(s) comprado(s)\n\n'
                      'As aulas e os pacotes não serão apagados. '
                      'Essa ação não pode ser desfeita.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(confirmContext, false),
                        child: const Text('Cancelar'),
                      ),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () => Navigator.pop(confirmContext, true),
                        icon: const Icon(Icons.delete),
                        label: const Text('Excluir aluno'),
                      ),
                    ],
                  ),
                );

                if (confirmar != true || !context.mounted) return;

                try {
                  final id = aluno['id'];
                  if (id != null) {
                    await supabase.from('alunos').delete().eq('id', id);
                  } else if (nomeOriginal.isNotEmpty) {
                    await supabase
                        .from('alunos')
                        .delete()
                        .eq('nome', nomeOriginal);
                  } else {
                    throw Exception('Registro do aluno sem identificador.');
                  }

                  if (context.mounted) Navigator.pop(context);
                  await carregarAlunos();
                  if (mounted) {
                    ScaffoldMessenger.of(this.context).showSnackBar(
                      const SnackBar(
                        content: Text('Aluno excluído com sucesso!'),
                      ),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(this.context).showSnackBar(
                      SnackBar(content: Text('Erro ao excluir aluno: $e')),
                    );
                  }
                }
              },
              icon: const Icon(Icons.delete_outline),
              label: const Text('Excluir'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () async {
                try {
                  final dadosAtualizados = {
                    'nome': nomeCtrl.text.trim(),
                    'ano_escolar': anoSel,
                    'responsavel': respCtrl.text.trim(),
                    'whatsapp_aluno': wppAlunoCtrl.text.trim(),
                    'whatsapp_resp': wppRespCtrl.text.trim(),
                  };

                  final id = aluno['id'];
                  if (id != null) {
                    await supabase
                        .from('alunos')
                        .update(dadosAtualizados)
                        .eq('id', id);
                  } else if (nomeOriginal.isNotEmpty) {
                    await supabase
                        .from('alunos')
                        .update(dadosAtualizados)
                        .eq('nome', nomeOriginal);
                  } else {
                    throw Exception('Registro do aluno sem identificador.');
                  }

                  if (context.mounted) Navigator.pop(context);
                  carregarAlunos();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Aluno atualizado com sucesso!'),
                      ),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Erro ao atualizar: $e')),
                    );
                  }
                }
              },
              child: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Alunos Cadastrados (Total: ${alunos.length})'),
        automaticallyImplyLeading: false,
      ),
      body: carregando
          ? const Center(child: CircularProgressIndicator())
          : alunos.isEmpty
          ? const Center(child: Text('Nenhum aluno cadastrado.'))
          : ListView.builder(
              itemCount: alunos.length,
              itemBuilder: (context, index) {
                final al = alunos[index];
                return GestureDetector(
                  onDoubleTap: () => abrirProntuario(al),
                  child: Card(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    child: ListTile(
                      title: Text(
                        al['nome'],
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        'Série: ${al['ano_escolar'] ?? '-'}\n'
                        'Resp: ${al['responsavel'] ?? '-'}\n'
                        'Duplo clique para abrir o prontuário',
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.edit, color: Colors.indigo),
                        onPressed: () => editarAluno(al),
                      ),
                      isThreeLine: true,
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: carregarAlunos,
        tooltip: 'Atualizar',
        child: const Icon(Icons.refresh),
      ),
    );
  }
}

class AbaComprarPacoteMobile extends StatefulWidget {
  const AbaComprarPacoteMobile({super.key});

  @override
  State<AbaComprarPacoteMobile> createState() => _AbaComprarPacoteMobileState();
}

class _AbaComprarPacoteMobileState extends State<AbaComprarPacoteMobile> {
  final supabase = Supabase.instance.client;
  List<Map<String, dynamic>> alunos = [];
  List<Map<String, dynamic>> pacotesDisponiveis = [];
  String? alunoSelecionado;
  String? pacoteSelecionado;
  DateTime dataInicio = DateTime.now();
  DateTime dataFim = DateTime.now().add(const Duration(days: 30));
  bool carregando = true;
  bool salvando = false;

  @override
  void initState() {
    super.initState();
    carregarDados();
  }

  Future<void> carregarDados() async {
    try {
      final resAlunos = await supabase
          .from('alunos')
          .select('nome')
          .order('nome');
      final resPacs = await supabase
          .from('pacotes_professor')
          .select()
          .eq('ativo', true);

      List<Map<String, dynamic>> pacs = List<Map<String, dynamic>>.from(resPacs)
          .where((p) => (p['qtd_aulas'] ?? 1) > 1)
          .toList();

      if (!mounted) return;
      setState(() {
        alunos = List<Map<String, dynamic>>.from(resAlunos);
        if (alunos.isNotEmpty) alunoSelecionado = alunos.first['nome'];
        pacotesDisponiveis = pacs;
        if (pacotesDisponiveis.isNotEmpty) {
          pacoteSelecionado = pacotesDisponiveis.first['nome_pacote'];
          atualizarDataFim();
        }
        carregando = false;
      });
    } catch (_) {
      if (mounted) setState(() => carregando = false);
    }
  }

  void atualizarDataFim() {
    if (pacoteSelecionado == null) return;
    try {
      final pac = pacotesDisponiveis.firstWhere(
        (p) => p['nome_pacote'] == pacoteSelecionado,
      );
      String periodicidade = pac['periodicidade'] ?? 'Mensal';
      int diasAdd = 30;
      if (periodicidade == 'Semanal')
        diasAdd = 7;
      else if (periodicidade == 'Quinzenal')
        diasAdd = 15;
      else if (periodicidade == 'Mensal')
        diasAdd = 30;
      else if (periodicidade == 'Bimestral')
        diasAdd = 60;
      else if (periodicidade == 'Trimestral')
        diasAdd = 90;
      else if (periodicidade == 'Semestral')
        diasAdd = 180;

      setState(() {
        dataFim = dataInicio.add(Duration(days: diasAdd));
      });
    } catch (_) {}
  }

  Future<void> confirmarCompra() async {
    if (alunoSelecionado == null || pacoteSelecionado == null) return;
    setState(() => salvando = true);
    try {
      final pac = pacotesDisponiveis.firstWhere(
        (p) => p['nome_pacote'] == pacoteSelecionado,
      );
      double valorTotal = double.tryParse(pac['valor_total'].toString()) ?? 0.0;
      String dataIniStr =
          "${dataInicio.day.toString().padLeft(2, '0')}/${dataInicio.month.toString().padLeft(2, '0')}/${dataInicio.year}";
      String dataFimStr =
          "${dataFim.day.toString().padLeft(2, '0')}/${dataFim.month.toString().padLeft(2, '0')}/${dataFim.year}";

      final pacoteComprado = await supabase
          .from('pacotes_comprados')
          .insert({
            'aluno': alunoSelecionado,
            'pacote': pacoteSelecionado,
            'data_inicio': dataIniStr,
            'data_fim': dataFimStr,
            'valor_total': valorTotal,
            'qtd_aulas_total':
                int.tryParse(pac['qtd_aulas']?.toString() ?? '') ?? 1,
            'duracao_min':
                int.tryParse(pac['duracao_min']?.toString() ?? '') ?? 60,
            'status_pacote': 'Aberto',
          })
          .select()
          .single();

      double valorMetade = valorTotal / 2.0;
      await supabase.from('cobrancas').insert([
        {
          'aluno': alunoSelecionado,
          'descricao': 'Sinal 50% - $pacoteSelecionado ($alunoSelecionado)',
          'valor': valorMetade,
          'vencimento': dataInicio.toString().substring(0, 10),
          'status': 'Pendente',
          'pacote_compra_id': pacoteComprado['id'],
        },
        {
          'aluno': alunoSelecionado,
          'descricao': 'Quitação 50% - $pacoteSelecionado ($alunoSelecionado)',
          'valor': valorMetade,
          'vencimento': dataFim.toString().substring(0, 10),
          'status': 'Pendente',
          'pacote_compra_id': pacoteComprado['id'],
        },
      ]);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Pacote comprado com sucesso! 2 cobranças de 50% geradas.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Erro: $e')));
    } finally {
      if (mounted) setState(() => salvando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return carregando
        ? const Center(child: CircularProgressIndicator())
        : SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                alunos.isEmpty
                    ? const Text(
                        'Cadastre alunos primeiro.',
                        style: TextStyle(color: Colors.red),
                      )
                    : DropdownButtonFormField<String>(
                        value: alunoSelecionado,
                        decoration: const InputDecoration(
                          labelText: 'Aluno',
                          border: OutlineInputBorder(),
                        ),
                        items: alunos
                            .map(
                              (a) => DropdownMenuItem(
                                value: a['nome'].toString(),
                                child: Text(a['nome'].toString()),
                              ),
                            )
                            .toList(),
                        onChanged: (v) => setState(() => alunoSelecionado = v),
                      ),
                const SizedBox(height: 14),
                pacotesDisponiveis.isEmpty
                    ? const Text(
                        'Cadastre pacotes/modalidades com mais de 1 aula na aba Preços.',
                        style: TextStyle(color: Colors.red),
                      )
                    : DropdownButtonFormField<String>(
                        value: pacoteSelecionado,
                        decoration: const InputDecoration(
                          labelText: 'Pacote Disponível',
                          border: OutlineInputBorder(),
                        ),
                        items: pacotesDisponiveis
                            .map(
                              (p) => DropdownMenuItem(
                                value: p['nome_pacote'].toString(),
                                child: Text(p['nome_pacote'].toString()),
                              ),
                            )
                            .toList(),
                        onChanged: (v) {
                          setState(() => pacoteSelecionado = v);
                          atualizarDataFim();
                        },
                      ),
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: dataInicio,
                      firstDate: DateTime(2025),
                      lastDate: DateTime(2030),
                    );
                    if (picked != null) {
                      setState(() => dataInicio = picked);
                      atualizarDataFim();
                    }
                  },
                  icon: const Icon(Icons.calendar_month),
                  label: Text(
                    'Início: ${dataInicio.toString().substring(0, 10)}',
                  ),
                ),
                const SizedBox(height: 14),
                InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Fim Calculado (Automático)',
                    border: OutlineInputBorder(),
                  ),
                  child: Text(
                    dataFim.toString().substring(0, 10),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed:
                      salvando || alunos.isEmpty || pacotesDisponiveis.isEmpty
                      ? null
                      : confirmarCompra,
                  child: Text(
                    salvando
                        ? 'Processando...'
                        : '💳 Confirmar Compra (Gera 2x 50%)',
                  ),
                ),
              ],
            ),
          );
  }
}

// ================= TELA 4: GESTÃO MASTER =================
class TelaGestaoMasterMobile extends StatelessWidget {
  const TelaGestaoMasterMobile({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 5,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Painel de Gestão'),
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'Pacotes em Aberto'),
              Tab(text: 'Controle de Aulas'),
              Tab(text: 'Cobranças'),
              Tab(text: 'Resumo Fin.'),
              Tab(text: 'Evolução'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            OpenPackagesTab(),
            AbaControleAulasMobile(),
            AbaCobrancasMobile(),
            AbaResumoGanhosMobile(),
            AbaEvolucaoGanhosMobile(),
          ],
        ),
      ),
    );
  }
}

class AbaControleAulasMobile extends StatefulWidget {
  const AbaControleAulasMobile({super.key});

  @override
  State<AbaControleAulasMobile> createState() => _AbaControleAulasMobileState();
}

class _AbaControleAulasMobileState extends State<AbaControleAulasMobile> {
  final supabase = Supabase.instance.client;
  final calendarSync = GoogleCalendarSyncService.instance;
  final scheduling = SchedulingService.instance;
  List<Map<String, dynamic>> aulas = [];
  bool carregando = true;
  String filtroStatus = 'Agendada';

  @override
  void initState() {
    super.initState();
    carregarAulas();
  }

  Future<void> carregarAulas() async {
    try {
      await scheduling.completePastLessons();
      final statusConsulta = filtroStatus == 'Automáticas'
          ? 'Realizada'
          : filtroStatus;
      final res = await supabase
          .from('aulas')
          .select()
          .eq('status_aula', statusConsulta);
      List<Map<String, dynamic>> lista = List<Map<String, dynamic>>.from(res);
      if (filtroStatus == 'Automáticas') {
        lista = lista
            .where((aula) => aula['confirmacao_automatica'] == true)
            .toList();
      }

      lista.sort((a, b) {
        try {
          DateTime dtA = DateTime.parse(
            a['data_aula'].split('/').reversed.join('-'),
          );
          DateTime dtB = DateTime.parse(
            b['data_aula'].split('/').reversed.join('-'),
          );
          int cmp = dtA.compareTo(dtB);
          if (cmp != 0) return cmp;
          return (a['horario'] ?? '00:00').compareTo(b['horario'] ?? '00:00');
        } catch (_) {
          return 0;
        }
      });

      if (!mounted) return;
      setState(() {
        aulas = lista;
        carregando = false;
      });
    } catch (_) {
      if (mounted) setState(() => carregando = false);
    }
  }

  Future<void> editarAula(Map<String, dynamic> aula) async {
    final assuntoCtrl = TextEditingController(text: aula['assunto'] ?? '');
    DateTime dataSel = DateTime.now();
    try {
      dataSel = DateTime.parse(aula['data_aula'].split('/').reversed.join('-'));
    } catch (_) {}

    TimeOfDay horaSel = const TimeOfDay(hour: 14, minute: 0);
    try {
      final partes = (aula['horario'] ?? '14:00').split(':');
      horaSel = TimeOfDay(
        hour: int.parse(partes[0]),
        minute: int.parse(partes[1]),
      );
    } catch (_) {}

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateModal) => AlertDialog(
          title: Text('Editar Aula: ${aula['aluno']}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              OutlinedButton.icon(
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: dataSel,
                    firstDate: DateTime(2025),
                    lastDate: DateTime(2030),
                  );
                  if (picked != null) setStateModal(() => dataSel = picked);
                },
                icon: const Icon(Icons.calendar_month),
                label: Text('Data: ${dataSel.toString().substring(0, 10)}'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () async {
                  final picked = await showTimePicker(
                    context: context,
                    initialTime: horaSel,
                  );
                  if (picked != null) setStateModal(() => horaSel = picked);
                },
                icon: const Icon(Icons.access_time),
                label: Text('Horário: ${horaSel.format(context)}'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: assuntoCtrl,
                decoration: const InputDecoration(labelText: 'Assunto'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () async {
                final duration = await scheduling.lessonDuration(aula);
                final originalStart = scheduling.parseLessonStart(aula);
                final selectedStart = DateTime(
                  dataSel.year,
                  dataSel.month,
                  dataSel.day,
                  horaSel.hour,
                  horaSel.minute,
                );
                var targets = <Map<String, dynamic>>[aula];
                final serieId = aula['serie_id']?.toString();
                if (serieId != null && serieId.isNotEmpty) {
                  final scope = await showDialog<String>(
                    context: context,
                    builder: (scopeContext) => AlertDialog(
                      title: const Text('Editar aulas fixas'),
                      content: const Text(
                        'Esta aula faz parte de uma sequência. '
                        'Onde deseja aplicar a alteração?',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(scopeContext),
                          child: const Text('Cancelar'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(scopeContext, 'uma'),
                          child: const Text('Somente esta'),
                        ),
                        TextButton(
                          onPressed: () =>
                              Navigator.pop(scopeContext, 'futuras'),
                          child: const Text('Esta e as próximas'),
                        ),
                        ElevatedButton(
                          onPressed: () => Navigator.pop(scopeContext, 'todas'),
                          child: const Text('Toda a sequência'),
                        ),
                      ],
                    ),
                  );
                  if (scope == null || !context.mounted) return;
                  final response = await supabase
                      .from('aulas')
                      .select()
                      .eq('serie_id', serieId);
                  final series = List<Map<String, dynamic>>.from(response);
                  targets = series.where((item) {
                    if (scope == 'todas') return true;
                    if (scope == 'uma') return item['id'] == aula['id'];
                    final start = scheduling.parseLessonStart(item);
                    return originalStart != null &&
                        start != null &&
                        !start.isBefore(originalStart);
                  }).toList();
                }

                final delta = originalStart == null
                    ? Duration.zero
                    : selectedStart.difference(originalStart);
                final newStarts = <dynamic, DateTime>{};
                for (final target in targets) {
                  final oldStart = scheduling.parseLessonStart(target);
                  if (target['id'] == aula['id']) {
                    newStarts[target['id']] = selectedStart;
                  } else if (oldStart != null) {
                    newStarts[target['id']] = oldStart.add(delta);
                  }
                }
                final requested = targets
                    .where((target) => newStarts[target['id']] != null)
                    .map(
                      (target) => LessonSlot(
                        start: newStarts[target['id']]!,
                        durationMinutes:
                            int.tryParse(
                              target['duracao_min']?.toString() ?? '',
                            ) ??
                            duration,
                        label: target['aluno']?.toString(),
                      ),
                    )
                    .toList();
                final conflicts = await scheduling.findConflicts(
                  requested,
                  excludeLessonIds: targets.map((item) => item['id']).toSet(),
                );
                if (conflicts.isNotEmpty) {
                  if (!context.mounted) return;
                  final existing = conflicts.first.existing;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Horário ocupado por ${existing['aluno'] ?? 'outra aula'} '
                        'às ${existing['horario'] ?? ''}. Escolha outro horário.',
                      ),
                    ),
                  );
                  return;
                }

                var syncErrors = 0;
                for (final target in targets) {
                  final newStart = newStarts[target['id']];
                  if (newStart == null) continue;
                  final aulaAtualizada = await supabase
                      .from('aulas')
                      .update({
                        'data_aula': scheduling.formatDate(newStart),
                        'horario': scheduling.formatTime(newStart),
                        'assunto': assuntoCtrl.text.trim(),
                        'google_sync_status': 'pendente',
                        'google_sync_action': 'upsert',
                        'google_sync_error': null,
                      })
                      .eq('id', target['id'])
                      .select()
                      .single();
                  try {
                    await calendarSync.syncLesson(aulaAtualizada);
                  } catch (_) {
                    syncErrors++;
                  }
                }

                final mensagem = syncErrors == 0
                    ? '${targets.length} aula(s) atualizada(s) no app e no Google Agenda.'
                    : '${targets.length} aula(s) atualizada(s); $syncErrors sincronização(ões) ficaram pendentes.';

                if (context.mounted) Navigator.pop(context);
                carregarAulas();
                if (context.mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text(mensagem)));
                }
              },
              child: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> resolverAulaEmRevisao(Map<String, dynamic> aula) async {
    final escolha = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Revisar aula de ${aula['aluno']}'),
        content: Text(
          '${aula['data_aula']} às ${aula['horario']}\n\n'
          'Escolha o que realmente aconteceu com esta aula.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, 'cancelar'),
            child: const Text('Cancelada sem cobrança'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, 'falta'),
            child: const Text('Falta sem aviso'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, 'realizada'),
            child: const Text('Realizada'),
          ),
        ],
      ),
    );
    if (escolha == null) return;

    try {
      if (escolha == 'cancelar') {
        await calendarSync.requestLessonDeletion(aula);
      } else if (escolha == 'falta') {
        await supabase
            .from('aulas')
            .update({
              'status_aula': 'Falta sem Aviso',
              'confirmacao_automatica': false,
              'google_sync_status': 'pendente',
              'google_sync_action': 'upsert',
            })
            .eq('id', aula['id']);
      } else {
        await supabase
            .from('aulas')
            .update({
              'status_aula': 'Realizada',
              'confirmacao_automatica': false,
              'realizada_em': DateTime.now().toIso8601String(),
            })
            .eq('id', aula['id']);
      }
      await carregarAulas();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erro ao revisar aula: $error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(50),
        child: Container(
          color: Colors.white,
          alignment: Alignment.center,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                ChoiceChip(
                  label: const Text('Agendadas'),
                  selected: filtroStatus == 'Agendada',
                  onSelected: (sel) {
                    if (sel) {
                      setState(() => filtroStatus = 'Agendada');
                      carregarAulas();
                    }
                  },
                ),
                const SizedBox(width: 10),
                ChoiceChip(
                  label: const Text('Realizadas'),
                  selected: filtroStatus == 'Realizada',
                  onSelected: (sel) {
                    if (sel) {
                      setState(() => filtroStatus = 'Realizada');
                      carregarAulas();
                    }
                  },
                ),
                const SizedBox(width: 10),
                ChoiceChip(
                  label: const Text('Automáticas'),
                  selected: filtroStatus == 'Automáticas',
                  onSelected: (sel) {
                    if (sel) {
                      setState(() => filtroStatus = 'Automáticas');
                      carregarAulas();
                    }
                  },
                ),
                const SizedBox(width: 10),
                ChoiceChip(
                  label: const Text('Revisar'),
                  selected: filtroStatus == 'Revisar',
                  onSelected: (sel) {
                    if (sel) {
                      setState(() => filtroStatus = 'Revisar');
                      carregarAulas();
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ),
      body: carregando
          ? const Center(child: CircularProgressIndicator())
          : aulas.isEmpty
          ? Center(child: Text('Nenhuma aula $filtroStatus.'))
          : ListView.builder(
              itemCount: aulas.length,
              itemBuilder: (context, index) {
                final a = aulas[index];
                return Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  child: ListTile(
                    title: Text(
                      '${a['aluno']} - ${a['disciplina']}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      'Data: ${a['data_aula']} às ${a['horario']}\nAssunto: ${a['assunto'] ?? ''}\nStatus: ${a['status_aula']}',
                    ),
                    trailing: filtroStatus == 'Revisar'
                        ? IconButton(
                            tooltip: 'Definir situação correta',
                            icon: const Icon(
                              Icons.fact_check,
                              color: Colors.orange,
                            ),
                            onPressed: () => resolverAulaEmRevisao(a),
                          )
                        : filtroStatus == 'Automáticas' &&
                              a['confirmacao_automatica'] == true
                        ? IconButton(
                            tooltip: 'Desfazer confirmação automática',
                            icon: const Icon(Icons.undo, color: Colors.orange),
                            onPressed: () async {
                              await scheduling.undoAutomaticCompletion(a['id']);
                              await carregarAulas();
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Confirmação desfeita. A aula foi enviada para Revisar.',
                                  ),
                                ),
                              );
                            },
                          )
                        : IconButton(
                            icon: const Icon(Icons.edit, color: Colors.indigo),
                            onPressed: () => editarAula(a),
                          ),
                    isThreeLine: true,
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: carregarAulas,
        tooltip: 'Atualizar',
        child: const Icon(Icons.refresh),
      ),
    );
  }
}

class AbaCobrancasMobile extends StatefulWidget {
  const AbaCobrancasMobile({super.key});

  @override
  State<AbaCobrancasMobile> createState() => _AbaCobrancasMobileState();
}

class _AbaCobrancasMobileState extends State<AbaCobrancasMobile> {
  final supabase = Supabase.instance.client;
  List<Map<String, dynamic>> cobrancas = [];
  bool carregando = true;
  String filtroStatusCob = 'Todas';

  @override
  void initState() {
    super.initState();
    carregarCobrancas();
  }

  Future<void> carregarCobrancas() async {
    try {
      var query = supabase.from('cobrancas').select();
      if (filtroStatusCob != 'Todas') {
        query = query.eq('status', filtroStatusCob);
      }
      final res = await query;
      List<Map<String, dynamic>> lista = List<Map<String, dynamic>>.from(res);

      // Ordem cronológica por data de vencimento
      lista.sort((a, b) {
        try {
          DateTime dtA = DateTime.parse(
            a['vencimento'].split('/').reversed.join('-'),
          );
          DateTime dtB = DateTime.parse(
            b['vencimento'].split('/').reversed.join('-'),
          );
          return dtA.compareTo(dtB);
        } catch (_) {
          return 0;
        }
      });

      if (!mounted) return;
      setState(() {
        cobrancas = lista;
        carregando = false;
      });
    } catch (_) {
      if (mounted) setState(() => carregando = false);
    }
  }

  Future<void> mudarStatusCobranca(int id, String novoStatus) async {
    await supabase
        .from('cobrancas')
        .update({'status': novoStatus})
        .eq('id', id);
    carregarCobrancas();
  }

  Future<void> excluirCobranca(int id) async {
    await supabase.from('cobrancas').delete().eq('id', id);
    carregarCobrancas();
  }

  Future<void> editarValor(Map<String, dynamic> c) async {
    final controller = TextEditingController(text: c['valor'].toString());
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Editar Valor da Cobrança'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Novo Valor (R\$)'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              double? val = double.tryParse(
                controller.text.replaceAll(',', '.'),
              );
              if (val != null) {
                await supabase
                    .from('cobrancas')
                    .update({'valor': val})
                    .eq('id', c['id']);
                if (context.mounted) Navigator.pop(context);
                carregarCobrancas();
              }
            },
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
  }

  Future<void> mandarCobrancaWhatsApp(Map<String, dynamic> c) async {
    final aluno = c['aluno'];
    final valor = double.tryParse(c['valor'].toString()) ?? 0.0;
    final descricao = c['descricao'] ?? '';
    final vencimento = c['vencimento'] ?? '';

    String telefone = '';
    try {
      final resAluno = await supabase
          .from('alunos')
          .select('whatsapp_resp, whatsapp_aluno')
          .eq('nome', aluno)
          .maybeSingle();
      if (resAluno != null) {
        telefone =
            resAluno['whatsapp_resp'] ?? resAluno['whatsapp_aluno'] ?? '';
      }
    } catch (_) {}

    String chavePix = '';
    try {
      final resConfig = await supabase
          .from('configuracoes_professor')
          .select('chave_pix')
          .limit(1)
          .maybeSingle();
      if (resConfig != null) {
        chavePix = resConfig['chave_pix'] ?? '';
      }
    } catch (_) {}

    String mensagemPadrao =
        'Olá! Passando para lembrar sobre a cobrança "$descricao" no valor de R\$ ${valor.toStringAsFixed(2)}, com vencimento em $vencimento.\n\nChave Pix para pagamento: ${chavePix.isNotEmpty ? chavePix : "(Não cadastrada)"}\n\nObrigado!';
    final msgController = TextEditingController(text: mensagemPadrao);

    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Cobrança: $aluno'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Personalize a mensagem:',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: msgController,
              maxLines: 6,
              decoration: const InputDecoration(border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.send, size: 16),
            label: const Text('Enviar WhatsApp'),
            onPressed: () async {
              Navigator.pop(context);
              if (telefone.isNotEmpty) {
                final numLimpo = telefone.replaceAll(RegExp(r'\D'), '');
                final url = Uri.parse(
                  'https://wa.me/55$numLimpo?text=${Uri.encodeComponent(msgController.text)}',
                );
                if (await canLaunchUrl(url)) {
                  await launchUrl(url, mode: LaunchMode.externalApplication);
                }
              } else {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('WhatsApp do aluno não cadastrado.'),
                    ),
                  );
                }
              }
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(50),
        child: Container(
          color: Colors.white,
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: ['Todas', 'Pendente', 'Pago'].map((st) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: ChoiceChip(
                  label: Text(st),
                  selected: filtroStatusCob == st,
                  onSelected: (sel) {
                    if (sel) {
                      setState(() => filtroStatusCob = st);
                      carregarCobrancas();
                    }
                  },
                ),
              );
            }).toList(),
          ),
        ),
      ),
      body: carregando
          ? const Center(child: CircularProgressIndicator())
          : cobrancas.isEmpty
          ? const Center(child: Text('Nenhuma cobrança registrada.'))
          : ListView.builder(
              itemCount: cobrancas.length,
              itemBuilder: (context, index) {
                final c = cobrancas[index];
                bool pago = c['status'] == 'Pago';
                return Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  child: ListTile(
                    title: Text(
                      c['aluno'],
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      '${c['descricao']}\nVencimento: ${c['vencimento']} | Status: ${c['status']}',
                    ),
                    trailing: PopupMenuButton<String>(
                      onSelected: (val) {
                        if (val == 'pago') mudarStatusCobranca(c['id'], 'Pago');
                        if (val == 'pendente')
                          mudarStatusCobranca(c['id'], 'Pendente');
                        if (val == 'editar') editarValor(c);
                        if (val == 'excluir') excluirCobranca(c['id']);
                        if (val == 'whatsapp') mandarCobrancaWhatsApp(c);
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'whatsapp',
                          child: Text(
                            '📱 Mandar Cobrança',
                            style: TextStyle(
                              color: Colors.green,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'pago',
                          child: Text('Marcar como Pago'),
                        ),
                        const PopupMenuItem(
                          value: 'pendente',
                          child: Text('Marcar como Pendente'),
                        ),
                        const PopupMenuItem(
                          value: 'editar',
                          child: Text('Editar Valor'),
                        ),
                        const PopupMenuItem(
                          value: 'excluir',
                          child: Text(
                            'Excluir Cobrança',
                            style: TextStyle(color: Colors.red),
                          ),
                        ),
                      ],
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            'R\$ ${double.parse(c['valor'].toString()).toStringAsFixed(2)}',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: pago ? Colors.green : Colors.orange,
                            ),
                          ),
                          Text(
                            c['status'],
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                    isThreeLine: true,
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: carregarCobrancas,
        tooltip: 'Atualizar',
        child: const Icon(Icons.refresh),
      ),
    );
  }
}

class AbaResumoGanhosMobile extends StatefulWidget {
  const AbaResumoGanhosMobile({super.key});

  @override
  State<AbaResumoGanhosMobile> createState() => _AbaResumoGanhosMobileState();
}

class _AbaResumoGanhosMobileState extends State<AbaResumoGanhosMobile> {
  final supabase = Supabase.instance.client;
  double hoje = 0.0;
  double semana = 0.0;
  double mes = 0.0;
  double ano = 0.0;
  bool carregando = true;

  @override
  void initState() {
    super.initState();
    calcularResumo();
  }

  Future<void> calcularResumo() async {
    try {
      final res = await supabase
          .from('cobrancas')
          .select()
          .eq('status', 'Pago');
      final dtHoje = DateTime.now();
      final dtInicioSemana = dtHoje.subtract(
        Duration(days: dtHoje.weekday - 1),
      );
      final dtFimSemana = dtInicioSemana.add(const Duration(days: 6));

      double tHoje = 0.0, tSem = 0.0, tMes = 0.0, tAno = 0.0;

      for (var r in res) {
        String? venc = r['vencimento'];
        double val = double.tryParse(r['valor'].toString()) ?? 0.0;
        if (venc == null || venc.length < 10) continue;

        try {
          DateTime dtObj = DateTime.parse(venc.split('/').reversed.join('-'));
          if (dtObj.year == dtHoje.year &&
              dtObj.month == dtHoje.month &&
              dtObj.day == dtHoje.day) {
            tHoje += val;
          }
          if (dtObj.isAfter(dtInicioSemana.subtract(const Duration(days: 1))) &&
              dtObj.isBefore(dtFimSemana.add(const Duration(days: 1)))) {
            tSem += val;
          }
          if (dtObj.year == dtHoje.year && dtObj.month == dtHoje.month) {
            tMes += val;
          }
          if (dtObj.year == dtHoje.year) {
            tAno += val;
          }
        } catch (_) {}
      }

      if (!mounted) return;
      setState(() {
        hoje = tHoje;
        semana = tSem;
        mes = tMes;
        ano = tAno;
        carregando = false;
      });
    } catch (_) {
      if (mounted) setState(() => carregando = false);
    }
  }

  Widget cardGanho(String titulo, double valor, Color cor) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              titulo,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.grey,
              ),
            ),
            Text(
              'R\$ ${valor.toStringAsFixed(2)}',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: cor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: carregando
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.symmetric(vertical: 16),
              children: [
                cardGanho('Ganho Hoje', hoje, Colors.blue),
                cardGanho('Ganho Esta Semana', semana, Colors.teal),
                cardGanho('Ganho Este Mês', mes, Colors.green),
                cardGanho('Ganho Este Ano', ano, Colors.purple),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: calcularResumo,
        tooltip: 'Atualizar',
        child: const Icon(Icons.refresh),
      ),
    );
  }
}

class AbaEvolucaoGanhosMobile extends StatefulWidget {
  const AbaEvolucaoGanhosMobile({super.key});

  @override
  State<AbaEvolucaoGanhosMobile> createState() =>
      _AbaEvolucaoGanhosMobileState();
}

class _AbaEvolucaoGanhosMobileState extends State<AbaEvolucaoGanhosMobile> {
  final supabase = Supabase.instance.client;
  List<Map<String, dynamic>> evolucao = [];
  bool carregando = true;
  String escalaSel = "Mensal";

  final List<String> mesesNomes = [
    '',
    'Jan',
    'Fev',
    'Mar',
    'Abr',
    'Mai',
    'Jun',
    'Jul',
    'Ago',
    'Set',
    'Out',
    'Nov',
    'Dez',
  ];

  @override
  void initState() {
    super.initState();
    calcularEvolucao();
  }

  Future<void> calcularEvolucao() async {
    try {
      final res = await supabase
          .from('cobrancas')
          .select()
          .eq('status', 'Pago');
      Map<String, Map<String, dynamic>> agrupado = {};

      for (var r in res) {
        String? venc = r['vencimento'];
        double val = double.tryParse(r['valor'].toString()) ?? 0.0;
        if (venc == null || venc.length < 10) continue;

        try {
          DateTime dtObj = DateTime.parse(venc.split('/').reversed.join('-'));
          String chaveSort = "";
          String label = "";

          if (escalaSel == "Diária") {
            chaveSort =
                "${dtObj.year}${dtObj.month.toString().padLeft(2, '0')}${dtObj.day.toString().padLeft(2, '0')}";
            label =
                "${dtObj.day.toString().padLeft(2, '0')}/${dtObj.month.toString().padLeft(2, '0')}/${dtObj.year}";
          } else if (escalaSel == "Semanal") {
            int semanaNum = ((dtObj.day - 1) ~/ 7) + 1;
            chaveSort =
                "${dtObj.year}${dtObj.month.toString().padLeft(2, '0')}$semanaNum";
            label = "${semanaNum}ª S ${mesesNomes[dtObj.month]} ${dtObj.year}";
          } else if (escalaSel == "Mensal") {
            chaveSort =
                "${dtObj.year}${dtObj.month.toString().padLeft(2, '0')}";
            label = "${mesesNomes[dtObj.month]} ${dtObj.year}";
          } else if (escalaSel == "Bimestral") {
            int bimestre = ((dtObj.month - 1) ~/ 2) + 1;
            int mInicio = (bimestre - 1) * 2 + 1;
            int mFim = mInicio + 1;
            chaveSort = "${dtObj.year}$bimestre";
            label = "${mesesNomes[mInicio]}-${mesesNomes[mFim]} ${dtObj.year}";
          } else if (escalaSel == "Trimestral") {
            int trimestre = ((dtObj.month - 1) ~/ 3) + 1;
            int mInicio = (trimestre - 1) * 3 + 1;
            int mFim = mInicio + 2;
            chaveSort = "${dtObj.year}$trimestre";
            label = "${mesesNomes[mInicio]}-${mesesNomes[mFim]} ${dtObj.year}";
          } else if (escalaSel == "Semestral") {
            int semestre = dtObj.month <= 6 ? 1 : 2;
            int mInicio = semestre == 1 ? 1 : 7;
            int mFim = semestre == 1 ? 6 : 12;
            chaveSort = "${dtObj.year}$semestre";
            label = "${mesesNomes[mInicio]}-${mesesNomes[mFim]} ${dtObj.year}";
          } else if (escalaSel == "Anual") {
            chaveSort = "${dtObj.year}";
            label = "${dtObj.year}";
          }

          if (!agrupado.containsKey(chaveSort)) {
            agrupado[chaveSort] = {
              'sort': chaveSort,
              'periodo': label,
              'total': 0.0,
            };
          }
          agrupado[chaveSort]!['total'] += val;
        } catch (_) {}
      }

      List<Map<String, dynamic>> lista = agrupado.values.toList();
      lista.sort((a, b) => b['sort'].compareTo(a['sort']));

      if (!mounted) return;
      setState(() {
        evolucao = lista.take(30).toList();
        carregando = false;
      });
    } catch (_) {
      if (mounted) setState(() => carregando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(60),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
          color: Colors.white,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children:
                  [
                    "Diária",
                    "Semanal",
                    "Mensal",
                    "Bimestral",
                    "Trimestral",
                    "Semestral",
                    "Anual",
                  ].map((escala) {
                    bool selecionado = escalaSel == escala;
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: ChoiceChip(
                        label: Text(escala),
                        selected: selecionado,
                        onSelected: (bool selected) {
                          if (selected) {
                            setState(() => escalaSel = escala);
                            calcularEvolucao();
                          }
                        },
                      ),
                    );
                  }).toList(),
            ),
          ),
        ),
      ),
      body: carregando
          ? const Center(child: CircularProgressIndicator())
          : evolucao.isEmpty
          ? const Center(child: Text('Nenhum ganho registrado no período.'))
          : ListView.builder(
              itemCount: evolucao.length,
              itemBuilder: (context, index) {
                final item = evolucao[index];
                return Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  child: ListTile(
                    title: Text(
                      item['periodo'],
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    trailing: Text(
                      'R\$ ${item['total'].toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                        fontSize: 16,
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
