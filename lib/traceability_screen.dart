import 'package:flutter/material.dart';

typedef TraceRequest = Future<dynamic> Function(String method, String endpoint, [Map<String, dynamic>? data]);

/// Registre pilote. Les identités opérateur ne sont pas authentifiées.
class TraceabilityScreen extends StatefulWidget {
  const TraceabilityScreen({super.key, required this.request, required this.demo,
    required this.products, required this.files, required this.employeeNumber});
  final TraceRequest request;
  final bool demo;
  final List<dynamic> products;
  final List<dynamic> files;
  final String employeeNumber;
  @override
  State<TraceabilityScreen> createState() => _TraceabilityScreenState();
}

class _TraceabilityScreenState extends State<TraceabilityScreen> {
  List<Map<String,dynamic>> lots = [];
  bool loading = false;
  String error = '';
  static const teal = Color(0xff007d87);
  @override
  void initState() { super.initState(); if (!widget.demo) load(); }
  Future<void> load() async {
    setState(() { loading = true; error = ''; });
    try {
      final rows = await widget.request('GET', '/material-lots') as List;
      if (mounted) setState(() => lots = rows.map((e) => Map<String,dynamic>.from(e as Map)).toList());
    } catch(e) { if (mounted) setState(() => error = e.toString().replaceFirst('Exception: ','')); }
    if (mounted) setState(() => loading = false);
  }
  void inform(Object text) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text.toString().replaceFirst('Exception: ','')))); }
  InputDecoration decoration(String label) => InputDecoration(labelText: label, border: const OutlineInputBorder(), isDense:true);
  Widget field(TextEditingController c, String label, {TextInputType? keyboard}) => Padding(
    padding: const EdgeInsets.only(bottom:12), child: TextField(controller:c,keyboardType:keyboard,decoration:decoration(label)));
  Map<String,dynamic>? selected(List<dynamic> rows, int? id) {
    for (final row in rows) { if (row['id'] == id) return Map<String,dynamic>.from(row); }
    return null;
  }
  Future<void> addLot() async {
    if (widget.products.isEmpty) { inform('Créez d’abord une fiche produit.'); return; }
    int? product = widget.products.first['id'] as int;
    final supplier=TextEditingController(), reference=TextEditingController(), number=TextEditingController();
    final received=TextEditingController(text:DateTime.now().toIso8601String().substring(0,10));
    final expiry=TextEditingController(), certificate=TextEditingController(), notes=TextEditingController();
    try {
      await showDialog<void>(context:context,builder:(dialog)=>StatefulBuilder(builder:(ctx,update)=>AlertDialog(
        title:const Text('Nouveau lot fournisseur'),
        content:SizedBox(width:480,child:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
          DropdownButtonFormField<int>(initialValue:product,isExpanded:true,decoration:decoration('Produit'),
            items:widget.products.map((p)=>DropdownMenuItem<int>(value:p['id'] as int,child:Text(p['name'].toString(),overflow:TextOverflow.ellipsis))).toList(),onChanged:(v)=>update(()=>product=v)),
          const SizedBox(height:12),field(supplier,'Fournisseur'),field(reference,'Référence fournisseur'),field(number,'Numéro de lot'),
          field(received,'Réception (AAAA-MM-JJ)'),field(expiry,'Péremption (facultative, AAAA-MM-JJ)'),field(certificate,'Référence certificat (facultative)'),field(notes,'Observations'),
          const Text('Les références de certificats ne remplacent pas le stockage sécurisé des documents.',style:TextStyle(fontSize:12)),
        ]))),
        actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Annuler')),
          FilledButton(onPressed:() async {
            if (product==null || supplier.text.trim().isEmpty || reference.text.trim().isEmpty || number.text.trim().isEmpty || DateTime.tryParse(received.text.trim())==null || (expiry.text.trim().isNotEmpty && DateTime.tryParse(expiry.text.trim())==null)) {inform('Vérifiez les champs obligatoires et les dates.'); return;}
            try {
              await widget.request('POST','/material-lots',{
                'product_id':product,'supplier':supplier.text.trim(),'supplier_reference':reference.text.trim(),
                'lot_number':number.text.trim(),'received_at':received.text.trim(),
                'expires_on':expiry.text.trim().isEmpty?null:expiry.text.trim(),'certificate_ref':certificate.text.trim(),'notes':notes.text.trim()});
              if (ctx.mounted) Navigator.pop(ctx);
              await load();
            } catch(e) { inform(e); }
          },child:const Text('Enregistrer'))]
      )));
    } finally { for (final c in [supplier,reference,number,received,expiry,certificate,notes]) {c.dispose();} }
  }
  Future<void> addOperation() async {
    final allowed = lots.where((l)=>l['category']=='Liquide'||l['category']=='Poudre').toList();
    if (allowed.isEmpty || widget.files.isEmpty) { inform('Créez d’abord un lot liquide/poudre et un dossier.'); return; }
    int? lotId=allowed.first['id'] as int, fileId=widget.files.first['id'] as int;
    final qty=TextEditingController(), hardener=TextEditingController(), ratio=TextEditingController();
    final pot=TextEditingController(), temp=TextEditingController(), duration=TextEditingController();
    final notes=TextEditingController(), operator=TextEditingController(text:widget.employeeNumber);
    final operationAt=TextEditingController(text:DateTime.now().toIso8601String());
    try {
      await showDialog<void>(context:context,builder:(dialog)=>StatefulBuilder(builder:(ctx,update){
        final lot=selected(allowed,lotId)!;
        final liquid=lot['category']=='Liquide';
        return AlertDialog(title:const Text('Enregistrer une opération'),content:SizedBox(width:480,child:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
          const Text('Registre pilote : numéro opérateur déclaratif, sans validation d’identité ni signature.',style:TextStyle(fontSize:12)),
          const SizedBox(height:12),
          DropdownButtonFormField<int>(initialValue:fileId,isExpanded:true,decoration:decoration('Dossier'),items:widget.files.map((f)=>DropdownMenuItem<int>(value:f['id'] as int,child:Text('${f['reference']} — ${f['client']}',overflow:TextOverflow.ellipsis))).toList(),onChanged:(v)=>update(()=>fileId=v)),
          const SizedBox(height:12),
          DropdownButtonFormField<int>(initialValue:lotId,isExpanded:true,decoration:decoration('Lot matière'),items:allowed.map((l)=>DropdownMenuItem<int>(value:l['id'] as int,child:Text('${l['lot_number']} • ${l['product_name']}',overflow:TextOverflow.ellipsis))).toList(),onChanged:(v)=>update(()=>lotId=v)),
          const SizedBox(height:12),field(qty,'Quantité utilisée (${lot['unit']})',keyboard:const TextInputType.numberWithOptions(decimal:true)),
          field(operator,'Numéro opérateur (déclaratif)',keyboard:TextInputType.number),field(operationAt,'Date et heure ISO (AAAA-MM-JJTHH:MM:SS)'),
          if(liquid) ...[field(hardener,'Lot durcisseur'),field(ratio,'Rapport de mélange'),field(pot,'Durée de vie mélange (minutes)',keyboard:TextInputType.number)]
          else ...[field(temp,'Température cuisson déclarée (°C)',keyboard:const TextInputType.numberWithOptions(decimal:true)),field(duration,'Durée cuisson (minutes)',keyboard:TextInputType.number)],
          field(notes,'Observations'),
        ]))),actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Annuler')),
          FilledButton(onPressed:() async {
            double? d(String x)=>double.tryParse(x.replaceAll(',','.').trim());
            final amount=d(qty.text), minutes=int.tryParse((liquid?pot:duration).text.trim());
            if(fileId==null||lotId==null||amount==null||amount<=0||minutes==null||minutes<=0||!RegExp(r'^\d+$').hasMatch(operator.text.trim())||DateTime.tryParse(operationAt.text.trim())==null|| (liquid&&(hardener.text.trim().isEmpty||ratio.text.trim().isEmpty))||(!liquid&&d(temp.text)==null)) {inform('Complétez les informations obligatoires.');return;}
            try {
              await widget.request('POST','/process-records',{
                'file_id':fileId,'material_lot_id':lotId,'process_type':lot['category'],
                'quantity':amount,'unit':lot['unit'],'operator_number':operator.text.trim(),'operation_at':operationAt.text.trim(),
                'hardener_lot':liquid?hardener.text.trim():'','mix_ratio':liquid?ratio.text.trim():'',
                'pot_life_minutes':liquid?minutes:null,'powder_temperature_c':liquid?null:d(temp.text),
                'powder_duration_minutes':liquid?null:minutes,'notes':notes.text.trim()});
              if(ctx.mounted) Navigator.pop(ctx);
              inform('Opération déclarée sur le serveur pilote.');
            } catch(e) {inform(e);}
          },child:const Text('Enregistrer'))]);
      }));
    } finally {for(final c in [qty,hardener,ratio,pot,temp,duration,notes,operator,operationAt]) {c.dispose();}}
  }
  Future<void> showTrace(String endpoint,String title) async {
    try {
      final raw=await widget.request('GET',endpoint) as Map;
      final records=(raw['operations'] as List).cast<dynamic>();
      if(!mounted)return;
      await showDialog<void>(context:context,builder:(ctx)=>AlertDialog(title:Text(title),content:SizedBox(width:480,height:370,child:records.isEmpty
        ?const Center(child:Text('Aucune opération associée.'))
        :ListView.builder(itemCount:records.length,itemBuilder:(ctx,i){final r=records[i] as Map;
          return ListTile(leading:const Icon(Icons.fact_check_outlined,color:teal),title:Text((r['reference']??r['lot_number']??r['product_name']??'Opération').toString()),
            subtitle:Text('${r['process_type']} • ${r['quantity']} ${r['unit']}\nOpérateur déclaré : ${r['operator_number']}\n${r['operation_at']}'));
        })),actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Fermer'))]));
    } catch(e) {inform(e);}
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar:AppBar(title:const Text('Traçabilité matières')),
    body:ListView(padding:const EdgeInsets.all(16),children:[
      Card(color:const Color(0xfffff2d9),child:Padding(padding:const EdgeInsets.all(14),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        const Text('REGISTRE PILOTE • NON VALIDÉ POUR PRODUCTION',style:TextStyle(fontWeight:FontWeight.w800,color:Color(0xff6c4300))),
        const SizedBox(height:5),Text(widget.demo?'Mode démonstration : les opérations de traçabilité ne sont pas enregistrées.':'Numéro opérateur déclaratif et clé serveur partagée : ce registre ne constitue pas une preuve d’identité ni un journal d’audit inviolable.'),
      ]))),
      const SizedBox(height:12),
      if(widget.demo) const Card(child:Padding(padding:EdgeInsets.all(18),child:Text('La traçabilité de production sera activée après validation des comptes individuels, du serveur et des procédures qualité. Vous pouvez continuer les essais Stocks et Dossiers.')))
      else ...[
        Wrap(spacing:8,runSpacing:8,children:[
          FilledButton.icon(onPressed:addLot,icon:const Icon(Icons.add),label:const Text('Nouveau lot')),
          FilledButton.tonalIcon(onPressed:addOperation,icon:const Icon(Icons.science_outlined),label:const Text('Opération liquide / poudre')),
          OutlinedButton.icon(onPressed:load,icon:const Icon(Icons.refresh),label:const Text('Actualiser')),
        ]),
        const SizedBox(height:15),
        Text('Lots fournisseurs (${lots.length})',style:const TextStyle(fontSize:20,fontWeight:FontWeight.w800,color:Color(0xff103d4b))),
        if(loading) const LinearProgressIndicator(),
        if(error.isNotEmpty) Card(child:Padding(padding:const EdgeInsets.all(14),child:Text(error,style:const TextStyle(color:Colors.red)))),
        for(final lot in lots) Card(child:ListTile(
          leading:CircleAvatar(backgroundColor:const Color(0xffe0f4f0),child:Icon(lot['category']=='Poudre'?Icons.grain:Icons.opacity,color:teal)),
          title:Text('${lot['lot_number']} · ${lot['product_name']}',style:const TextStyle(fontWeight:FontWeight.w800)),
          subtitle:Text('${lot['supplier']} · ${lot['category']}\nCertificat : ${lot['certificate_ref'].toString().isEmpty?'non indiqué':lot['certificate_ref']}'),
          isThreeLine:true,
          trailing:IconButton(tooltip:'Dossiers concernés par ce lot',icon:const Icon(Icons.manage_search),onPressed:()=>showTrace('/material-lots/${lot['id']}/traceability','Utilisations du lot ${lot['lot_number']}')),
        )),
        const SizedBox(height:12),
        const Text('Recherche par dossier',style:TextStyle(fontSize:18,fontWeight:FontWeight.w800)),
        for(final dossier in widget.files) Card(child:ListTile(
          title:Text(dossier['reference'].toString()),subtitle:Text(dossier['client'].toString()),
          trailing:const Icon(Icons.arrow_forward_ios,size:16),onTap:()=>showTrace('/files/${dossier['id']}/traceability','Traçabilité ${dossier['reference']}'))),
      ],
    ]),
  );
}
