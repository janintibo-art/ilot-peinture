import 'dart:convert';
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
      scaffoldBackgroundColor: const Color(0xfff2f6f7), cardTheme: CardThemeData(elevation:0, color:Colors.white,shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(18))), inputDecorationTheme: InputDecorationTheme(filled:true,fillColor:Colors.white,border:OutlineInputBorder(borderRadius:BorderRadius.circular(14)))),
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
  String error = '';
  List<dynamic> products = [], files = [];
  final search = TextEditingController();
  final categories = ['Liquide','Poudre','Solvant','Autre'];
  final statuses = ['Reçu','En attente','En peinture','Terminé','Expédié'];
  @override
  void initState() { super.initState(); init(); }
  @override
  void dispose() { search.dispose(); super.dispose(); }
  Future<void> init() async { await api.load(); await refresh(); }
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
    await refresh();
  }
  Future<void> settings() async {
    final server = TextEditingController(text: api.url), key = TextEditingController(text: api.token);
    await showDialog<void>(context:context,builder:(dialog)=>AlertDialog(title:const Text('Connexion au serveur'),content:SizedBox(width:420,child:Column(mainAxisSize:MainAxisSize.min,children:[
      field(server,'Adresse (ex. http://192.168.1.10:8000)'),field(key,'Clé d’accès'),
      const Text('Le mode démonstration ne touche jamais aux données du serveur.',style:TextStyle(fontSize:12))])),actions:[
      TextButton(onPressed:()=>Navigator.pop(dialog),child:const Text('Annuler')),
      FilledButton(onPressed:() async {await api.save(server.text,key.text); if(dialog.mounted) Navigator.pop(dialog); await refresh();},child:const Text('Enregistrer'))]));
    server.dispose(); key.dispose();
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
      field(ref,'Numéro de dossier'),field(client,'Nom du client'),field(location,'Emplacement précis (ex. Rack B / Niveau 2)'),
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
    return Scaffold(appBar:AppBar(title:const Row(mainAxisSize:MainAxisSize.min,children:[Icon(Icons.palette_outlined,color:Color(0xff007d87)),SizedBox(width:8),Flexible(child:Text('Îlot Peinture',overflow:TextOverflow.ellipsis,style:TextStyle(fontWeight:FontWeight.w800,fontSize:20)))]),actions:[IconButton(tooltip:'Actualiser',onPressed:refresh,icon:const Icon(Icons.refresh)),IconButton(tooltip:'Serveur',onPressed:settings,icon:const Icon(Icons.settings_outlined))]),
      bottomNavigationBar:NavigationBar(selectedIndex:page,onDestinationSelected:(v)=>setState(()=>page=v),destinations:const [NavigationDestination(icon:Icon(Icons.dashboard_outlined),label:'Accueil'),NavigationDestination(icon:Icon(Icons.inventory_2_outlined),label:'Stocks'),NavigationDestination(icon:Icon(Icons.folder_copy_outlined),label:'Dossiers')]),
      floatingActionButton:page==0?null:FloatingActionButton.extended(onPressed:page==1?productEditor:()=>fileEditor(),icon:const Icon(Icons.add),label:Text(page==1?'Produit':'Dossier')),
      body:RefreshIndicator(onRefresh:refresh,child:ListView(padding:const EdgeInsets.symmetric(horizontal:16,vertical:14),children:[
        Card(color:api.demo?const Color(0xffe3f7ed):const Color(0xffe9f2f5),child:Padding(padding:const EdgeInsets.symmetric(horizontal:14,vertical:8),child:Row(children:[Icon(api.demo?Icons.science_outlined:Icons.dns_outlined,color:const Color(0xff007d87)),const SizedBox(width:10),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(api.demo?'Démonstration active':'Mode serveur',style:const TextStyle(fontWeight:FontWeight.w700)),Text(api.demo?'Données fictives enregistrées sur ce téléphone':'Connexion au serveur Linux/NAS',style:const TextStyle(fontSize:11))])),Switch(value:api.demo,onChanged:(v)=>changeDemo(v))]))),
        if (busy) const LinearProgressIndicator(),
        if (error.isNotEmpty) Card(color:const Color(0xffffe8e6),child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(error),const SizedBox(height:8),TextButton(onPressed:settings,child:const Text('Configurer la connexion'))]))),
        if(page==0) ...[
          Container(padding:const EdgeInsets.all(22),decoration:BoxDecoration(gradient:const LinearGradient(colors:[Color(0xff073d4b),Color(0xff087d85)]),borderRadius:BorderRadius.circular(24)),child:const Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text('TABLEAU DE BORD',style:TextStyle(color:Color(0xff9ce9e3),fontWeight:FontWeight.bold,letterSpacing:2,fontSize:11)),SizedBox(height:8),Text('Votre atelier, en un coup d’œil',style:TextStyle(fontSize:25,fontWeight:FontWeight.w800,color:Colors.white)),SizedBox(height:8),Text('Stocks, commandes et emplacements réunis au même endroit.',style:TextStyle(color:Color(0xffd6eeef)))])),const SizedBox(height:18),
          Wrap(spacing:12,runSpacing:12,children:[metric('Produits', '${products.length}',Icons.inventory_2),metric('Alertes stock','$alerts',Icons.warning_amber),metric('Dossiers','${files.length}',Icons.folder_open)]),
          const SizedBox(height:28),const Text('Accès rapide',style:TextStyle(fontSize:20,fontWeight:FontWeight.bold)),
          Card(child:ListTile(leading:const Icon(Icons.search),title:const Text('Retrouver une commande'),subtitle:const Text('Par client, numéro ou emplacement'),trailing:const Icon(Icons.arrow_forward),onTap:()=>setState(()=>page=2))),
          Card(child:ListTile(leading:const Icon(Icons.add_box_outlined),title:const Text('Enregistrer une livraison de peinture'),trailing:const Icon(Icons.arrow_forward),onTap:()=>setState(()=>page=1))),
          if(alerts>0) Card(child:ListTile(leading:const Icon(Icons.warning_amber,color:Colors.deepOrange),title:Text('$alerts produit(s) à surveiller'),onTap:()=>setState(()=>page=1)))
        ],
        if(page==1) ...[
          const Text('Stocks & consommables',style:TextStyle(fontSize:23,fontWeight:FontWeight.bold)),const SizedBox(height:8),
          const Text('Peintures liquides, poudres, solvants et autres produits.'),const SizedBox(height:12),
          for(final item in products.cast<Map<String,dynamic>>()) Card(child:ListTile(
            leading:CircleAvatar(child:Icon(item['category']=='Poudre'?Icons.grain:item['category']=='Solvant'?Icons.science:Icons.opacity)),
            title:Text(item['name'].toString(),style:const TextStyle(fontWeight:FontWeight.w600)),
            subtitle:Text('${item['category']} • ${item['location']}\nAlerte à ${item['alert_at']} ${item['unit']}'),isThreeLine:true,
            trailing:Column(mainAxisAlignment:MainAxisAlignment.center,mainAxisSize:MainAxisSize.min,children:[Text('${item['quantity']} ${item['unit']}',style:TextStyle(fontWeight:FontWeight.bold,color:(item['quantity'] as num)<=(item['alert_at'] as num)?Colors.deepOrange:null)),IconButton(tooltip:'Historique',icon:const Icon(Icons.history,size:21),onPressed:()=>showHistory(item['name'].toString(),'/products/${item['id']}/history',true))]),onTap:()=>movement(item))),
          if(products.isEmpty) const Card(child:Padding(padding:EdgeInsets.all(24),child:Column(children:[Icon(Icons.inventory_2_outlined,size:44,color:Color(0xff007d87)),SizedBox(height:12),Text('Aucun produit enregistré'),Text('Ajoutez un produit ou activez la démonstration.',textAlign:TextAlign.center)])))
        ],
        if(page==2) ...[
          const Text('Suivi des dossiers',style:TextStyle(fontSize:23,fontWeight:FontWeight.bold)),const SizedBox(height:8),
          TextField(controller:search,onChanged:(_)=>refresh(),decoration:InputDecoration(prefixIcon:const Icon(Icons.search),hintText:'Client, numéro de dossier, emplacement',suffixIcon:IconButton(onPressed:(){search.clear();refresh();},icon:const Icon(Icons.clear)))),const SizedBox(height:14),
          for(final item in files.cast<Map<String,dynamic>>()) Card(child:ListTile(leading:const Icon(Icons.folder_outlined),title:Text('${item['reference']} • ${item['client']}',style:const TextStyle(fontWeight:FontWeight.w600)),subtitle:Text('📍 ${item['location']}\n${item['status']}${(item['notes'] as String).isEmpty?'':' • ${item['notes']}'}'),isThreeLine:true,trailing:IconButton(tooltip:'Historique du dossier',icon:const Icon(Icons.history),onPressed:()=>showHistory(item['reference'].toString(),'/files/${item['id']}/history',false)),onTap:()=>fileEditor(item))),
          if(files.isEmpty) const Card(child:Padding(padding:EdgeInsets.all(24),child:Column(children:[Icon(Icons.folder_open_outlined,size:44,color:Color(0xff007d87)),SizedBox(height:12),Text('Aucun dossier trouvé'),Text('Essayez une autre recherche ou créez un dossier.',textAlign:TextAlign.center)])))
        ],
        const SizedBox(height:80)
      ])));
  }
  Widget metric(String label,String value,IconData icon)=>SizedBox(width:145,height:125,child:Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Icon(icon,color:const Color(0xff007d87)),const Spacer(),Text(value,style:const TextStyle(fontSize:27,fontWeight:FontWeight.w800)),Text(label,style:const TextStyle(fontSize:12))]))));
}
