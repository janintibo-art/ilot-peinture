import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'demo_store.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const IlotApp());

class Api {
  String url = '';
  String token = '';
  bool demo = false;
  final demoStore = DemoStore();
  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    url = p.getString('server') ?? '';
    token = p.getString('token') ?? '';
    demo = p.getBool('demo_mode') ?? false;
  }
  Future<void> save(String server, String key) async {
    url = server.trim().replaceAll(RegExp(r'/$'), '');
    token = key.trim();
    final p = await SharedPreferences.getInstance();
    await p.setString('server', url);
    await p.setString('token', token);
  }
  Future<dynamic> request(String method, String endpoint, [Map<String, dynamic>? data]) async {
    if (demo) return demoStore.request(method, endpoint, data);
    if (url.isEmpty || token.isEmpty) throw Exception('Configurez le serveur dans Réglages.');
    final uri = Uri.parse('$url$endpoint');
    final headers = {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'};
    late http.Response response;
    try {
      if (method == 'GET') {
        response = await http.get(uri, headers: headers).timeout(const Duration(seconds: 12));
      } else if (method == 'PUT') {
        response = await http.put(uri, headers: headers, body: jsonEncode(data)).timeout(const Duration(seconds: 12));
      } else {
        response = await http.post(uri, headers: headers, body: jsonEncode(data)).timeout(const Duration(seconds: 12));
      }
    } catch (_) { throw Exception('Serveur injoignable. Vérifiez le Wi-Fi et son adresse.'); }
    if (response.statusCode >= 400) {
      String reason = 'Erreur ${response.statusCode}';
      try { reason = jsonDecode(response.body)['detail'].toString(); } catch (_) {}
      throw Exception(reason);
    }
    return jsonDecode(utf8.decode(response.bodyBytes));
  }
}

class IlotApp extends StatelessWidget {
  const IlotApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Îlot Peinture', debugShowCheckedModeBanner: false,
    theme: ThemeData(useMaterial3: true, colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff007d87)),
      scaffoldBackgroundColor: const Color(0xffeaf1f4), cardTheme: CardThemeData(elevation:3,shadowColor:const Color(0x33093b4a),color:Colors.white,shape:RoundedRectangleBorder(side:const BorderSide(color:Color(0xffd7e7ea)),borderRadius:BorderRadius.circular(20))), inputDecorationTheme: InputDecorationTheme(filled:true,fillColor:Colors.white,border:OutlineInputBorder(borderRadius:BorderRadius.circular(14)))),
    home: const Home(),
  );
}

class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}
class _HomeState extends State<Home> {
  final api = Api();
  int page = 0;
  bool busy = false;
  String selectedZone = 'Toutes';
  String error = '';
  String employeeNumber = ''; // Identifiant d'affichage local, pas une authentification
  List<dynamic> products = [], files = [];
  final search = TextEditingController();
  Timer? _searchTimer;
  static const Map<String, List<String>> defaultZoneLocations = {
    'Réception': ['Réception / Zone A'],
    'Racks': ['Rack A / Niveau 1', 'Rack A / Niveau 2', 'Rack B / Niveau 1', 'Rack B / Niveau 2', 'Rack C / Niveau 3'],
    'Peinture': ['Zone peinture / Chariot 1', 'Zone peinture / Chariot 2'],
    'Contrôle': ['Zone contrôle'],
    'Expédition': ['Zone expédition'],
  };
  Map<String, List<String>> zoneLocations = defaultZoneLocations.map((key, value) => MapEntry(key, List<String>.from(value)));
  Iterable<String> get suggestedLocations => zoneLocations.values.expand((list) => list);
  List<String> get zones => ['Toutes', ...zoneLocations.keys, 'Autres'];
  Future<void> loadZoneLocations() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('workshop_locations_v11');
    if (saved == null) return;
    try {
      final map = jsonDecode(saved) as Map<String, dynamic>;
      final parsed = <String, List<String>>{};
      for (final entry in map.entries) {
        final name = entry.key.trim();
        if (name.isEmpty || name == 'Toutes' || name == 'Autres') continue;
        if (entry.value is! List) continue;
        parsed[name] = (entry.value as List).whereType<String>().map((e) => e.trim()).where((e) => e.isNotEmpty).toSet().toList();
      }
      if (parsed.isNotEmpty && mounted) setState(() => zoneLocations = parsed);
    } catch (_) { /* Configuration invalide : conserver les zones par défaut. */ }
  }
  Future<void> saveZoneLocations() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('workshop_locations_v11', jsonEncode(zoneLocations));
    if (mounted) setState(() { if (!zones.contains(selectedZone)) selectedZone = 'Toutes'; });
  }
  Future<void> editLocations() async {
    await showDialog<void>(context: context, builder: (dialog) => StatefulBuilder(builder: (context, update) => AlertDialog(
      title: const Text('Zones et emplacements'),
      content: SizedBox(width: 440, height: 410, child: Column(children: [
        const Text('Cette configuration reste sur ce téléphone. La synchronisation via NAS sera ajoutée ultérieurement.', style: TextStyle(fontSize: 12)),
        const SizedBox(height: 8),
        Expanded(child: ListView(children: zoneLocations.entries.map((entry) => ExpansionTile(
          title: Text(entry.key, style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text('${entry.value.length} emplacement(s)'),
          children: [
            for (final location in entry.value) ListTile(dense: true, title: Text(location), trailing: IconButton(
              tooltip: 'Supprimer cet emplacement', icon: const Icon(Icons.delete_outline), onPressed: () async {
                if (files.any((f) => (f['location'] ?? '').toString() == location)) { message('Emplacement utilisé par un dossier : déplacez-le avant de le supprimer.'); return; }
                update(() => zoneLocations[entry.key]!.remove(location)); await saveZoneLocations();
              })),
            TextButton.icon(icon: const Icon(Icons.add), label: const Text('Ajouter un emplacement'), onPressed: () async {
              final value = await askLocationText('Nouvel emplacement', 'Nom de l’emplacement');
              if (value == null || !mounted) return;
              if (suggestedLocations.any((x) => x.toLowerCase() == value.toLowerCase())) { message('Cet emplacement existe déjà.'); return; }
              update(() => zoneLocations[entry.key]!.add(value)); await saveZoneLocations();
            }),
            TextButton.icon(icon: const Icon(Icons.delete_outline), label: const Text('Supprimer la zone'), onPressed: () async {
              if (entry.value.isNotEmpty || files.any((f) => zoneOf(f['location']) == entry.key)) { message('Videz la zone et déplacez ses dossiers avant suppression.'); return; }
              if (zoneLocations.length <= 1) { message('Conservez au moins une zone.'); return; }
              update(() => zoneLocations.remove(entry.key)); await saveZoneLocations();
            }),
          ],
        )).toList())),
      ])),
      actions: [TextButton.icon(icon: const Icon(Icons.add), label: const Text('Nouvelle zone'), onPressed: () async {
        final value = await askLocationText('Nouvelle zone', 'Nom de la zone');
        if (value == null || !mounted) return;
        if (zones.any((x) => x.toLowerCase() == value.toLowerCase())) { message('Cette zone existe déjà.'); return; }
        update(() => zoneLocations[value] = []); await saveZoneLocations();
      }), FilledButton(onPressed: () => Navigator.pop(dialog), child: const Text('Terminer'))],
    )));
  }
  Future<String?> askLocationText(String title, String label) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(context: context, builder: (dialog) => AlertDialog(
      title: Text(title), content: TextField(controller: controller, autofocus: true, maxLength: 80, decoration: InputDecoration(labelText: label)),
      actions: [TextButton(onPressed: () => Navigator.pop(dialog), child: const Text('Annuler')),
        FilledButton(onPressed: () { final value = controller.text.trim(); if (value.isNotEmpty) Navigator.pop(dialog, value); }, child: const Text('Ajouter'))],
    ));
    controller.dispose();
    return result;
  }
  void onSearchChanged(String _) {
    _searchTimer?.cancel();
    _searchTimer = Timer(const Duration(milliseconds: 320), () { if (mounted && page == 2) refresh(); });
  }
  Widget locationPicker(TextEditingController controller) => Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
    field(controller,'Emplacement précis'),
    const Padding(padding:EdgeInsets.only(bottom:8),child:Text('Emplacements rapides',style:TextStyle(fontWeight:FontWeight.w600,fontSize:12))),
    Wrap(spacing:6,runSpacing:4,children:suggestedLocations.map((loc)=>ActionChip(label:Text(loc,style:const TextStyle(fontSize:11)),onPressed:(){ controller.text=loc; controller.selection=TextSelection.collapsed(offset:controller.text.length); })).toList()),
    const SizedBox(height:12),
  ]);
  String zoneOf(Object? raw) {
    final value = (raw ?? '').toString().trim();
    for (final entry in zoneLocations.entries) {
      if (entry.value.any((loc) => loc.toLowerCase() == value.toLowerCase())) return entry.key;
    }
    final lower = value.toLowerCase();
    // Compatibilité avec les dossiers existants et les libellés historiques.
    final aliases = <String, List<String>>{
      'Réception': ['réception', 'reception'], 'Racks': ['rack', 'étagère', 'etagere'],
      'Peinture': ['peinture', 'chariot'], 'Contrôle': ['contrôle', 'controle'],
      'Expédition': ['expédition', 'expedition'],
    };
    for (final entry in zoneLocations.keys) {
      if (lower.startsWith(entry.toLowerCase())) return entry;
      if ((aliases[entry] ?? []).any(lower.contains)) return entry;
    }
    return 'Autres';
  }
  IconData zoneIcon(String zone) => switch (zone) {
    'Réception' => Icons.move_to_inbox_outlined,
    'Racks' => Icons.shelves,
    'Peinture' => Icons.format_paint_outlined,
    'Contrôle' => Icons.fact_check_outlined,
    'Expédition' => Icons.local_shipping_outlined,
    _ => Icons.place_outlined,
  };
  Widget zoneBoard() {
    final all = files.cast<Map<String,dynamic>>();
    return Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Row(children:[const Expanded(child: Text('Plan des zones', style:TextStyle(fontSize:18,fontWeight:FontWeight.w800))),IconButton(tooltip:'Personnaliser les zones',onPressed:editLocations,icon:const Icon(Icons.tune))]),
      const SizedBox(height:5),
      const Text('Touchez une zone pour afficher ses dossiers.',style:TextStyle(fontSize:12)),
      const SizedBox(height:10),
      LayoutBuilder(builder:(context, constraints) {
        final width = (constraints.maxWidth - 10) / 2;
        return Wrap(spacing:10,runSpacing:10,children:zones.where((z)=>z!='Toutes').map((zone) {
          final count=all.where((file)=>zoneOf(file['location'])==zone).length;
          final active=selectedZone==zone;
          return SizedBox(width:width,child:Material(color:active?const Color(0xffd3efea):Colors.white,borderRadius:BorderRadius.circular(16),child:InkWell(borderRadius:BorderRadius.circular(16),onTap:()=>setState(()=>selectedZone=active?'Toutes':zone),child:Padding(padding:const EdgeInsets.all(12),child:Row(children:[Icon(zoneIcon(zone),color:const Color(0xff007d87)),const SizedBox(width:9),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(zone,style:const TextStyle(fontWeight:FontWeight.w700,fontSize:12),overflow:TextOverflow.ellipsis),Text('$count dossier(s)',style:const TextStyle(fontSize:11))]))])))));
        }).toList());
      }),
      if(selectedZone!='Toutes') Padding(padding:const EdgeInsets.only(top:8,bottom:5),child:ActionChip(avatar:const Icon(Icons.close,size:17),label:Text('Filtre : $selectedZone'),onPressed:()=>setState(()=>selectedZone='Toutes'))),
    ]);
  }
  Future<void> quickMove(Map<String,dynamic> item) async {
    final controller=TextEditingController(text:(item['location']??'').toString());
    await showDialog<void>(context:context,builder:(dialog)=>AlertDialog(
      title:Text('Déplacer ${item['reference']}'),
      content:SizedBox(width:440,child:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text('Emplacement actuel : ${item['location']}',style:const TextStyle(fontSize:12)),
        const SizedBox(height:12),locationPicker(controller),
      ]))),
      actions:[TextButton(onPressed:()=>Navigator.pop(dialog),child:const Text('Annuler')),
        FilledButton.icon(icon:const Icon(Icons.check),label:const Text('Déplacer'),onPressed:() async {
          final destination=controller.text.trim();
          if(destination.isEmpty) {message('Choisissez un emplacement.');return;}
          if(destination==(item['location']??'').toString()) {Navigator.pop(dialog);return;}
          await execute(() async {await api.request('PUT','/files/${item['id']}',{
            'reference':item['reference'],'client':item['client'],'location':destination,
            'status':item['status'],'notes':item['notes']??'',
          });});
        })]));
    controller.dispose();
  }
  final categories = ['Liquide','Poudre','Solvant','Autre'];
  final statuses = ['Reçu','En attente','En peinture','Terminé','Expédié'];
  @override
  void initState() { super.initState(); init(); }
  @override
  void dispose() { _searchTimer?.cancel(); search.dispose(); super.dispose(); }
  Future<void> init() async { await api.load(); await loadZoneLocations(); final prefs=await SharedPreferences.getInstance(); employeeNumber=prefs.getString('employee_number_v13')??''; await refresh(); }
  Future<void> refresh() async {
    if (!mounted) return;
    setState(() {busy=true; error='';});
    try {
      final p = await api.request('GET', '/products');
      final f = await api.request('GET','/files?q=${Uri.encodeQueryComponent(search.text)}');
      if (mounted) setState(() {products=p; files=f;});
    } catch(e) { if(mounted) setState(() => error=e.toString().replaceFirst('Exception: ','')); }
    if(mounted) setState(() => busy=false);
  }
  void message(Object e) { if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ','')))); }
  Future<void> execute(Future<void> Function() job) async {
    try { await job(); if(mounted) Navigator.of(context).pop(); await refresh(); } catch(e) {message(e);} }
  Widget field(TextEditingController c, String name, {TextInputType? keyboard, int lines=1}) => Padding(
    padding: const EdgeInsets.only(bottom:12), child: TextField(controller:c, keyboardType:keyboard, maxLines:lines, decoration:InputDecoration(labelText:name)));
  Future<void> changeDemo(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('demo_mode',enabled);
    api.demo=enabled;
    search.clear();
    setState(()=>selectedZone='Toutes');
    await refresh();
  }
  Future<void> resetDemo() async {
    if (!api.demo) return;
    final yes = await showDialog<bool>(context:context,builder:(dialog)=>AlertDialog(title:const Text('Réinitialiser la démonstration ?'),content:const Text('Les modifications des données fictives seront effacées. Aucune donnée du serveur ne sera touchée.'),actions:[TextButton(onPressed:()=>Navigator.pop(dialog,false),child:const Text('Annuler')),FilledButton(onPressed:()=>Navigator.pop(dialog,true),child:const Text('Réinitialiser'))]));
    if (yes == true) { await DemoStore.reset(); await refresh(); }
  }
  Future<void> settings() async {
    final server = TextEditingController(text: api.url), key = TextEditingController(text: api.token), employee = TextEditingController(text: employeeNumber);
    await showDialog<void>(context:context,builder:(dialog)=>AlertDialog(title:const Text('Connexion au serveur'),content:SizedBox(width:420,child:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
      field(employee,'Numéro professionnel (ex. 128)',keyboard:TextInputType.number),
      const Text('Numéro affiché sur cet appareil uniquement. Ce n’est pas encore un compte sécurisé ni une preuve d’identité.',style:TextStyle(fontSize:12)),
      const SizedBox(height:12),field(server,'Adresse (ex. http://192.168.1.10:8000)'),field(key,'Clé d’accès'),
      const Text('Exemple : http://192.168.1.10:8000 (réseau interne). Ne partagez jamais la clé sur GitHub.',style:TextStyle(fontSize:12)),
      const SizedBox(height:8),OutlinedButton.icon(onPressed:() async {
        final temp=Api()..url=server.text.trim().replaceAll(RegExp(r'/$'),'')..token=key.text.trim();
        try { await temp.request('GET','/health'); if(dialog.mounted) ScaffoldMessenger.of(dialog).showSnackBar(const SnackBar(content:Text('Connexion réussie au serveur'))); }
        catch(e) { if(dialog.mounted) ScaffoldMessenger.of(dialog).showSnackBar(SnackBar(content:Text('Échec : ${e.toString().replaceFirst('Exception: ','')}'))); }
      },icon:const Icon(Icons.wifi_tethering),label:const Text('Tester la connexion'))]))),actions:[
      TextButton(onPressed:()=>Navigator.pop(dialog),child:const Text('Annuler')),
      FilledButton(onPressed:() async {final number=employee.text.trim(); if(number.isNotEmpty && !RegExp(r'^\d{1,8}$').hasMatch(number)){message('Le numéro doit contenir 1 à 8 chiffres.');return;} final prefs=await SharedPreferences.getInstance(); await prefs.setString('employee_number_v13',number); employeeNumber=number; await api.save(server.text,key.text); if(dialog.mounted) Navigator.pop(dialog); await refresh();},child:const Text('Enregistrer'))]));
    server.dispose(); key.dispose(); employee.dispose();
  }
  Future<void> productEditor() async {
    final name=TextEditingController(), amount=TextEditingController(text:'0'), alert=TextEditingController(text:'0'), location=TextEditingController();
    String category='Liquide', unit='kg';
    await showDialog<void>(context:context,builder:(dialog)=>StatefulBuilder(builder:(context,update)=>AlertDialog(
      title:const Text('Nouveau produit'), content:SizedBox(width:440,child:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
        field(name,'Nom / référence'),DropdownButtonFormField<String>(initialValue:category,decoration:const InputDecoration(labelText:'Famille'),items:categories.map((x)=>DropdownMenuItem(value:x,child:Text(x))).toList(),onChanged:(v)=>update(()=>category=v!)),
        const SizedBox(height:12),DropdownButtonFormField<String>(initialValue:unit,decoration:const InputDecoration(labelText:'Unité'),items:['kg','L','unité'].map((x)=>DropdownMenuItem(value:x,child:Text(x))).toList(),onChanged:(v)=>update(()=>unit=v!)),
        const SizedBox(height:12),field(amount,'Stock initial',keyboard:TextInputType.number),field(alert,'Seuil d’alerte',keyboard:TextInputType.number),field(location,'Emplacement de stockage')]))),
      actions:[TextButton(onPressed:()=>Navigator.pop(dialog),child:const Text('Annuler')),FilledButton(onPressed:()=>execute(() async {
        await api.request('POST','/products',{'name':name.text.trim(),'category':category,'unit':unit,'quantity':double.parse(amount.text.replaceAll(',','.')),'alert_at':double.parse(alert.text.replaceAll(',','.')),'location':location.text.trim()});
      }),child:const Text('Créer'))])));
    name.dispose();amount.dispose();alert.dispose();location.dispose();
  }
  Future<void> movement(Map<String,dynamic> product) async {
    final amount=TextEditingController(),reason=TextEditingController(); bool entry=true;
    await showDialog<void>(context:context,builder:(dialog)=>StatefulBuilder(builder:(context,update)=>AlertDialog(title:Text(product['name'].toString()),content:SizedBox(width:420,child:Column(mainAxisSize:MainAxisSize.min,children:[
      SegmentedButton<bool>(segments:const [ButtonSegment(value:true,label:Text('Entrée')),ButtonSegment(value:false,label:Text('Sortie'))],selected:{entry},onSelectionChanged:(v)=>update(()=>entry=v.first)),
      const SizedBox(height:16),field(amount,'Quantité (${product['unit']})',keyboard:TextInputType.number),field(reason,'Motif / dossier')
    ])),actions:[TextButton(onPressed:()=>Navigator.pop(dialog),child:const Text('Annuler')),FilledButton(onPressed:()=>execute(() async {
      final delta=double.parse(amount.text.replaceAll(',','.')); if(delta<=0) throw Exception('Quantité supérieure à zéro requise');
      await api.request('POST','/products/${product['id']}/movement',{'delta':entry?delta:-delta,'reason':reason.text.trim()});
    }),child:const Text('Valider'))])));
    amount.dispose();reason.dispose();
  }
  Future<void> showHistory(String title, String path, bool isStock) async {
    try {
      final entries = (await api.request('GET', path) as List).cast<Map<String,dynamic>>();
      if (!mounted) return;
      await showDialog<void>(context:context,builder:(dialog)=>AlertDialog(
        title:Text('Historique • $title'),
        content:SizedBox(width:440,height:360,child:entries.isEmpty
          ? const Center(child:Text('Aucun mouvement enregistré.'))
          : ListView.builder(itemCount:entries.length,itemBuilder:(context,index){
              final e=entries[index];
              final date=(e[isStock?'created_at':'changed_at']??'').toString().replaceAll('T',' ');
              return ListTile(
                leading:Icon(isStock?Icons.swap_vert:Icons.history),
                title:Text(isStock?'${e['delta']} • ${e['reason']}':'${e['previous_location']} → ${e['new_location']}'),
                subtitle:Text(isStock?date:'${e['previous_status']} → ${e['new_status']}\n$date'));
            })),actions:[TextButton(onPressed:()=>Navigator.pop(dialog),child:const Text('Fermer'))]));
    } catch(e) { message(e); }
  }
  Future<void> fileEditor([Map<String,dynamic>? existing]) async {
    final ref=TextEditingController(text:existing?['reference']?.toString()??''),client=TextEditingController(text:existing?['client']?.toString()??''),location=TextEditingController(text:existing?['location']?.toString()??''),notes=TextEditingController(text:existing?['notes']?.toString()??'');
    String status=existing?['status']?.toString()??'Reçu';
    await showDialog<void>(context:context,builder:(dialog)=>StatefulBuilder(builder:(context,update)=>AlertDialog(title:Text(existing==null?'Nouveau dossier':'Modifier le dossier'),content:SizedBox(width:450,child:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
      field(ref,'Numéro de dossier'),field(client,'Nom du client'),locationPicker(location),
      DropdownButtonFormField<String>(initialValue:status,decoration:const InputDecoration(labelText:'Étape'),items:statuses.map((x)=>DropdownMenuItem(value:x,child:Text(x))).toList(),onChanged:(v)=>update(()=>status=v!)),
      const SizedBox(height:12),field(notes,'Observations',lines:3)
    ]))),actions:[TextButton(onPressed:()=>Navigator.pop(dialog),child:const Text('Annuler')),FilledButton(onPressed:()=>execute(() async {
      final body={'reference':ref.text.trim(),'client':client.text.trim(),'location':location.text.trim(),'status':status,'notes':notes.text.trim()};
      await api.request(existing==null?'POST':'PUT',existing==null?'/files':'/files/${existing['id']}',body);
    }),child:const Text('Enregistrer'))])));
    ref.dispose();client.dispose();location.dispose();notes.dispose();
  }
  @override
  Widget build(BuildContext context) {
    final alerts = products.where((p)=>(p['quantity'] as num).toDouble()<=(p['alert_at'] as num).toDouble()).length;
    return Scaffold(appBar:AppBar(title:Row(mainAxisSize:MainAxisSize.min,children:[Image.asset('assets/icon.png',width:36,height:36),const SizedBox(width:8),const Flexible(child:Text('Îlot Peinture',overflow:TextOverflow.ellipsis,style:TextStyle(fontWeight:FontWeight.w800,fontSize:20)))]),actions:[if(employeeNumber.isNotEmpty) Center(child:Padding(padding:const EdgeInsets.only(right:4),child:Text('N° $employeeNumber',style:const TextStyle(fontSize:12,fontWeight:FontWeight.w700)))),IconButton(tooltip:'Actualiser',onPressed:refresh,icon:const Icon(Icons.refresh)),IconButton(tooltip:'Serveur',onPressed:settings,icon:const Icon(Icons.settings_outlined))]),
      bottomNavigationBar:NavigationBar(height:72,indicatorColor:const Color(0xffc6eeea),backgroundColor:const Color(0xfff8fcfd),selectedIndex:page,onDestinationSelected:(v)=>setState(()=>page=v),destinations:const [NavigationDestination(icon:Icon(Icons.dashboard_outlined),label:'Accueil'),NavigationDestination(icon:Icon(Icons.inventory_2_outlined),label:'Stocks'),NavigationDestination(icon:Icon(Icons.folder_copy_outlined),label:'Dossiers')]),
      floatingActionButton:page==0?null:FloatingActionButton.extended(onPressed:page==1?productEditor:()=>fileEditor(),icon:const Icon(Icons.add),label:Text(page==1?'Produit':'Dossier')),
      body:RefreshIndicator(onRefresh:refresh,child:ListView(padding:const EdgeInsets.symmetric(horizontal:16,vertical:14),children:[
        Card(color:api.demo?const Color(0xffe3f7ed):const Color(0xffe9f2f5),child:Padding(padding:const EdgeInsets.symmetric(horizontal:14,vertical:8),child:Row(children:[Icon(api.demo?Icons.science_outlined:Icons.dns_outlined,color:const Color(0xff007d87)),const SizedBox(width:10),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[const Text('Mode démonstration',style:TextStyle(fontWeight:FontWeight.w700)),Text(api.demo?'ACTIF • Données fictives sur cet appareil':'Désactivé • Mode serveur Linux/NAS',style:const TextStyle(fontSize:11))])),Switch(value:api.demo,onChanged:(v)=>changeDemo(v))]))),
        if (api.demo) Padding(padding:const EdgeInsets.only(bottom:10),child:Row(children:[const Expanded(child:Text('EXEMPLES FICTIFS · Aucune donnée entreprise',style:TextStyle(fontSize:10,color:Color(0xff087d85),fontWeight:FontWeight.w700))),TextButton.icon(onPressed:resetDemo,icon:const Icon(Icons.restart_alt,size:17),label:const Text('Réinitialiser'))])),
        if (busy) const LinearProgressIndicator(),
        if (error.isNotEmpty) Card(color:const Color(0xffffe8e6),child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(error),const SizedBox(height:8),TextButton(onPressed:settings,child:const Text('Configurer la connexion'))]))),
        if(page==0) ...[
          Container(padding:const EdgeInsets.all(16),decoration:BoxDecoration(gradient:const LinearGradient(colors:[Color(0xff073d4b),Color(0xff087d85)]),borderRadius:BorderRadius.circular(24)),child:const Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text('TABLEAU DE BORD',style:TextStyle(color:Color(0xff9ce9e3),fontWeight:FontWeight.bold,letterSpacing:2,fontSize:11)),SizedBox(height:8),Text('Votre atelier, en un coup d’œil',style:TextStyle(fontSize:21,fontWeight:FontWeight.w800,color:Colors.white)),SizedBox(height:5),Text('Stocks, commandes et emplacements réunis au même endroit.',style:TextStyle(color:Color(0xffd6eeef)))])),const SizedBox(height:18),
          LayoutBuilder(builder:(context,constraints)=>Wrap(spacing:10,runSpacing:10,children:[metric('Produits','${products.length}',Icons.inventory_2,width:(constraints.maxWidth-10)/2),metric('Alertes stock','$alerts',Icons.warning_amber,width:(constraints.maxWidth-10)/2),metric('Dossiers','${files.length}',Icons.folder_open,width:(constraints.maxWidth-10)/2),metric('À traiter','${files.where((f)=>f['status']!='Terminé' && f['status']!='Expédié').length}',Icons.pending_actions,width:(constraints.maxWidth-10)/2)])),
          const SizedBox(height:18),const Text('Accès rapide',style:TextStyle(fontSize:20,fontWeight:FontWeight.w800,color:Color(0xff103d4b))),
          Card(child:ListTile(leading:const CircleAvatar(backgroundColor:Color(0xffdbf4f1),child:Icon(Icons.search,color:Color(0xff007d87))),title:const Text('Retrouver une commande'),subtitle:const Text('Par client, numéro ou emplacement'),trailing:const Icon(Icons.arrow_forward),onTap:()=>setState(()=>page=2))),
          Card(child:ListTile(leading:const CircleAvatar(backgroundColor:Color(0xffdbf4f1),child:Icon(Icons.add_box_outlined,color:Color(0xff007d87))),title:const Text('Enregistrer une livraison de peinture'),trailing:const Icon(Icons.arrow_forward),onTap:()=>setState(()=>page=1))),
          if(alerts>0) Card(child:ListTile(leading:const Icon(Icons.warning_amber,color:Colors.deepOrange),title:Text('$alerts produit(s) à surveiller'),onTap:()=>setState(()=>page=1)))
        ],
        if(page==1) ...[
          const Text('Stocks & consommables',style:TextStyle(fontSize:23,fontWeight:FontWeight.w800,color:Color(0xff103d4b))),const SizedBox(height:8),
          const Text('Peintures liquides, poudres, solvants et autres produits.'),const SizedBox(height:12),
          for(final item in products.cast<Map<String,dynamic>>()) Card(child:ListTile(
            leading:CircleAvatar(child:Icon(item['category']=='Poudre'?Icons.grain:item['category']=='Solvant'?Icons.science:Icons.opacity)),
            title:Text(item['name'].toString(),style:const TextStyle(fontWeight:FontWeight.w600)),
            subtitle:Text('${item['category']} • ${item['location']}\nAlerte à ${item['alert_at']} ${item['unit']}'),isThreeLine:true,
            trailing:Column(mainAxisAlignment:MainAxisAlignment.center,mainAxisSize:MainAxisSize.min,children:[Text('${item['quantity']} ${item['unit']}',style:TextStyle(fontWeight:FontWeight.bold,color:(item['quantity'] as num)<=(item['alert_at'] as num)?Colors.deepOrange:null)),IconButton(tooltip:'Historique',icon:const Icon(Icons.history,size:21),onPressed:()=>showHistory(item['name'].toString(),'/products/${item['id']}/history',true))]),onTap:()=>movement(item))),
          if(products.isEmpty && !busy) const Card(child:Padding(padding:EdgeInsets.all(24),child:Column(children:[Icon(Icons.inventory_2_outlined,size:44,color:Color(0xff007d87)),SizedBox(height:12),Text('Aucun produit enregistré'),Text('Ajoutez un produit ou activez la démonstration.',textAlign:TextAlign.center)])))
        ],
        if(page==2) ...[
          const Text('Suivi des dossiers',style:TextStyle(fontSize:23,fontWeight:FontWeight.w800,color:Color(0xff103d4b))),const SizedBox(height:8),
          TextField(controller:search,onChanged:onSearchChanged,decoration:InputDecoration(prefixIcon:const Icon(Icons.search),hintText:'Client, numéro de dossier, emplacement',suffixIcon:IconButton(onPressed:(){search.clear();refresh();},icon:const Icon(Icons.clear)))),const SizedBox(height:14),
          zoneBoard(),const SizedBox(height:16),
          Text(selectedZone=='Toutes'?'Tous les dossiers':'Dossiers : $selectedZone',style:const TextStyle(fontSize:17,fontWeight:FontWeight.w700)),const SizedBox(height:8),
          for(final item in files.cast<Map<String,dynamic>>().where((item)=>selectedZone=='Toutes'||zoneOf(item['location'])==selectedZone)) Card(child:Padding(padding:const EdgeInsets.symmetric(vertical:5),child:ListTile(leading:const CircleAvatar(backgroundColor:Color(0xffe3f1f2),child:Icon(Icons.folder_outlined,color:Color(0xff007d87))),title:Text('${item['reference']} • ${item['client']}',style:const TextStyle(fontWeight:FontWeight.w700)),subtitle:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[const SizedBox(height:7),Text('📍 ${item['location']}',style:const TextStyle(fontWeight:FontWeight.w700,color:Color(0xff007d87))),const SizedBox(height:3),Text('Statut : ${item['status']}'),if((item['notes']??'').toString().isNotEmpty) Text(item['notes'].toString(),maxLines:2,overflow:TextOverflow.ellipsis)]),trailing:PopupMenuButton<String>(tooltip:'Actions du dossier',onSelected:(action){if(action=='move'){quickMove(item);}else if(action=='history'){showHistory(item['reference'].toString(),'/files/${item['id']}/history',false);}else{fileEditor(item);}},itemBuilder:(context)=>const [PopupMenuItem(value:'move',child:Text('Déplacer')),PopupMenuItem(value:'history',child:Text('Historique')),PopupMenuItem(value:'edit',child:Text('Modifier'))]),onTap:()=>fileEditor(item)))),
          if(files.isEmpty && !busy) const Card(child:Padding(padding:EdgeInsets.all(24),child:Column(children:[Icon(Icons.folder_open_outlined,size:44,color:Color(0xff007d87)),SizedBox(height:12),Text('Aucun dossier trouvé'),Text('Essayez une autre recherche ou créez un dossier.',textAlign:TextAlign.center)])))
        ],
        const SizedBox(height:80)
      ])));
  }
  Widget metric(String label,String value,IconData icon,{double width=145})=>SizedBox(width:width,height:126,child:Card(child:Padding(padding:const EdgeInsets.all(13),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Container(padding:const EdgeInsets.all(7),decoration:BoxDecoration(color:const Color(0xffdbf4f1),borderRadius:BorderRadius.circular(11)),child:Icon(icon,color:const Color(0xff007d87),size:20)),const Spacer(),Text(value,style:const TextStyle(fontSize:28,fontWeight:FontWeight.w900,color:Color(0xff103d4b))),Text(label,style:const TextStyle(fontSize:12,fontWeight:FontWeight.w600))]))));
}
