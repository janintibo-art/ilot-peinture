import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// Compte personnel PILOTE : ne vaut pas validation qualité ou signature.
class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key, required this.server, required this.initialNumber,
    required this.currentToken, required this.onSession});
  final String server;
  final String initialNumber;
  final String currentToken;
  final void Function(String token, String number, String role) onSession;
  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  late final TextEditingController number = TextEditingController(text: widget.initialNumber);
  final TextEditingController password = TextEditingController();
  String token = '', role = '', error = '';
  bool busy = false;
  @override
  void initState() { super.initState(); token = widget.currentToken; if (token.isNotEmpty) verify(); }
  @override
  void dispose() { number.dispose(); password.dispose(); super.dispose(); }

  Future<void> verify() async {
    if (widget.server.isEmpty) return;
    setState(() => busy = true);
    try {
      final r = await http.get(Uri.parse('${widget.server}/auth/me'),
        headers: {'Authorization': 'Bearer $token'}).timeout(const Duration(seconds: 12));
      if (r.statusCode != 200) throw Exception('Session expirée : reconnectez-vous.');
      final data = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String,dynamic>;
      if (!mounted) return;
      setState(() { number.text = '${data['employee_number']}'; role = '${data['role']}'; error = ''; });
      widget.onSession(token, number.text, role);
    } catch (e) {
      if (mounted) { setState(() { token = ''; role = ''; error = '$e'; }); widget.onSession('', '', ''); }
    } finally { if (mounted) setState(() => busy = false); }
  }

  Future<void> login() async {
    if (widget.server.isEmpty) { setState(() => error = 'Configurez d’abord le serveur dans Réglages.'); return; }
    if (!RegExp(r'^\d{1,8}$').hasMatch(number.text.trim()) || password.text.length < 12) {
      setState(() => error = 'Numéro professionnel valide et mot de passe requis (12 caractères minimum).'); return;
    }
    setState(() { busy = true; error = ''; });
    try {
      final r = await http.post(Uri.parse('${widget.server}/auth/login'),
        headers: {'Content-Type':'application/json'},
        body: jsonEncode({'employee_number':number.text.trim(),'password':password.text}))
        .timeout(const Duration(seconds:12));
      if (r.statusCode != 200) throw Exception('Connexion refusée. Vérifiez votre compte et votre mot de passe.');
      final data = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String,dynamic>;
      if (!mounted) return;
      token = '${data['access_token']}'; role = '${data['role']}';
      widget.onSession(token, '${data['employee_number']}', role);
      password.clear();
      setState(() {});
    } catch (e) { if (mounted) setState(() => error = '$e'); }
    finally { if (mounted) setState(() => busy = false); }
  }

  Future<void> logout() async {
    setState(() => busy = true);
    try {
      if (token.isNotEmpty) await http.post(Uri.parse('${widget.server}/auth/logout'),
        headers: {'Authorization':'Bearer $token'}).timeout(const Duration(seconds:8));
    } catch (_) { /* Une session réseau inaccessible expirera côté serveur. */ }
    if (!mounted) return;
    token = ''; role = ''; password.clear(); widget.onSession('', '', '');
    setState(() { busy = false; error = ''; });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title:const Text('Compte professionnel')),
    body: SafeArea(child: ListView(padding:const EdgeInsets.all(20),children:[
      const Icon(Icons.verified_user_outlined,size:64,color:Color(0xff007d87)),
      const SizedBox(height:14),
      Text(token.isNotEmpty?'Session active · N° ${number.text}':'Connexion individuelle',
        style:const TextStyle(fontSize:23,fontWeight:FontWeight.w800),textAlign:TextAlign.center),
      const SizedBox(height:12),
      Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        if (token.isNotEmpty) ...[
          Text('Rôle : $role',style:const TextStyle(fontWeight:FontWeight.bold)),
          const SizedBox(height:12),
          FilledButton.icon(onPressed:busy?null:logout,icon:const Icon(Icons.logout),label:const Text('Se déconnecter')),
        ] else ...[
          TextField(controller:number,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'Numéro professionnel')),
          const SizedBox(height:12),
          TextField(controller:password,obscureText:true,enableSuggestions:false,autocorrect:false,
            decoration:const InputDecoration(labelText:'Mot de passe personnel')),
          const SizedBox(height:16),
          FilledButton.icon(onPressed:busy?null:login,icon:const Icon(Icons.login),label:const Text('Se connecter')),
        ],
      ]))),
      if (busy) const LinearProgressIndicator(),
      if (error.isNotEmpty) Padding(padding:const EdgeInsets.all(12),child:Text(error,style:const TextStyle(color:Colors.red))),
      const SizedBox(height:12),
      const Text('Version pilote : cette connexion ne constitue pas une signature qualité. Les opérations d’écriture exigent désormais une session personnelle. Le journal doit encore être rendu transactionnel et audité.',style:TextStyle(color:Color(0xff5b6e75))),
    ])));
}
