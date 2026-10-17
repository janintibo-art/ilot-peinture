import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Jeu de données fictives, propre à chaque appareil. Aucune requête réseau.
class DemoStore {
  static const _seedProducts = [
    {'id': 1, 'name': 'Peinture liquide RAL 7016', 'category': 'Liquide', 'unit': 'L', 'quantity': 18.5, 'alert_at': 5.0, 'location': 'Armoire A / Niveau 2'},
    {'id': 2, 'name': 'Poudre polyester RAL 9010', 'category': 'Poudre', 'unit': 'kg', 'quantity': 3.0, 'alert_at': 5.0, 'location': 'Rack poudres B3'},
    {'id': 3, 'name': 'Solvant de nettoyage (fictif)', 'category': 'Solvant', 'unit': 'L', 'quantity': 12.0, 'alert_at': 4.0, 'location': 'Armoire produits C'},
    {'id': 4, 'name': 'Peinture liquide RAL 9005', 'category': 'Liquide', 'unit': 'L', 'quantity': 7.5, 'alert_at': 8.0, 'location': 'Armoire A / Niveau 1'},
    {'id': 5, 'name': 'Poudre epoxy RAL 3000', 'category': 'Poudre', 'unit': 'kg', 'quantity': 22.0, 'alert_at': 5.0, 'location': 'Rack poudres B1'},
    {'id': 6, 'name': 'Diluant technique (fictif)', 'category': 'Solvant', 'unit': 'L', 'quantity': 2.0, 'alert_at': 3.0, 'location': 'Armoire produits C'},
    {'id': 7, 'name': 'Ruban de masquage', 'category': 'Autre', 'unit': 'unité', 'quantity': 24.0, 'alert_at': 10.0, 'location': 'Consommables A'},
  ];
  static const _seedFiles = [
    {'id': 1, 'reference': 'DEMO-2026-041', 'client': 'Ateliers Exemple', 'location': 'Rack A / Niveau 1', 'status': 'Reçu', 'notes': 'Pièces fictives à préparer'},
    {'id': 2, 'reference': 'DEMO-2026-042', 'client': 'Métal Démo', 'location': 'Zone peinture / Chariot 2', 'status': 'En peinture', 'notes': 'Teinte RAL 7016'},
    {'id': 3, 'reference': 'DEMO-2026-043', 'client': 'Industrie Test', 'location': 'Rack C / Niveau 3', 'status': 'En attente', 'notes': 'Lot de supports'},
    {'id': 4, 'reference': 'DEMO-2026-044', 'client': 'Ateliers Exemple', 'location': 'Zone contrôle', 'status': 'Terminé', 'notes': 'Contrôle visuel'},
    {'id': 5, 'reference': 'DEMO-2026-045', 'client': 'Aluminium Démo', 'location': 'Zone expédition', 'status': 'Expédié', 'notes': 'Commande fictive'},
  ];
  static Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('ilot_demo_v7');
  }

  Future<Map<String, dynamic>> _load(SharedPreferences prefs) async {
    final stored = prefs.getString('ilot_demo_v7');
    if (stored != null) return (jsonDecode(stored) as Map).cast<String, dynamic>();
    final initial = <String, dynamic>{'products': _seedProducts.map((p) => Map<String, dynamic>.from(p)).toList(), 'files': _seedFiles.map((f) => Map<String, dynamic>.from(f)).toList(), 'stockHistory': <dynamic>[], 'fileHistory': <dynamic>[]};
    await prefs.setString('ilot_demo_v7', jsonEncode(initial));
    return initial;
  }

  Future<dynamic> request(String method, String endpoint, Map<String, dynamic>? data) async {
    final prefs = await SharedPreferences.getInstance();
    final db = await _load(prefs);
    final uri = Uri.parse(endpoint);
    final path = uri.pathSegments;
    final products = (db['products'] as List).cast<dynamic>();
    final files = (db['files'] as List).cast<dynamic>();
    final stockHistory = (db['stockHistory'] as List).cast<dynamic>();
    final fileHistory = (db['fileHistory'] as List).cast<dynamic>();
    dynamic result;
    bool changed = false;
    if (path.length == 1 && path[0] == 'products') {
      if (method == 'GET') { result = products; }
      else if (method == 'POST' && data != null) {
        final item = {...data, 'id': _nextId(products)};
        if ((item['name'] as String).trim().isEmpty) throw Exception('Le nom est obligatoire.');
        products.add(item); result = item; changed = true;
      }
    } else if (path.length == 1 && path[0] == 'files') {
      if (method == 'GET') {
        final query = (uri.queryParameters['q'] ?? '').trim().toLowerCase();
        result = files.where((f) => query.isEmpty || [f['reference'], f['client'], f['location']].any((value) => value.toString().toLowerCase().contains(query))).toList();
      } else if (method == 'POST' && data != null) {
        if ((data['reference'] ?? '').toString().isEmpty || (data['client'] ?? '').toString().isEmpty) throw Exception('Numéro et client obligatoires.');
        if (files.any((f) => f['reference'] == data['reference'])) throw Exception('Numéro de dossier déjà utilisé.');
        final item = {...data, 'id': _nextId(files)};
        files.add(item); result = item; changed = true;
      }
    } else if (path.length == 3 && path[0] == 'products') {
      final id = int.tryParse(path[1]);
      final item = _byId(products, id);
      if (path[2] == 'history' && method == 'GET') {
        result = stockHistory.where((h) => h['product_id'] == id).toList().reversed.toList();
      } else if (path[2] == 'movement' && method == 'POST' && data != null) {
        final delta = (data['delta'] as num).toDouble();
        final next = (item['quantity'] as num).toDouble() + delta;
        if (delta == 0 || next < 0) throw Exception('Mouvement invalide ou stock insuffisant.');
        item['quantity'] = next;
        stockHistory.add({'product_id': id, 'delta': delta, 'reason': data['reason'] ?? '', 'created_at': DateTime.now().toIso8601String()});
        result = item; changed = true;
      }
    } else if (path.length >= 2 && path[0] == 'files') {
      final id = int.tryParse(path[1]);
      final item = _byId(files, id);
      if (path.length == 3 && path[2] == 'history' && method == 'GET') {
        result = fileHistory.where((h) => h['file_id'] == id).toList().reversed.toList();
      } else if (path.length == 2 && method == 'PUT' && data != null) {
        if ((data['reference'] ?? '').toString().isEmpty || (data['client'] ?? '').toString().isEmpty) throw Exception('Numéro et client obligatoires.');
        if (files.any((f) => f['id'] != id && f['reference'] == data['reference'])) throw Exception('Numéro de dossier déjà utilisé.');
        if (item['location'] != data['location'] || item['status'] != data['status']) {
          fileHistory.add({'file_id': id, 'previous_location': item['location'], 'new_location': data['location'], 'previous_status': item['status'], 'new_status': data['status'], 'changed_at': DateTime.now().toIso8601String()});
        }
        item.addAll(data); result = item; changed = true;
      }
    }
    if (result == null) throw Exception('Action indisponible en démonstration.');
    if (changed) await prefs.setString('ilot_demo_v7', jsonEncode(db));
    return jsonDecode(jsonEncode(result));
  }

  int _nextId(List<dynamic> items) => items.fold<int>(0, (max, item) => (item['id'] as int) > max ? item['id'] as int : max) + 1;
  Map<String, dynamic> _byId(List<dynamic> items, int? id) {
    for (final item in items) { if (item['id'] == id) return (item as Map).cast<String, dynamic>(); }
    throw Exception('Élément introuvable.');
  }
}
