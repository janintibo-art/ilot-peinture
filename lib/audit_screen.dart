import 'package:flutter/material.dart';

typedef AuditRequest = Future<dynamic> Function(String method, String endpoint, [Map<String, dynamic>? data]);

class AuditScreen extends StatefulWidget {
  const AuditScreen({super.key, required this.request});
  final AuditRequest request;
  @override
  State<AuditScreen> createState() => _AuditScreenState();
}

class _AuditScreenState extends State<AuditScreen> {
  final operator = TextEditingController();
  final action = TextEditingController();
  final localSearch = TextEditingController();
  DateTime? from;
  DateTime? to;
  bool loading = false;
  String error = '';
  List<Map<String, dynamic>> entries = [];

  @override
  void initState() { super.initState(); load(); }
  @override
  void dispose() { operator.dispose(); action.dispose(); localSearch.dispose(); super.dispose(); }

  Future<void> load() async {
    setState(() { loading = true; error = ''; });
    try {
      final query = Uri(queryParameters: {
        'employee_number': operator.text.trim(),
        'action': action.text.trim(),
        'limit': '300',
      }).query;
      final response = await widget.request('GET', '/audit/events?$query') as List;
      if (mounted) setState(() => entries = response.map((row) => Map<String, dynamic>.from(row as Map)).toList());
    } catch (e) {
      if (mounted) setState(() => error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  bool matches(Map<String, dynamic> item) {
    final text = localSearch.text.trim().toLowerCase();
    if (text.isNotEmpty && !item.values.any((v) => v.toString().toLowerCase().contains(text))) return false;
    final timestamp = DateTime.tryParse((item['at'] ?? '').toString());
    if (from != null && (timestamp == null || timestamp.isBefore(from!))) return false;
    if (to != null && (timestamp == null || timestamp.isAfter(to!.add(const Duration(days: 1)).subtract(const Duration(microseconds: 1))))) return false;
    return true;
  }

  Future<void> pick(bool beginning) async {
    final chosen = await showDatePicker(context: context, initialDate: beginning ? (from ?? DateTime.now()) : (to ?? DateTime.now()), firstDate: DateTime(2020), lastDate: DateTime(2100));
    if (chosen != null && mounted) setState(() { if (beginning) { from = chosen; } else { to = chosen; } });
  }

  @override
  Widget build(BuildContext context) {
    final visible = entries.where(matches).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Journal qualité'), actions: [IconButton(onPressed: loading ? null : load, tooltip: 'Actualiser', icon: const Icon(Icons.refresh))]),
      body: SafeArea(child: ListView(padding: const EdgeInsets.all(16), children: [
        Container(padding: const EdgeInsets.all(17), decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xff093c4a), Color(0xff087e85)]), borderRadius: BorderRadius.circular(18)), child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('AUDIT QUALITÉ · PILOTE', style: TextStyle(color: Color(0xffa9ece6), letterSpacing: 1.2, fontWeight: FontWeight.bold)), SizedBox(height: 8), Text('Historique des actions serveur', style: TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w800)), SizedBox(height: 5), Text('Consultation réservée aux comptes qualité et administrateur.', style: TextStyle(color: Color(0xffe1f6f5)))])),
        const SizedBox(height: 14),
        TextField(controller: operator, decoration: const InputDecoration(labelText: 'Numéro opérateur (exact)', prefixIcon: Icon(Icons.badge_outlined)), keyboardType: TextInputType.number),
        const SizedBox(height: 10),
        TextField(controller: action, decoration: const InputDecoration(labelText: 'Action serveur (exacte)', prefixIcon: Icon(Icons.fact_check_outlined))),
        const SizedBox(height: 10),
        FilledButton.icon(onPressed: loading ? null : load, icon: const Icon(Icons.manage_search), label: const Text('Rechercher sur le serveur')),
        const SizedBox(height: 10),
        TextField(controller: localSearch, onChanged: (_) => setState(() {}), decoration: const InputDecoration(labelText: 'Rechercher dans les résultats chargés', prefixIcon: Icon(Icons.search))),
        const SizedBox(height: 8),
        Wrap(spacing: 8, children: [OutLinedDate(label: from == null ? 'Depuis' : '${from!.day}/${from!.month}/${from!.year}', onPressed: () => pick(true)), OutLinedDate(label: to == null ? 'Jusqu’au' : '${to!.day}/${to!.month}/${to!.year}', onPressed: () => pick(false)), if (from != null || to != null) TextButton(onPressed: () => setState(() { from = null; to = null; }), child: const Text('Effacer les dates'))]),
        const Text('Les dates et la recherche libre filtrent uniquement les 300 derniers événements retournés par le serveur. Aucun export ni signature qualité dans cette version.', style: TextStyle(fontSize: 12, color: Color(0xff607781))),
        if (loading) const Padding(padding: EdgeInsets.only(top: 10), child: LinearProgressIndicator()),
        if (error.isNotEmpty) Padding(padding: const EdgeInsets.all(12), child: Text(error, style: const TextStyle(color: Colors.red))),
        const SizedBox(height: 12),
        Text('${visible.length} événement(s) affiché(s)', style: const TextStyle(fontWeight: FontWeight.w700)),
        for (final event in visible) Card(child: Padding(padding: const EdgeInsets.all(13), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text((event['action'] ?? 'Action').toString(), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 5),
          Text('Opérateur : ${event['actor'] ?? 'Inconnu'} · Rôle : ${event['role'] ?? 'Non précisé'}'),
          Text('Élément : ${event['target'] ?? 'Non précisé'}'),
          Text('Date serveur : ${event['at'] ?? 'Non précisée'}'),
          if ((event['details'] ?? '').toString().isNotEmpty) Text('Détails : ${event['details']}', style: const TextStyle(fontSize: 12)),
        ]))),
        if (visible.isEmpty && !loading && error.isEmpty) const Padding(padding: EdgeInsets.all(22), child: Center(child: Text('Aucun événement à afficher.'))),
        const SizedBox(height: 32),
      ])),
    );
  }
}

class OutLinedDate extends StatelessWidget {
  const OutLinedDate({super.key, required this.label, required this.onPressed});
  final String label;
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) => OutlinedButton.icon(onPressed: onPressed, icon: const Icon(Icons.calendar_today_outlined, size: 16), label: Text(label));
}
