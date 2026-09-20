import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

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
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final text = newValue.text.replaceAll(RegExp(r'\D'), '');
    String formatted = '';
    if (text.isNotEmpty) {
      formatted += '(${text.substring(0, text.length >= 2 ? 2 : text.length)}';
    }
    if (text.length >= 3) {
      formatted += ') ${text.substring(2, text.length >= 7 ? 7 : text.length)}';
    }
    if (text.length >= 8) {
      formatted += '-${text.substring(7, text.length >= 11 ? 11 : text.length)}';
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

  // Removida a tela de Ajustes, restando 4 abas principais
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
          BottomNavigationBarItem(icon: Icon(Icons.calendar_today), label: 'Agenda'),
          BottomNavigationBarItem(icon: Icon(Icons.attach_money), label: 'Preços'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Alunos'),
          BottomNavigationBarItem(icon: Icon(Icons.assessment), label: 'Gestão'),
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
  List<Map<String, dynamic>> aulas = [];
  bool carregando = true;

  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['https://www.googleapis.com/auth/calendar.events'],
  );

  @override
  void initState() {
    super.initState();
    carregarAulas();
  }

  Future<void> carregarAulas() async {
    try {
      final response = await supabase
          .from('aulas')
          .select()
          .eq('status_aula', 'Agendada');
      
      List<Map<String, dynamic>> lista = List<Map<String, dynamic>>.from(response);

      lista.sort((a, b) {
        try {
          DateTime dtA = DateTime.parse(a['data_aula'].split('/').reversed.join('-'));
          DateTime dtB = DateTime.parse(b['data_aula'].split('/').reversed.join('-'));
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

  Future<void> adicionarAoGoogleCalendar({
    required String titulo,
    required String descricao,
    required DateTime inicio,
    required DateTime fim,
  }) async {
    try {
      GoogleSignInAccount? account = _googleSignIn.currentUser;
      account ??= await _googleSignIn.signIn();

      if (account == null) return;

      final auth = await account.authHeaders;
      final accessToken = auth['Authorization'];

      if (accessToken == null) return;

      final url = Uri.parse('https://www.googleapis.com/calendar/v3/calendars/primary/events');
      
      final body = jsonEncode({
        'summary': titulo,
        'description': descricao,
        'start': {'dateTime': inicio.toIso8601String(), 'timeZone': 'America/Sao_Paulo'},
        'end': {'dateTime': fim.toIso8601String(), 'timeZone': 'America/Sao_Paulo'},
      });

      await http.post(
        url,
        headers: {
          'Authorization': accessToken,
          'Content-Type': 'application/json',
        },
        body: body,
      );
    } catch (e) {
      debugPrint("Erro ao sincronizar com Google Calendar API: $e");
    }
  }

  Future<void> mudarStatusComRegra(int id, String novoStatus) async {
    try {
      final resAula = await supabase.from('aulas').select().eq('id', id).maybeSingle();
      if (resAula == null) return;

      String aluno = resAula['aluno'];
      String pacote = resAula['pacote'] ?? 'Avulsa';
      String dataAula = resAula['data_aula'] ?? '';

      if (novoStatus == 'Falta sem Aviso') {
        double valorFalta = 110.0;
        final resPac = await supabase.from('pacotes_professor').select().eq('nome_pacote', pacote).maybeSingle();
        if (resPac != null) {
          double total = double.tryParse(resPac['valor_total'].toString()) ?? 110.0;
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

        await supabase.from('aulas').delete().eq('id', id);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Falta registrada e convertida em cobrança financeira.')));
      } else if (novoStatus == 'Cancelada com Reposição') {
        await supabase.from('creditos_reposicao').insert({
          'aluno': aluno,
          'detalhes': 'Reposição gerada por cancelamento em $dataAula',
          'status': 'Disponível',
        });
        await supabase.from('aulas').delete().eq('id', id);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Crédito de reposição gerado e aula removida.')));
      } else if (novoStatus == 'Cancelada sem Cobrança') {
        await supabase.from('aulas').delete().eq('id', id);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Aula cancelada sem ônus.')));
      } else {
        await supabase.from('aulas').update({'status_aula': 'Realizada'}).eq('id', id);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Aula marcada como Realizada!')));
      }

      carregarAulas();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e')));
    }
  }

  void abrirModalNovaAula() async {
    List<Map<String, dynamic>> listaAlunos = [];
    try {
      final resAlunos = await supabase.from('alunos').select('nome');
      listaAlunos = List<Map<String, dynamic>>.from(resAlunos);
    } catch (_) {}

    if (!mounted) return;

    String? alunoSelecionado = listaAlunos.isNotEmpty ? listaAlunos.first['nome']?.toString() : null;
    List<String> modalidadesAluno = ['Avulsa 1h'];
    String? modalidadeSelecionada = 'Avulsa 1h';
    String disciplina = 'Química';
    DateTime dataSel = DateTime.now();
    TimeOfDay horaSel = const TimeOfDay(hour: 14, minute: 0);
    
    List<String> assuntosDisponiveis = [];
    String? assuntoSelecionado;
    final novoAssuntoCtrl = TextEditingController();

    Future<void> carregarAssuntosDinamicos(String disc, StateSetter setStateModal) async {
      try {
        final resTopicos = await supabase.from('topicos').select('assunto').eq('disciplina', disc);
        List<String> tops = resTopicos.map<String>((t) => t['assunto'].toString()).toList();
        setStateModal(() {
          assuntosDisponiveis = tops;
          assuntoSelecionado = tops.isNotEmpty ? tops.first : null;
        });
      } catch (_) {}
    }

    Future<void> atualizarModalidades(String aluno, StateSetter setStateModal) async {
      List<String> opcs = [];
      try {
        final resPacs = await supabase.from('pacotes_professor').select('nome_pacote, qtd_aulas').eq('ativo', true);
        for (var p in resPacs) {
          if ((p['qtd_aulas'] ?? 1) == 1) opcs.add(p['nome_pacote'].toString());
        }
        final resComprados = await supabase.from('pacotes_comprados').select('pacote').eq('aluno', aluno);
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
                    ? const Text('Cadastre alunos primeiro.', style: TextStyle(color: Colors.red))
                    : DropdownButtonFormField<String>(
                        value: alunoSelecionado,
                        decoration: const InputDecoration(labelText: 'Aluno'),
                        items: listaAlunos.map((a) => DropdownMenuItem(value: a['nome'].toString(), child: Text(a['nome'].toString()))).toList(),
                        onChanged: (v) async {
                          setStateModal(() => alunoSelecionado = v);
                          if (v != null) await atualizarModalidades(v, setStateModal);
                        },
                      ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: modalidadeSelecionada,
                  decoration: const InputDecoration(labelText: 'Modalidade (Avulsa ou Pacote)'),
                  items: modalidadesAluno.map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
                  onChanged: (v) => setStateModal(() => modalidadeSelecionada = v),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: disciplina,
                  decoration: const InputDecoration(labelText: 'Disciplina'),
                  items: DISCIPLINAS.map((d) => DropdownMenuItem(value: d, child: Text(d))).toList(),
                  onChanged: (v) async {
                    if (v != null) {
                      setStateModal(() => disciplina = v);
                      await carregarAssuntosDinamicos(v, setStateModal);
                    }
                  },
                ),
                const SizedBox(height: 10),
                assuntosDisponiveis.isEmpty
                    ? const Text('Nenhum assunto cadastrado para esta disciplina.')
                    : DropdownButtonFormField<String>(
                        value: assuntoSelecionado,
                        decoration: const InputDecoration(labelText: 'Assunto do Acervo'),
                        items: assuntosDisponiveis.map((as) => DropdownMenuItem(value: as, child: Text(as))).toList(),
                        onChanged: (v) => setStateModal(() => assuntoSelecionado = v),
                      ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: novoAssuntoCtrl,
                        decoration: const InputDecoration(labelText: 'Ou cadastrar novo assunto'),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add_circle, color: Colors.indigo),
                      onPressed: () async {
                        String novo = novoAssuntoCtrl.text.trim();
                        if (novo.isNotEmpty) {
                          try {
                            await supabase.from('topicos').insert({'disciplina': disciplina, 'assunto': novo});
                            novoAssuntoCtrl.clear();
                            await carregarAssuntosDinamicos(disciplina, setStateModal);
                            setStateModal(() => assuntoSelecionado = novo);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Assunto adicionado e salvo com sucesso!')));
                            }
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao salvar assunto: $e')));
                            }
                          }
                        }
                      },
                    )
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
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
            ElevatedButton(
              onPressed: listaAlunos.isEmpty || alunoSelecionado == null
                  ? null
                  : () async {
                      String assuntoFinal = assuntoSelecionado ?? 'Geral';
                      if (modalidadeSelecionada != null && !modalidadeSelecionada!.startsWith('Avulsa')) {
                        final resPacInfo = await supabase.from('pacotes_professor').select('qtd_aulas').eq('nome_pacote', modalidadeSelecionada!).maybeSingle();
                        if (resPacInfo != null) {
                          int qtdMax = int.tryParse(resPacInfo['qtd_aulas'].toString()) ?? 1;
                          final resAulasCad = await supabase.from('aulas').select('id').eq('aluno', alunoSelecionado!).eq('pacote', modalidadeSelecionada!);
                          int jaCadastradas = resAulasCad.length;
                          if (jaCadastradas >= qtdMax) {
                            if (!context.mounted) return;
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Limite de aulas deste pacote esgotado!')));
                            return;
                          }
                        }
                      }

                      String dataStr = "${dataSel.day.toString().padLeft(2, '0')}/${dataSel.month.toString().padLeft(2, '0')}/${dataSel.year}";
                      String horaStr = "${horaSel.hour.toString().padLeft(2, '0')}:${horaSel.minute.toString().padLeft(2, '0')}";

                      if (modalidadeSelecionada != null && modalidadeSelecionada!.startsWith('Avulsa')) {
                        double valAvulsa = 110.0;
                        final resPac = await supabase.from('pacotes_professor').select('valor_total').eq('nome_pacote', modalidadeSelecionada!).maybeSingle();
                        if (resPac != null) valAvulsa = double.tryParse(resPac['valor_total'].toString()) ?? 110.0;

                        await supabase.from('cobrancas').insert({
                          'aluno': alunoSelecionado,
                          'descricao': 'Aula Avulsa $disciplina ($dataStr) - $alunoSelecionado',
                          'valor': valAvulsa,
                          'vencimento': DateTime.now().toString().substring(0, 10),
                          'status': 'Pendente',
                        });
                      }

                      await supabase.from('aulas').insert({
                        'aluno': alunoSelecionado,
                        'pacote': modalidadeSelecionada ?? 'Avulsa',
                        'disciplina': disciplina,
                        'data_aula': dataStr,
                        'horario': horaStr,
                        'assunto': assuntoFinal,
                        'status_aula': 'Agendada',
                      });

                      try {
                        final DateTime horaInicio = DateTime(dataSel.year, dataSel.month, dataSel.day, horaSel.hour, horaSel.minute);
                        final DateTime horaFim = horaInicio.add(const Duration(hours: 1));
                        await adicionarAoGoogleCalendar(
                          titulo: 'Aula de $disciplina - $alunoSelecionado',
                          descricao: 'Assunto: $assuntoFinal | Modalidade: $modalidadeSelecionada',
                          inicio: horaInicio,
                          fim: horaFim,
                        );
                      } catch (e) {
                        debugPrint("Erro ao enviar para Google Agenda: $e");
                      }

                      if (!mounted) return;
                      Navigator.pop(context);
                      carregarAulas();
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Aula agendada e salva no Google Agenda!')));
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
        title: const Text('Agenda (Aulas Futuras)'),
        actions: [
          IconButton(
            icon: const Icon(Icons.login),
            tooltip: 'Conectar Google Conta',
            onPressed: () async {
              try {
                await _googleSignIn.signIn();
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Conta Google conectada com sucesso!')));
              } catch (e) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao conectar: $e')));
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
                      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('${a['aluno']}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                Text('${a['data_aula']} às ${a['horario']}', style: const TextStyle(color: Colors.blueGrey, fontWeight: FontWeight.w600)),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text('Disciplina: ${a['disciplina']} | Assunto: ${a['assunto']}'),
                            Text('Modalidade: ${a['pacote']}'),
                            const Divider(height: 16),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                // WhatsApp removido daqui conforme solicitado
                                TextButton.icon(
                                  onPressed: () => mudarStatusComRegra(a['id'], 'Realizada'),
                                  icon: const Icon(Icons.check, color: Colors.indigo, size: 18),
                                  label: const Text('Realizada'),
                                ),
                                PopupMenuButton<String>(
                                  onSelected: (val) => mudarStatusComRegra(a['id'], val),
                                  itemBuilder: (context) => [
                                    const PopupMenuItem(value: 'Falta sem Aviso', child: Text('Falta (Gera Cobrança)')),
                                    const PopupMenuItem(value: 'Cancelada com Reposição', child: Text('Cancelar c/ Reposição')),
                                    const PopupMenuItem(value: 'Cancelada sem Cobrança', child: Text('Cancelar s/ Cobrança')),
                                  ],
                                  child: const Text('Outros', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
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
        onPressed: abrirModalNovaAula,
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
      final response = await supabase.from('pacotes_professor').select().eq('ativo', true).order('id', ascending: true);
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
                  margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  child: ListTile(
                    title: Text(p['nome_pacote'], style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text('Tipo: ${p['periodicidade'] ?? 'Avulsa'} | Aulas: ${p['qtd_aulas']} | ${p['duracao_min']} min'),
                    trailing: Text("R\$ ${double.parse(p['valor_total'].toString()).toStringAsFixed(2)}", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green, fontSize: 15)),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(onPressed: carregarPacotes, tooltip: 'Atualizar', child: const Icon(Icons.refresh)),
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
  final List<String> periodicidades = ["Avulsa", "Semanal", "Quinzenal", "Mensal", "Bimestral", "Trimestral", "Semestral"];
  final List<String> duracoes = ["30", "45", "60", "75", "90", "105", "120", "135", "150", "165", "180"];
  
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

  String get nomeAutomatico => '$tipoSel ${qtdAulas}x ${formatarDuracao(duracaoSel)}';

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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Modalidade "$nomeAutomatico" criada!')));
      _valorController.clear();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e')));
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
            decoration: const InputDecoration(labelText: 'Tipo / Periodicidade', border: OutlineInputBorder()),
            items: periodicidades.map((p) => DropdownMenuItem(value: p, child: Text(p))).toList(),
            onChanged: (v) => setState(() => tipoSel = v!),
          ),
          const SizedBox(height: 12),
          TextField(
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Quantidade de Aulas (1 = Avulsa)', border: OutlineInputBorder()),
            controller: TextEditingController(text: qtdAulas.toString())..selection = TextSelection.fromPosition(TextPosition(offset: qtdAulas.toString().length)),
            onChanged: (v) => setState(() => qtdAulas = int.tryParse(v) ?? 1),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: duracaoSel,
            decoration: const InputDecoration(labelText: 'Duração da Aula', border: OutlineInputBorder()),
            items: duracoes.map((d) => DropdownMenuItem(value: d, child: Text('$d minutos'))).toList(),
            onChanged: (v) => setState(() => duracaoSel = v!),
          ),
          const SizedBox(height: 12),
          InputDecorator(
            decoration: const InputDecoration(labelText: 'Nome Automático da Modalidade', border: OutlineInputBorder()),
            child: Text(nomeAutomatico, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.indigo)),
          ),
          const SizedBox(height: 12),
          TextField(controller: _valorController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Valor Total (R\$)', border: OutlineInputBorder())),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: OutlinedButton.icon(onPressed: sugerirPreco, icon: const Icon(Icons.lightbulb), label: const Text('Sugerir Preço'))),
              const SizedBox(width: 8),
              Expanded(child: ElevatedButton(onPressed: salvando ? null : salvarModalidade, child: Text(salvando ? 'Salvando...' : 'Salvar'))),
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
  State<AbaCadastrarAlunoMobile> createState() => _AbaCadastrarAlunoMobileState();
}

class _AbaCadastrarAlunoMobileState extends State<AbaCadastrarAlunoMobile> {
  final supabase = Supabase.instance.client;
  final _nomeController = TextEditingController();
  final _respController = TextEditingController();
  final _wppAlunoController = TextEditingController();
  final _wppRespController = TextEditingController();
  bool salvando = false;

  final List<String> _anos = [
    "5º Ano - Fund.", "6º Ano - Fund.", "7º Ano - Fund.", "8º Ano - Fund.", "9º Ano - Fund.",
    "1ª Série - EM", "2ª Série - EM", "3ª Série - EM", "Pré-Vestibular / Superior"
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Aluno $nome salvo!')));
      _nomeController.clear();
      _respController.clear();
      _wppAlunoController.clear();
      _wppRespController.clear();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e')));
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
          TextField(controller: _nomeController, decoration: const InputDecoration(labelText: 'Nome do Aluno', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _anoSelecionado,
            decoration: const InputDecoration(labelText: 'Ano Escolar', border: OutlineInputBorder()),
            items: _anos.map((a) => DropdownMenuItem(value: a, child: Text(a))).toList(),
            onChanged: (v) { if (v != null) setState(() => _anoSelecionado = v); },
          ),
          const SizedBox(height: 12),
          TextField(controller: _respController, decoration: const InputDecoration(labelText: 'Responsável', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          TextField(controller: _wppAlunoController, keyboardType: TextInputType.phone, inputFormatters: [PhoneInputFormatter()], decoration: const InputDecoration(labelText: 'WhatsApp Aluno', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          TextField(controller: _wppRespController, keyboardType: TextInputType.phone, inputFormatters: [PhoneInputFormatter()], decoration: const InputDecoration(labelText: 'WhatsApp Responsável', border: OutlineInputBorder())),
          const SizedBox(height: 20),
          ElevatedButton(onPressed: salvando ? null : salvarAluno, child: Text(salvando ? 'Salvando...' : 'Salvar Aluno')),
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
    "5º Ano - Fund.", "6º Ano - Fund.", "7º Ano - Fund.", "8º Ano - Fund.", "9º Ano - Fund.",
    "1ª Série - EM", "2ª Série - EM", "3ª Série - EM", "Pré-Vestibular / Superior"
  ];

  @override
  void initState() {
    super.initState();
    carregarAlunos();
  }

  Future<void> carregarAlunos() async {
    try {
      final res = await supabase.from('alunos').select().order('nome', ascending: true);
      if (!mounted) return;
      setState(() {
        alunos = List<Map<String, dynamic>>.from(res);
        carregando = false;
      });
    } catch (_) {
      if (mounted) setState(() => carregando = false);
    }
  }

  // Prontuário atualizado para listar pacotes em aberto e aulas restantes
  void abrirProntuario(Map<String, dynamic> aluno) async {
    String nome = aluno['nome'];
    List<Map<String, dynamic>> aulas = [];
    List<Map<String, dynamic>> pacotesComprados = [];
    Map<String, Map<String, dynamic>> dadosPacotesMaster = {};

    try {
      final resAulas = await supabase.from('aulas').select().eq('aluno', nome);
      aulas = List<Map<String, dynamic>>.from(resAulas);

      final resPacComp = await supabase.from('pacotes_comprados').select().eq('aluno', nome);
      pacotesComprados = List<Map<String, dynamic>>.from(resPacComp);

      final resPacs = await supabase.from('pacotes_professor').select();
      for (var p in resPacs) {
        dadosPacotesMaster[p['nome_pacote']] = p;
      }
    } catch (_) {}

    int total = aulas.length;
    int feitas = aulas.where((a) => a['status_aula'] == 'Realizada').length;

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Prontuário: $nome'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('• Ano Escolar: ${aluno['ano_escolar'] ?? '-'}'),
              Text('• Responsável: ${aluno['responsavel'] ?? '-'}'),
              Text('• Wpp Aluno: ${aluno['whatsapp_aluno'] ?? '-'}'),
              Text('• Wpp Resp.: ${aluno['whatsapp_resp'] ?? '-'}'),
              const Divider(),
              Text('• Total de Aulas: $total'),
              Text('• Aulas Realizadas: $feitas'),
              const Divider(),
              const Text('📦 Pacotes e Ciclos:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              pacotesComprados.isEmpty
                  ? const Text('Nenhum pacote contratado.')
                  : Column(
                      children: pacotesComprados.map((pc) {
                        String pacNome = pc['pacote'] ?? '';
                        var info = dadosPacotesMaster[pacNome] ?? {'qtd_aulas': 1};
                        int qtdEsperada = int.tryParse(info['qtd_aulas'].toString()) ?? 1;
                        int feitasPac = aulas.where((a) => a['pacote'] == pacNome).length;
                        int restantes = (qtdEsperada - feitasPac).clamp(0, qtdEsperada);

                        return Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.grey[100],
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('$pacNome', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo)),
                              Text('Início: ${pc['data_inicio']} | Fim: ${pc['data_fim']}'),
                              Text('Aulas Restantes: $restantes de $qtdEsperada', style: TextStyle(color: restantes > 0 ? Colors.orange[800] : Colors.green)),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Fechar')),
        ],
      ),
    );
  }

  void editarAluno(Map<String, dynamic> aluno) {
    final nomeCtrl = TextEditingController(text: aluno['nome'] ?? '');
    final respCtrl = TextEditingController(text: aluno['responsavel'] ?? '');
    final wppAlunoCtrl = TextEditingController(text: aluno['whatsapp_aluno'] ?? '');
    final wppRespCtrl = TextEditingController(text: aluno['whatsapp_resp'] ?? '');
    String anoSel = aluno['ano_escolar'] ?? '3ª Série - EM';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateModal) => AlertDialog(
          title: Text('Editar Aluno: ${aluno['nome']}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: nomeCtrl, decoration: const InputDecoration(labelText: 'Nome')),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: _anos.contains(anoSel) ? anoSel : _anos.first,
                  decoration: const InputDecoration(labelText: 'Ano Escolar'),
                  items: _anos.map((a) => DropdownMenuItem(value: a, child: Text(a))).toList(),
                  onChanged: (v) => setStateModal(() => anoSel = v!),
                ),
                const SizedBox(height: 10),
                TextField(controller: respCtrl, decoration: const InputDecoration(labelText: 'Responsável')),
                const SizedBox(height: 10),
                TextField(controller: wppAlunoCtrl, keyboardType: TextInputType.phone, inputFormatters: [PhoneInputFormatter()], decoration: const InputDecoration(labelText: 'WhatsApp Aluno')),
                const SizedBox(height: 10),
                TextField(controller: wppRespCtrl, keyboardType: TextInputType.phone, inputFormatters: [PhoneInputFormatter()], decoration: const InputDecoration(labelText: 'WhatsApp Responsável')),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
            ElevatedButton(
              onPressed: () async {
                try {
                  await supabase.from('alunos').update({
                    'nome': nomeCtrl.text.trim(),
                    'ano_escolar': anoSel,
                    'responsavel': respCtrl.text.trim(),
                    'whatsapp_aluno': wppAlunoCtrl.text.trim(),
                    'whatsapp_resp': wppRespCtrl.text.trim(),
                  }).eq('id', aluno['id']);

                  if (context.mounted) Navigator.pop(context);
                  carregarAlunos();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Aluno atualizado com sucesso!')));
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao atualizar: $e')));
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
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      child: ListTile(
                        title: Text(al['nome'], style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text('Série: ${al['ano_escolar'] ?? '-'}\nResp: ${al['responsavel'] ?? '-'}'),
                        trailing: IconButton(
                          icon: const Icon(Icons.edit, color: Colors.indigo),
                          onPressed: () => editarAluno(al),
                        ),
                        isThreeLine: true,
                        onTap: () => abrirProntuario(al),
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton(onPressed: carregarAlunos, tooltip: 'Atualizar', child: const Icon(Icons.refresh)),
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
      final resAlunos = await supabase.from('alunos').select('nome').order('nome');
      final resPacs = await supabase.from('pacotes_professor').select().eq('ativo', true);
      
      List<Map<String, dynamic>> pacs = List<Map<String, dynamic>>.from(resPacs).where((p) => (p['qtd_aulas'] ?? 1) > 1).toList();

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
      final pac = pacotesDisponiveis.firstWhere((p) => p['nome_pacote'] == pacoteSelecionado);
      String periodicidade = pac['periodicidade'] ?? 'Mensal';
      int diasAdd = 30;
      if (periodicidade == 'Semanal') diasAdd = 7;
      else if (periodicidade == 'Quinzenal') diasAdd = 15;
      else if (periodicidade == 'Mensal') diasAdd = 30;
      else if (periodicidade == 'Bimestral') diasAdd = 60;
      else if (periodicidade == 'Trimestral') diasAdd = 90;
      else if (periodicidade == 'Semestral') diasAdd = 180;

      setState(() {
        dataFim = dataInicio.add(Duration(days: diasAdd));
      });
    } catch (_) {}
  }

  Future<void> confirmarCompra() async {
    if (alunoSelecionado == null || pacoteSelecionado == null) return;
    setState(() => salvando = true);
    try {
      final pac = pacotesDisponiveis.firstWhere((p) => p['nome_pacote'] == pacoteSelecionado);
      double valorTotal = double.tryParse(pac['valor_total'].toString()) ?? 0.0;
      String dataIniStr = "${dataInicio.day.toString().padLeft(2, '0')}/${dataInicio.month.toString().padLeft(2, '0')}/${dataInicio.year}";
      String dataFimStr = "${dataFim.day.toString().padLeft(2, '0')}/${dataFim.month.toString().padLeft(2, '0')}/${dataFim.year}";

      await supabase.from('pacotes_comprados').insert({
        'aluno': alunoSelecionado,
        'pacote': pacoteSelecionado,
        'data_inicio': dataIniStr,
        'data_fim': dataFimStr,
        'valor_total': valorTotal,
      });

      double valorMetade = valorTotal / 2.0;
      await supabase.from('cobrancas').insert([
        {
          'aluno': alunoSelecionado,
          'descricao': 'Sinal 50% - $pacoteSelecionado ($alunoSelecionado)',
          'valor': valorMetade,
          'vencimento': dataInicio.toString().substring(0, 10),
          'status': 'Pendente',
        },
        {
          'aluno': alunoSelecionado,
          'descricao': 'Quitação 50% - $pacoteSelecionado ($alunoSelecionado)',
          'valor': valorMetade,
          'vencimento': dataFim.toString().substring(0, 10),
          'status': 'Pendente',
        }
      ]);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pacote comprado com sucesso! 2 cobranças de 50% geradas.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e')));
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
                    ? const Text('Cadastre alunos primeiro.', style: TextStyle(color: Colors.red))
                    : DropdownButtonFormField<String>(
                        value: alunoSelecionado,
                        decoration: const InputDecoration(labelText: 'Aluno', border: OutlineInputBorder()),
                        items: alunos.map((a) => DropdownMenuItem(value: a['nome'].toString(), child: Text(a['nome'].toString()))).toList(),
                        onChanged: (v) => setState(() => alunoSelecionado = v),
                      ),
                const SizedBox(height: 14),
                pacotesDisponiveis.isEmpty
                    ? const Text('Cadastre pacotes/modalidades com mais de 1 aula na aba Preços.', style: TextStyle(color: Colors.red))
                    : DropdownButtonFormField<String>(
                        value: pacoteSelecionado,
                        decoration: const InputDecoration(labelText: 'Pacote Disponível', border: OutlineInputBorder()),
                        items: pacotesDisponiveis.map((p) => DropdownMenuItem(value: p['nome_pacote'].toString(), child: Text(p['nome_pacote'].toString()))).toList(),
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
                  label: Text('Início: ${dataInicio.toString().substring(0, 10)}'),
                ),
                const SizedBox(height: 14),
                InputDecorator(
                  decoration: const InputDecoration(labelText: 'Fim Calculado (Automático)', border: OutlineInputBorder()),
                  child: Text(dataFim.toString().substring(0, 10), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: salvando || alunos.isEmpty || pacotesDisponiveis.isEmpty ? null : confirmarCompra,
                  child: Text(salvando ? 'Processando...' : '💳 Confirmar Compra (Gera 2x 50%)'),
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
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Painel de Gestão'),
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'Controle de Aulas'),
              Tab(text: 'Cobranças'),
              Tab(text: 'Resumo Fin.'),
              Tab(text: 'Evolução'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
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
      final res = await supabase.from('aulas').select().eq('status_aula', filtroStatus);
      List<Map<String, dynamic>> lista = List<Map<String, dynamic>>.from(res);

      lista.sort((a, b) {
        try {
          DateTime dtA = DateTime.parse(a['data_aula'].split('/').reversed.join('-'));
          DateTime dtB = DateTime.parse(b['data_aula'].split('/').reversed.join('-'));
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
      horaSel = TimeOfDay(hour: int.parse(partes[0]), minute: int.parse(partes[1]));
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
              TextField(controller: assuntoCtrl, decoration: const InputDecoration(labelText: 'Assunto')),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
            ElevatedButton(
              onPressed: () async {
                String dataStr = "${dataSel.day.toString().padLeft(2, '0')}/${dataSel.month.toString().padLeft(2, '0')}/${dataSel.year}";
                String horaStr = "${horaSel.hour.toString().padLeft(2, '0')}:${horaSel.minute.toString().padLeft(2, '0')}";

                await supabase.from('aulas').update({
                  'data_aula': dataStr,
                  'horario': horaStr,
                  'assunto': assuntoCtrl.text.trim(),
                }).eq('id', aula['id']);

                if (context.mounted) Navigator.pop(context);
                carregarAulas();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Aula atualizada com sucesso!')));
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
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(50),
        child: Container(
          color: Colors.white,
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
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
            ],
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
                      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      child: ListTile(
                        title: Text('${a['aluno']} - ${a['disciplina']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text('Data: ${a['data_aula']} às ${a['horario']}\nAssunto: ${a['assunto'] ?? ''}\nStatus: ${a['status_aula']}'),
                        trailing: IconButton(
                          icon: const Icon(Icons.edit, color: Colors.indigo),
                          onPressed: () => editarAula(a),
                        ),
                        isThreeLine: true,
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton(onPressed: carregarAulas, tooltip: 'Atualizar', child: const Icon(Icons.refresh)),
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

      lista.sort((a, b) {
        try {
          DateTime dtA = DateTime.parse(a['vencimento'].split('/').reversed.join('-'));
          DateTime dtB = DateTime.parse(b['vencimento'].split('/').reversed.join('-'));
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
    await supabase.from('cobrancas').update({'status': novoStatus}).eq('id', id);
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
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () async {
              double? val = double.tryParse(controller.text.replaceAll(',', '.'));
              if (val != null) {
                await supabase.from('cobrancas').update({'valor': val}).eq('id', c['id']);
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
      final resAluno = await supabase.from('alunos').select('whatsapp_resp, whatsapp_aluno').eq('nome', aluno).maybeSingle();
      if (resAluno != null) {
        telefone = resAluno['whatsapp_resp'] ?? resAluno['whatsapp_aluno'] ?? '';
      }
    } catch (_) {}

    String chavePix = '';
    try {
      final resConfig = await supabase.from('configuracoes_professor').select('chave_pix').limit(1).maybeSingle();
      if (resConfig != null) {
        chavePix = resConfig['chave_pix'] ?? '';
      }
    } catch (_) {}

    String mensagemPadrao = 'Olá! Passando para lembrar sobre a cobrança "$descricao" no valor de R\$ ${valor.toStringAsFixed(2)}, com vencimento em $vencimento.\n\nChave Pix para pagamento: ${chavePix.isNotEmpty ? chavePix : "(Não cadastrada)"}\n\nObrigado!';
    final msgController = TextEditingController(text: mensagemPadrao);

    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Cobrança: $aluno'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Personalize a mensagem:', style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 10),
            TextField(controller: msgController, maxLines: 6, decoration: const InputDecoration(border: OutlineInputBorder())),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          ElevatedButton.icon(
            icon: const Icon(Icons.send, size: 16),
            label: const Text('Enviar WhatsApp'),
            onPressed: () async {
              Navigator.pop(context);
              if (telefone.isNotEmpty) {
                final numLimpo = telefone.replaceAll(RegExp(r'\D'), '');
                final url = Uri.parse('https://wa.me/55$numLimpo?text=${Uri.encodeComponent(msgController.text)}');
                if (await canLaunchUrl(url)) {
                  await launchUrl(url, mode: LaunchMode.externalApplication);
                }
              } else {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('WhatsApp do aluno não cadastrado.')));
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
                      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      child: ListTile(
                        title: Text(c['aluno'], style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text('${c['descricao']}\nVencimento: ${c['vencimento']} | Status: ${c['status']}'),
                        trailing: PopupMenuButton<String>(
                          onSelected: (val) {
                            if (val == 'pago') mudarStatusCobranca(c['id'], 'Pago');
                            if (val == 'pendente') mudarStatusCobranca(c['id'], 'Pendente');
                            if (val == 'editar') editarValor(c);
                            if (val == 'excluir') excluirCobranca(c['id']);
                            if (val == 'whatsapp') mandarCobrancaWhatsApp(c);
                          },
                          itemBuilder: (context) => [
                            const PopupMenuItem(value: 'whatsapp', child: Text('📱 Mandar Cobrança', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold))),
                            const PopupMenuItem(value: 'pago', child: Text('Marcar como Pago')),
                            const PopupMenuItem(value: 'pendente', child: Text('Marcar como Pendente')),
                            const PopupMenuItem(value: 'editar', child: Text('Editar Valor')),
                            const PopupMenuItem(value: 'excluir', child: Text('Excluir Cobrança', style: TextStyle(color: Colors.red))),
                          ],
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text('R\$ ${double.parse(c['valor'].toString()).toStringAsFixed(2)}', style: TextStyle(fontWeight: FontWeight.bold, color: pago ? Colors.green : Colors.orange)),
                              Text(c['status'], style: const TextStyle(fontSize: 12, color: Colors.grey)),
                            ],
                          ),
                        ),
                        isThreeLine: true,
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton(onPressed: carregarCobrancas, tooltip: 'Atualizar', child: const Icon(Icons.refresh)),
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
      final res = await supabase.from('cobrancas').select().eq('status', 'Pago');
      final dtHoje = DateTime.now();
      final dtInicioSemana = dtHoje.subtract(Duration(days: dtHoje.weekday - 1));
      final dtFimSemana = dtInicioSemana.add(const Duration(days: 6));

      double tHoje = 0.0, tSem = 0.0, tMes = 0.0, tAno = 0.0;

      for (var r in res) {
        String? venc = r['vencimento'];
        double val = double.tryParse(r['valor'].toString()) ?? 0.0;
        if (venc == null || venc.length < 10) continue;

        try {
          DateTime dtObj = DateTime.parse(venc.split('/').reversed.join('-'));
          if (dtObj.year == dtHoje.year && dtObj.month == dtHoje.month && dtObj.day == dtHoje.day) {
            tHoje += val;
          }
          if (dtObj.isAfter(dtInicioSemana.subtract(const Duration(days: 1))) && dtObj.isBefore(dtFimSemana.add(const Duration(days: 1)))) {
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
            Text(titulo, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.grey)),
            Text('R\$ ${valor.toStringAsFixed(2)}', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: cor)),
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
      floatingActionButton: FloatingActionButton(onPressed: calcularResumo, tooltip: 'Atualizar', child: const Icon(Icons.refresh)),
    );
  }
}

class AbaEvolucaoGanhosMobile extends StatefulWidget {
  const AbaEvolucaoGanhosMobile({super.key});

  @override
  State<AbaEvolucaoGanhosMobile> createState() => _AbaEvolucaoGanhosMobileState();
}

class _AbaEvolucaoGanhosMobileState extends State<AbaEvolucaoGanhosMobile> {
  final supabase = Supabase.instance.client;
  List<Map<String, dynamic>> evolucao = [];
  bool carregando = true;
  String escalaSel = "Mensal";

  final List<String> mesesNomes = ['', 'Jan', 'Fev', 'Mar', 'Abr', 'Mai', 'Jun', 'Jul', 'Ago', 'Set', 'Out', 'Nov', 'Dez'];

  @override
  void initState() {
    super.initState();
    calcularEvolucao();
  }

  Future<void> calcularEvolucao() async {
    try {
      final res = await supabase.from('cobrancas').select().eq('status', 'Pago');
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
            chaveSort = "${dtObj.year}${dtObj.month.toString().padLeft(2, '0')}${dtObj.day.toString().padLeft(2, '0')}";
            label = "${dtObj.day.toString().padLeft(2, '0')}/${dtObj.month.toString().padLeft(2, '0')}/${dtObj.year}";
          } else if (escalaSel == "Semanal") {
            int semanaNum = ((dtObj.day - 1) ~/ 7) + 1;
            chaveSort = "${dtObj.year}${dtObj.month.toString().padLeft(2, '0')}$semanaNum";
            label = "${semanaNum}ª S ${mesesNomes[dtObj.month]} ${dtObj.year}";
          } else if (escalaSel == "Mensal") {
            chaveSort = "${dtObj.year}${dtObj.month.toString().padLeft(2, '0')}";
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
            agrupado[chaveSort] = {'sort': chaveSort, 'periodo': label, 'total': 0.0};
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
              children: ["Diária", "Semanal", "Mensal", "Bimestral", "Trimestral", "Semestral", "Anual"].map((escala) {
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
                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      child: ListTile(
                        title: Text(item['periodo'], style: const TextStyle(fontWeight: FontWeight.bold)),
                        trailing: Text('R\$ ${item['total'].toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green, fontSize: 16)),
                      ),
                    );
                  },
                ),
    );
  }
}

const List<String> DISCIPLINAS = ["Matemática", "Química", "Física"];