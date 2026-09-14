import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:add_2_calendar/add_2_calendar.dart';

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
      formatted += '(' + text.substring(0, text.length >= 2 ? 2 : text.length);
    }
    if (text.length >= 3) {
      formatted += ') ' + text.substring(2, text.length >= 7 ? 7 : text.length);
    }
    if (text.length >= 8) {
      formatted += '-' + text.substring(7, text.length >= 11 ? 11 : text.length);
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
    const TelaPainelGanhosMobile(),
    const TelaConfiguracoesMobile(),
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
          BottomNavigationBarItem(icon: Icon(Icons.bar_chart), label: 'Ganhos'),
          BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Ajustes'),
        ],
      ),
    );
  }
}

// ================= TELA 1: AGENDA (Aulas Futuras, Calendário Nativo & Ações Rápidas) =================
class TelaAgendaMobile extends StatefulWidget {
  const TelaAgendaMobile({super.key});

  @override
  State<TelaAgendaMobile> createState() => _TelaAgendaMobileState();
}

class _TelaAgendaMobileState extends State<TelaAgendaMobile> {
  final supabase = Supabase.instance.client;
  List<Map<String, dynamic>> aulas = [];
  bool carregando = true;

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
          .eq('status_aula', 'Agendada')
          .order('data_aula', ascending: true);
      if (!mounted) return;
      setState(() {
        aulas = List<Map<String, dynamic>>.from(response);
        carregando = false;
      });
    } catch (_) {
      if (mounted) setState(() => carregando = false);
    }
  }

  Future<void> mudarStatusComRegra(int id, String statusBase) async {
    if (statusBase == 'Cancelada') {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Regra de Cancelamento'),
          content: const Text('Este cancelamento possui cobrança de taxa de 50% ou é isento?'),
          actions: [
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                await supabase.from('aulas').update({'status_aula': 'Cancelada (Sem Cobrança)'}).eq('id', id);
                carregarAulas();
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Aula cancelada sem cobrança.')));
              },
              child: const Text('Sem Cobrança'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(context);
                await supabase.from('aulas').update({'status_aula': 'Cancelada (Com Cobrança 50%)'}).eq('id', id);
                carregarAulas();
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cancelado com taxa de 50% registrada.')));
              },
              child: const Text('Com Cobrança (50%)'),
            ),
          ],
        ),
      );
    } else {
      await supabase.from('aulas').update({'status_aula': 'Realizada'}).eq('id', id);
      carregarAulas();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Aula marcada como Realizada e enviada ao histórico!')));
    }
  }

  Future<void> abrirWhatsApp(String nomeAluno) async {
    final res = await supabase.from('alunos').select('whatsapp_aluno, whatsapp_resp').eq('nome', nomeAluno).maybeSingle();
    if (res != null) {
      final wpp = res['whatsapp_resp'] ?? res['whatsapp_aluno'];
      if (wpp != null && wpp.toString().isNotEmpty) {
        final numLimpo = wpp.replaceAll(RegExp(r'\D'), '');
        final url = Uri.parse('https://wa.me/55$numLimpo?text=Olá!%20Passando%20para%20falarmos%20sobre%20a%20aula.');
        if (await canLaunchUrl(url)) {
          await launchUrl(url, mode: LaunchMode.externalApplication);
          return;
        }
      }
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('WhatsApp não cadastrado.')));
  }

  void abrirModalNovaAula() async {
    List<Map<String, dynamic>> listaAlunos = [];
    List<Map<String, dynamic>> listaPacotes = [];
    try {
      final resAlunos = await supabase.from('alunos').select('nome');
      final resPacotes = await supabase.from('pacotes_professor').select('nome_pacote').eq('ativo', true);
      listaAlunos = List<Map<String, dynamic>>.from(resAlunos);
      listaPacotes = List<Map<String, dynamic>>.from(resPacotes);
    } catch (_) {}

    if (!mounted) return;

    String? alunoSelecionado = listaAlunos.isNotEmpty ? listaAlunos.first['nome']?.toString() : null;
    String? pacoteSelecionado = listaPacotes.isNotEmpty ? listaPacotes.first['nome_pacote']?.toString() : null;
    String disciplina = 'Química';
    DateTime dataSel = DateTime.now();
    TimeOfDay horaSel = const TimeOfDay(hour: 14, minute: 0);
    final assuntoCtrl = TextEditingController(text: 'Acompanhamento');

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
                    ? const Text('Cadastre alunos na aba Alunos primeiro.', style: TextStyle(color: Colors.red))
                    : DropdownButtonFormField<String>(
                        value: alunoSelecionado,
                        decoration: const InputDecoration(labelText: 'Aluno'),
                        items: listaAlunos.map((a) => DropdownMenuItem(value: a['nome'].toString(), child: Text(a['nome'].toString()))).toList(),
                        onChanged: (v) => setStateModal(() => alunoSelecionado = v),
                      ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: pacoteSelecionado,
                  decoration: const InputDecoration(labelText: 'Pacote / Contrato (Opcional)'),
                  items: listaPacotes.map((p) => DropdownMenuItem(value: p['nome_pacote'].toString(), child: Text(p['nome_pacote'].toString()))).toList(),
                  onChanged: (v) => setStateModal(() => pacoteSelecionado = v),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: disciplina,
                  decoration: const InputDecoration(labelText: 'Disciplina'),
                  items: ['Química', 'Física', 'Matemática', 'Biologia', 'Redação', 'Português']
                      .map((d) => DropdownMenuItem(value: d, child: Text(d)))
                      .toList(),
                  onChanged: (v) => setStateModal(() => disciplina = v!),
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
                const SizedBox(height: 10),
                TextField(controller: assuntoCtrl, decoration: const InputDecoration(labelText: 'Tópico / Assunto')),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
            ElevatedButton(
              onPressed: listaAlunos.isEmpty || alunoSelecionado == null
                  ? null
                  : () async {
                      String dataStr = dataSel.toString().substring(0, 10);
                      String horaStr = "${horaSel.hour.toString().padLeft(2, '0')}:${horaSel.minute.toString().padLeft(2, '0')}";

                      // 1. Salva na Nuvem (Supabase)
                      await supabase.from('aulas').insert({
                        'aluno': alunoSelecionado,
                        'pacote': pacoteSelecionado ?? 'Avulsa',
                        'disciplina': disciplina,
                        'data_aula': dataStr,
                        'horario': horaStr,
                        'assunto': assuntoCtrl.text.trim(),
                        'status_aula': 'Agendada',
                      });

                      // 2. Sincroniza com o Calendário Nativo do Celular
                      try {
                        final DateTime horaInicio = DateTime(
                          dataSel.year,
                          dataSel.month,
                          dataSel.day,
                          horaSel.hour,
                          horaSel.minute,
                        );
                        final DateTime horaFim = horaInicio.add(const Duration(hours: 1));

                        final eventoCalendario = Event(
                          title: 'Aula de $disciplina - $alunoSelecionado',
                          description: 'Assunto: ${assuntoCtrl.text.trim()} | Tipo: ${pacoteSelecionado ?? 'Avulsa'}',
                          location: 'Presencial / Online',
                          startDate: horaInicio,
                          endDate: horaFim,
                          allDay: false,
                        );

                        Add2Calendar.addEvent2Cal(eventoCalendario);
                      } catch (e) {
                        debugPrint("Erro ao abrir calendário nativo: $e");
                      }

                      if (!mounted) return;
                      Navigator.pop(context);
                      carregarAulas();
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Aula agendada e enviada ao calendário!')));
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
      appBar: AppBar(title: const Text('Agenda (Aulas Futuras)')),
      body: carregando
          ? const Center(child: CircularProgressIndicator())
          : aulas.isEmpty
              ? const Center(child: Text('Nenhuma aula agendada para vir.'))
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
                            Text('Tipo: ${a['pacote']}'),
                            const Divider(height: 16),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                IconButton(icon: const Icon(Icons.chat, color: Colors.green), onPressed: () => abrirWhatsApp(a['aluno'])),
                                TextButton.icon(
                                  onPressed: () => mudarStatusComRegra(a['id'], 'Realizada'),
                                  icon: const Icon(Icons.check, color: Colors.indigo, size: 18),
                                  label: const Text('Realizada'),
                                ),
                                TextButton.icon(
                                  onPressed: () => mudarStatusComRegra(a['id'], 'Cancelada'),
                                  icon: const Icon(Icons.close, color: Colors.red, size: 18),
                                  label: const Text('Cancelar'),
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
class TelaPrecosMobile extends StatefulWidget {
  const TelaPrecosMobile({super.key});

  @override
  State<TelaPrecosMobile> createState() => _TelaPrecosMobileState();
}

class _TelaPrecosMobileState extends State<TelaPrecosMobile> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestão de Preços'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.list), text: 'Meus Preços'),
            Tab(icon: Icon(Icons.add_box), text: 'Novo Pacote'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [AbaListaPrecos(), AbaNovoPacote()],
      ),
    );
  }
}

class AbaListaPrecos extends StatefulWidget {
  const AbaListaPrecos({super.key});

  @override
  State<AbaListaPrecos> createState() => _AbaListaPrecosState();
}

class _AbaListaPrecosState extends State<AbaListaPrecos> {
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
      final response = await supabase.from('pacotes_professor').select().order('id', ascending: true);
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
                bool ativo = p['ativo'] ?? true;
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  child: ListTile(
                    title: Text(p['nome_pacote'], style: TextStyle(fontWeight: FontWeight.bold, color: ativo ? Colors.black : Colors.grey)),
                    subtitle: Text('Aulas: ${p['qtd_aulas']} | ${p['duracao_min'] ?? 60} min'),
                    trailing: Text("R\$ ${p['valor_total']}", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green, fontSize: 15)),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(onPressed: carregarPacotes, tooltip: 'Atualizar', child: const Icon(Icons.refresh)),
    );
  }
}

class AbaNovoPacote extends StatefulWidget {
  const AbaNovoPacote({super.key});

  @override
  State<AbaNovoPacote> createState() => _AbaNovoPacoteState();
}

class _AbaNovoPacoteState extends State<AbaNovoPacote> {
  final supabase = Supabase.instance.client;
  final _nomeController = TextEditingController();
  final _qtdController = TextEditingController(text: '4');
  final _valorController = TextEditingController();
  bool salvando = false;

  Future<void> salvarPacote() async {
    final nome = _nomeController.text.trim();
    final valorStr = _valorController.text.trim();
    if (nome.isEmpty || valorStr.isEmpty) return;

    setState(() => salvando = true);
    try {
      await supabase.from('pacotes_professor').insert({
        'nome_pacote': nome,
        'valor_total': double.parse(valorStr),
        'qtd_aulas': int.parse(_qtdController.text.trim()),
        'duracao_min': 60,
        'ativo': true,
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Pacote "$nome" criado com sucesso!')));
      _nomeController.clear();
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
          TextField(controller: _nomeController, decoration: const InputDecoration(labelText: 'Nome do Pacote / Aula', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          TextField(controller: _qtdController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Quantidade de Aulas', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          TextField(controller: _valorController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Valor Total (R\$)', border: OutlineInputBorder())),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: salvando ? null : salvarPacote,
            icon: const Icon(Icons.save),
            label: Text(salvando ? 'Salvando...' : 'Salvar Novo Preço / Pacote'),
          ),
        ],
      ),
    );
  }
}

// ================= TELA 3: ALUNOS =================
class TelaAlunosMobile extends StatefulWidget {
  const TelaAlunosMobile({super.key});

  @override
  State<TelaAlunosMobile> createState() => _TelaAlunosMobileState();
}

class _TelaAlunosMobileState extends State<TelaAlunosMobile> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestão de Alunos'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.group), text: 'Lista'),
            Tab(icon: Icon(Icons.person_add), text: 'Cadastrar'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [AbaListaAlunos(), AbaCadastrarAluno()],
      ),
    );
  }
}

class AbaCadastrarAluno extends StatefulWidget {
  const AbaCadastrarAluno({super.key});

  @override
  State<AbaCadastrarAluno> createState() => _AbaCadastrarAlunoState();
}

class _AbaCadastrarAlunoState extends State<AbaCadastrarAluno> {
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
        'status_pagamento': 'Não pago',
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

class AbaListaAlunos extends StatefulWidget {
  const AbaListaAlunos({super.key});

  @override
  State<AbaListaAlunos> createState() => _AbaListaAlunosState();
}

class _AbaListaAlunosState extends State<AbaListaAlunos> {
  final supabase = Supabase.instance.client;
  List<Map<String, dynamic>> alunos = [];
  List<Map<String, dynamic>> pacotes = [];
  List<Map<String, dynamic>> todasAulas = [];
  bool carregando = true;

  @override
  void initState() {
    super.initState();
    carregarDados();
  }

  Future<void> carregarDados() async {
    try {
      final resAlunos = await supabase.from('alunos').select().order('nome', ascending: true);
      final resPacotes = await supabase.from('pacotes_professor').select();
      final resAulas = await supabase.from('aulas').select();

      if (!mounted) return;
      setState(() {
        alunos = List<Map<String, dynamic>>.from(resAlunos);
        pacotes = List<Map<String, dynamic>>.from(resPacotes);
        todasAulas = List<Map<String, dynamic>>.from(resAulas);
        carregando = false;
      });
    } catch (_) {
      if (mounted) setState(() => carregando = false);
    }
  }

  void abrirPerfilAluno(Map<String, dynamic> aluno) {
    String nomeAluno = aluno['nome'];
    String statusPagamento = aluno['status_pagamento'] ?? 'Não pago';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateModal) {
          List<Map<String, dynamic>> aulasAluno = todasAulas.where((a) => a['aluno'] == nomeAluno).toList();
          List<Map<String, dynamic>> aulasRealizadas = aulasAluno.where((a) => a['status_aula'] == 'Realizada').toList();
          List<Map<String, dynamic>> aulasAtivas = aulasAluno.where((a) => a['status_aula'] == 'Agendada').toList();

          int totalDadas = aulasRealizadas.length;

          String? pacoteAtivo;
          for (var a in aulasAtivas) {
            if (a['pacote'] != null && a['pacote'] != 'Avulsa') {
              pacoteAtivo = a['pacote'];
              break;
            }
          }

          int qtdTotalPacote = 4;
          double valorTotalPacote = 0.0;
          if (pacoteAtivo != null) {
            for (var p in pacotes) {
              if (p['nome_pacote'] == pacoteAtivo) {
                qtdTotalPacote = p['qtd_aulas'] ?? 4;
                valorTotalPacote = double.tryParse(p['valor_total'].toString()) ?? 0.0;
              }
            }
          }

          int aulasRestantesPacote = qtdTotalPacote - totalDadas;
          if (aulasRestantesPacote < 0) aulasRestantesPacote = 0;

          double precoPorAula = qtdTotalPacote > 0 ? (valorTotalPacote / qtdTotalPacote) : 110.0;
          double faturamentoAluno = totalDadas * precoPorAula;

          return AlertDialog(
            title: Text('Perfil: $nomeAluno'),
            content: SizedBox(
              width: double.maxFinite,
              height: 450,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Série: ${aluno['ano_escolar'] ?? '-'}'),
                    Text('Responsável: ${aluno['responsavel'] ?? '-'}'),
                    const Divider(),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Status Pagamento:', style: TextStyle(fontWeight: FontWeight.bold)),
                        DropdownButton<String>(
                          value: ['Não pago', 'Pago 50%', 'Pago 100%'].contains(statusPagamento) ? statusPagamento : 'Não pago',
                          items: const [
                            DropdownMenuItem(value: 'Não pago', child: Text('Não pago')),
                            DropdownMenuItem(value: 'Pago 50%', child: Text('Pago 50%')),
                            DropdownMenuItem(value: 'Pago 100%', child: Text('Pago 100%')),
                          ],
                          onChanged: (novoStatus) async {
                            if (novoStatus != null) {
                              await supabase.from('alunos').update({'status_pagamento': novoStatus}).eq('id', aluno['id']);
                              setStateModal(() => statusPagamento = novoStatus);
                              carregarDados();
                            }
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Card(
                      color: Colors.indigo.shade50,
                      child: Padding(
                        padding: const EdgeInsets.all(10.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            Column(children: [Text('$totalDadas', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.indigo)), const Text('Dadas')]),
                            Column(children: [Text(pacoteAtivo != null ? '$aulasRestantesPacote/$qtdTotalPacote' : 'Avulsa', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.blueGrey)), Text(pacoteAtivo != null ? 'Restantes' : 'Tipo')]),
                            Column(children: [Text('R\$ ${faturamentoAluno.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.green)), const Text('Faturamento')]),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text('Aulas Ativas (Agendadas para vir):', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo)),
                    const SizedBox(height: 4),
                    aulasAtivas.isEmpty
                        ? const Text('Nenhuma aula ativa no momento.', style: TextStyle(fontSize: 12, color: Colors.grey))
                        : Column(
                            children: aulasAtivas.map((au) {
                              return Card(
                                child: ListTile(
                                  dense: true,
                                  title: Text('${au['data_aula']} (${au['horario']}) - ${au['disciplina']}'),
                                  subtitle: Text('Tipo: ${au['pacote']}'),
                                  trailing: IconButton(
                                    icon: const Icon(Icons.check_circle, color: Colors.green, size: 20),
                                    tooltip: 'Marcar Realizada',
                                    onPressed: () async {
                                      await supabase.from('aulas').update({'status_aula': 'Realizada'}).eq('id', au['id']);
                                      await carregarDados();
                                      if (!context.mounted) return;
                                      Navigator.pop(context);
                                    },
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                    const SizedBox(height: 12),
                    const Text('Histórico de Aulas Realizadas:', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    aulasRealizadas.isEmpty
                        ? const Text('Nenhuma aula realizada ainda.', style: TextStyle(fontSize: 12, color: Colors.grey))
                        : Column(
                            children: aulasRealizadas.map((au) {
                              return Card(
                                child: ListTile(
                                  dense: true,
                                  title: Text('${au['data_aula']} - ${au['disciplina']}'),
                                  subtitle: Text('Assunto: ${au['assunto'] ?? ''}'),
                                  trailing: const Icon(Icons.check, color: Colors.indigo, size: 18),
                                ),
                              );
                            }).toList(),
                          ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Fechar')),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: carregando
          ? const Center(child: CircularProgressIndicator())
          : alunos.isEmpty
              ? const Center(child: Text('Nenhum aluno cadastrado.'))
              : ListView.builder(
                  itemCount: alunos.length,
                  itemBuilder: (context, index) {
                    final al = alunos[index];
                    String nome = al['nome'] ?? '';
                    String pagamento = al['status_pagamento'] ?? 'Não pago';
                    int concluidas = todasAulas.where((a) => a['aluno'] == nome && a['status_aula'] == 'Realizada').length;

                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      child: ListTile(
                        title: Row(
                          children: [
                            Text(nome, style: const TextStyle(fontWeight: FontWeight.bold)),
                            const SizedBox(width: 8),
                            Text('($pagamento)', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                          ],
                        ),
                        subtitle: Text('Série: ${al['ano_escolar'] ?? '-'}\nWhatsApp: ${al['whatsapp_aluno'] ?? al['whatsapp_resp'] ?? '-'}'),
                        isThreeLine: true,
                        trailing: Chip(
                          backgroundColor: Colors.indigo.shade50,
                          label: Text('$concluidas dadas', style: const TextStyle(color: Colors.indigo, fontWeight: FontWeight.bold)),
                        ),
                        onTap: () => abrirPerfilAluno(al),
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton(onPressed: carregarDados, tooltip: 'Atualizar', child: const Icon(Icons.refresh)),
    );
  }
}

// ================= TELA 4: PAINEL DE GANHOS =================
class TelaPainelGanhosMobile extends StatefulWidget {
  const TelaPainelGanhosMobile({super.key});

  @override
  State<TelaPainelGanhosMobile> createState() => _TelaPainelGanhosMobileState();
}

class _TelaPainelGanhosMobileState extends State<TelaPainelGanhosMobile> {
  final supabase = Supabase.instance.client;
  bool carregando = true;
  double ganhoDiario = 0;
  double ganhoMensal = 0;
  double ganhoSemestral = 0;
  double ganhoAnual = 0;
  double ganhoTotal = 0;

  List<Map<String, dynamic>> historicoDiario = [];
  List<Map<String, dynamic>> historicoMensal = [];
  List<Map<String, dynamic>> historicoAnual = [];

  @override
  void initState() {
    super.initState();
    calcularGanhos();
  }

  Future<void> calcularGanhos() async {
    try {
      final resAulas = await supabase.from('aulas').select().eq('status_aula', 'Realizada');
      double valorAulaPadrao = 110.0;

      DateTime hoje = DateTime.now();
      String hojeStr = hoje.toString().substring(0, 10);
      String mesAtualStr = hoje.toString().substring(0, 7);
      String anoAtualStr = hoje.toString().substring(0, 4);

      double d = 0, m = 0, sem = 0, ano = 0, tot = 0;
      Map<String, double> mapDias = {};
      Map<String, double> mapMeses = {};
      Map<String, double> mapAnos = {};

      for (var aula in resAulas) {
        String data = aula['data_aula']?.toString() ?? '';
        if (data.length < 10) continue;
        double valor = valorAulaPadrao;

        tot += valor;

        if (data == hojeStr) d += valor;
        if (DateTime.parse(data).isAfter(hoje.subtract(const Duration(days: 30)))) {
          mapDias[data] = (mapDias[data] ?? 0) + valor;
        }

        if (data.startsWith(mesAtualStr)) m += valor;
        String mesKey = data.substring(0, 7);
        mapMeses[mesKey] = (mapMeses[mesKey] ?? 0) + valor;

        if (data.startsWith(anoAtualStr)) ano += valor;
        String anoKey = data.substring(0, 4);
        mapAnos[anoKey] = (mapAnos[anoKey] ?? 0) + valor;

        if (DateTime.parse(data).isAfter(hoje.subtract(const Duration(days: 180)))) {
          sem += valor;
        }
      }

      historicoDiario = mapDias.entries.map((e) => {'periodo': e.key, 'valor': e.value}).toList();
      historicoDiario.sort((a, b) => b['periodo'].compareTo(a['periodo']));

      historicoMensal = mapMeses.entries.map((e) => {'periodo': e.key, 'valor': e.value}).toList();
      historicoMensal.sort((a, b) => b['periodo'].compareTo(a['periodo']));

      historicoAnual = mapAnos.entries.map((e) => {'periodo': e.key, 'valor': e.value}).toList();
      historicoAnual.sort((a, b) => b['periodo'].compareTo(a['periodo']));

      if (!mounted) return;
      setState(() {
        ganhoDiario = d;
        ganhoMensal = m;
        ganhoSemestral = sem;
        ganhoAnual = ano;
        ganhoTotal = tot;
        carregando = false;
      });
    } catch (_) {
      if (mounted) setState(() => carregando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Painel de Ganhos'),
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'Resumo'),
              Tab(text: 'Hist. Diário'),
              Tab(text: 'Hist. Mensal'),
              Tab(text: 'Hist. Anual'),
            ],
          ),
        ),
        body: carregando
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                children: [
                  SingleChildScrollView(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _cardGanho('Ganho Hoje (Diário)', ganhoDiario, Colors.blue),
                        _cardGanho('Ganho Este Mês', ganhoMensal, Colors.green),
                        _cardGanho('Ganho Último Semestre', ganhoSemestral, Colors.orange),
                        _cardGanho('Ganho Este Ano', ganhoAnual, Colors.purple),
                        _cardGanho('Ganho Desde o Início', ganhoTotal, Colors.indigo),
                      ],
                    ),
                  ),
                  ListView.builder(
                    itemCount: historicoDiario.length,
                    itemBuilder: (context, i) {
                      final item = historicoDiario[i];
                      return ListTile(
                        title: Text('Dia: ${item['periodo']}'),
                        trailing: Text('R\$ ${item['valor'].toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                      );
                    },
                  ),
                  ListView.builder(
                    itemCount: historicoMensal.length,
                    itemBuilder: (context, i) {
                      final item = historicoMensal[i];
                      return ListTile(
                        title: Text('Mês: ${item['periodo']}'),
                        trailing: Text('R\$ ${item['valor'].toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                      );
                    },
                  ),
                  ListView.builder(
                    itemCount: historicoAnual.length,
                    itemBuilder: (context, i) {
                      final item = historicoAnual[i];
                      return ListTile(
                        title: Text('Ano: ${item['periodo']}'),
                        trailing: Text('R\$ ${item['valor'].toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                      );
                    },
                  ),
                ],
              ),
        floatingActionButton: FloatingActionButton(onPressed: calcularGanhos, tooltip: 'Atualizar Ganhos', child: const Icon(Icons.refresh)),
      ),
    );
  }

  Widget _cardGanho(String titulo, double valor, Color cor) {
    return Card(
      elevation: 3,
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Text(titulo, style: const TextStyle(fontSize: 14, color: Colors.grey, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('R\$ ${valor.toStringAsFixed(2)}', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: cor)),
          ],
        ),
      ),
    );
  }
}

// ================= TELA 5: AJUSTES & PERFIL =================
class TelaConfiguracoesMobile extends StatefulWidget {
  const TelaConfiguracoesMobile({super.key});

  @override
  State<TelaConfiguracoesMobile> createState() => _TelaConfiguracoesMobileState();
}

class _TelaConfiguracoesMobileState extends State<TelaConfiguracoesMobile> {
  final supabase = Supabase.instance.client;
  
  final _nomeController = TextEditingController(text: 'Alexander Garreta Gonçalves Costa Pinto');
  final _chavePixController = TextEditingController();
  final _preco1hController = TextEditingController(text: '110.00');
  final _preco1h30Controller = TextEditingController(text: '155.00');
  bool carregando = true;
  bool salvando = false;

  @override
  void initState() {
    super.initState();
    carregarConfig();
  }

  Future<void> carregarConfig() async {
    try {
      final res = await supabase.from('configuracoes_professor').select().limit(1).maybeSingle();
      if (res != null) {
        if (res['nome_professor'] != null) _nomeController.text = res['nome_professor'].toString();
        if (res['chave_pix'] != null) _chavePixController.text = res['chave_pix'].toString();
        if (res['preco_hora_avulsa'] != null) {
          _preco1hController.text = double.parse(res['preco_hora_avulsa'].toString()).toStringAsFixed(2);
        }
      }
      if (mounted) setState(() => carregando = false);
    } catch (_) {
      if (mounted) setState(() => carregando = false);
    }
  }

  Future<void> salvarConfiguracoes() async {
    setState(() => salvando = true);
    try {
      final resExistente = await supabase.from('configuracoes_professor').select('id').limit(1).maybeSingle();
      final dados = {
        'nome_professor': _nomeController.text.trim(),
        'chave_pix': _chavePixController.text.trim(),
        'preco_hora_avulsa': double.tryParse(_preco1hController.text.replaceAll(',', '.')) ?? 110.0,
      };

      if (resExistente != null) {
        await supabase.from('configuracoes_professor').update(dados).eq('id', resExistente['id']);
      } else {
        await supabase.from('configuracoes_professor').insert(dados);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ajustes salvos com sucesso!')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e')));
    } finally {
      if (mounted) setState(() => salvando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ajustes & Perfil')),
      body: carregando
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(controller: _nomeController, decoration: const InputDecoration(labelText: 'Nome do Professor', border: OutlineInputBorder())),
                  const SizedBox(height: 14),
                  TextField(controller: _chavePixController, decoration: const InputDecoration(labelText: 'Chave Pix Principal', border: OutlineInputBorder(), prefixIcon: Icon(Icons.pix))),
                  const SizedBox(height: 14),
                  const Text('Preços Base:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(child: TextField(controller: _preco1hController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Base 1h (R\$)', border: OutlineInputBorder()))),
                      const SizedBox(width: 8),
                      Expanded(child: TextField(controller: _preco1h30Controller, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Base 1h30 (R\$)', border: OutlineInputBorder()))),
                    ],
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: salvando ? null : salvarConfiguracoes,
                    icon: salvando ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.save),
                    label: Text(salvando ? 'Salvando...' : 'Salvar Ajustes'),
                    style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                  ),
                ],
              ),
            ),
    );
  }
}