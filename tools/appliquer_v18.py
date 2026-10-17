from pathlib import Path
p = Path.home() / 'ilot_peinture' / 'lib' / 'main.dart'
if not p.is_file():
    raise SystemExit('Projet introuvable : '+str(p))
s = p.read_text(encoding='utf-8')
changes = [
('scaffoldBackgroundColor: const Color(0xfff2f6f7), cardTheme: CardThemeData(elevation:0, color:Colors.white,shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(18)))',
 'scaffoldBackgroundColor: const Color(0xffeaf1f4), cardTheme: CardThemeData(elevation:3,shadowColor:const Color(0x33093b4a),color:Colors.white,shape:RoundedRectangleBorder(side:const BorderSide(color:Color(0xffd7e7ea)),borderRadius:BorderRadius.circular(20)))'),
('bottomNavigationBar:NavigationBar(selectedIndex:page',
 'bottomNavigationBar:NavigationBar(height:72,indicatorColor:const Color(0xffc6eeea),backgroundColor:const Color(0xfff8fcfd),selectedIndex:page'),
("const Text('Accès rapide',style:TextStyle(fontSize:20,fontWeight:FontWeight.bold))", "const Text('Accès rapide',style:TextStyle(fontSize:20,fontWeight:FontWeight.w800,color:Color(0xff103d4b)))"),
("const Text('Stocks & consommables',style:TextStyle(fontSize:23,fontWeight:FontWeight.bold))", "const Text('Stocks & consommables',style:TextStyle(fontSize:23,fontWeight:FontWeight.w800,color:Color(0xff103d4b)))"),
("const Text('Suivi des dossiers',style:TextStyle(fontSize:23,fontWeight:FontWeight.bold))", "const Text('Suivi des dossiers',style:TextStyle(fontSize:23,fontWeight:FontWeight.w800,color:Color(0xff103d4b)))"),
('Widget metric(String label,String value,IconData icon,{double width=145})=>SizedBox(width:width,height:112,child:Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Icon(icon,color:const Color(0xff007d87)),const Spacer(),Text(value,style:const TextStyle(fontSize:27,fontWeight:FontWeight.w800)),Text(label,style:const TextStyle(fontSize:12))]))));',
 'Widget metric(String label,String value,IconData icon,{double width=145})=>SizedBox(width:width,height:126,child:Card(child:Padding(padding:const EdgeInsets.all(13),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Container(padding:const EdgeInsets.all(7),decoration:BoxDecoration(color:const Color(0xffdbf4f1),borderRadius:BorderRadius.circular(11)),child:Icon(icon,color:const Color(0xff007d87),size:20)),const Spacer(),Text(value,style:const TextStyle(fontSize:28,fontWeight:FontWeight.w900,color:Color(0xff103d4b))),Text(label,style:const TextStyle(fontSize:12,fontWeight:FontWeight.w600))]))));'),
('Card(child:ListTile(leading:const Icon(Icons.search)', 'Card(child:ListTile(leading:const CircleAvatar(backgroundColor:Color(0xffdbf4f1),child:Icon(Icons.search,color:Color(0xff007d87)))'),
('Card(child:ListTile(leading:const Icon(Icons.add_box_outlined)', 'Card(child:ListTile(leading:const CircleAvatar(backgroundColor:Color(0xffdbf4f1),child:Icon(Icons.add_box_outlined,color:Color(0xff007d87)))'),
]
missing=[old[:65] for old,new in changes if old not in s and new not in s]
if missing:
    raise SystemExit('V18 non appliquée, version du projet différente : '+repr(missing))
count=0
for old,new in changes:
    if old in s:
        s=s.replace(old,new,1)
        count+=1
if count:
    p.write_text(s,encoding='utf-8')
print(f'V18 : {count} adaptations graphiques appliquées ; aucune donnée métier modifiée.')
