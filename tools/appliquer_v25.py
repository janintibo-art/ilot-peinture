from pathlib import Path
p = Path.home() / 'ilot_peinture/lib/main.dart'
s = p.read_text(encoding='utf-8')
import_line = "import 'audit_screen.dart';\n"
needle = "import 'account_screen.dart';\n"
anchor = "IconButton(tooltip:'Compte professionnel',onPressed:accountScreen"
if import_line in s and "tooltip:'Journal qualité'" in s:
    print('V25 déjà appliquée')
else:
    if s.count(needle) != 1 or s.count(anchor) != 1:
        raise SystemExit('V25 annulée : fichier Flutter incompatible ou version attendue absente.')
    s = s.replace(needle, needle + import_line, 1)
    snippet = "IconButton(tooltip:'Journal qualité',onPressed:(){if(api.demo){message('Journal qualité indisponible en démonstration.');return;}if(api.personalToken.isEmpty || !['qualite','administrateur'].contains(api.personalRole)){message('Compte qualité ou administrateur requis.');return;}Navigator.of(context).push(MaterialPageRoute<void>(builder:(_)=>AuditScreen(request:api.request)));},icon:const Icon(Icons.manage_search_outlined)),"
    s = s.replace(anchor, snippet + anchor, 1)
    p.write_text(s, encoding='utf-8')
    print('V25 intégrée dans lib/main.dart')
