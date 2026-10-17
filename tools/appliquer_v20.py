from pathlib import Path
p=Path.home()/'ilot_peinture/lib/main.dart'
s=p.read_text(encoding='utf-8')
import_line="import 'traceability_screen.dart';\n"
needle="import 'demo_store.dart';\n"
if import_line not in s:
    if s.count(needle)!=1: raise SystemExit('Import V19 introuvable : aucune modification')
    s=s.replace(needle,needle+import_line,1)
old="IconButton(tooltip:'Actualiser',onPressed:refresh,icon:const Icon(Icons.refresh))"
new="IconButton(tooltip:'Traçabilité pilote',onPressed:()=>Navigator.of(context).push(MaterialPageRoute(builder:(context)=>TraceabilityScreen(request:api.request,demo:api.demo,products:products,files:files,employeeNumber:employeeNumber))),icon:const Icon(Icons.fact_check_outlined)),"+old
if "tooltip:'Traçabilité pilote'" not in s:
    if s.count(old)!=1: raise SystemExit('Barre de navigation V19 introuvable : aucune modification')
    s=s.replace(old,new,1)
p.write_text(s,encoding='utf-8')
print('V20 appliquée : accès traçabilité dans la barre supérieure')
