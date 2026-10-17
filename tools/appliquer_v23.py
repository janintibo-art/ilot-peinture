#!/usr/bin/env python3
"""V23 migration contrôlée sur la base GitHub V22, sans remplacer les sources complètes."""
from pathlib import Path
import re, ast
root=Path.home()/ 'ilot_peinture'
srv=root/'server/main.py'; app=root/'lib/main.dart'; trace=root/'lib/traceability_screen.dart'; acct=root/'lib/account_screen.dart'
for p in [srv,app,trace,acct]:
    if not p.exists(): raise SystemExit(f'Fichier absent : {p}')
S=srv.read_text(); A=app.read_text(); T=trace.read_text(); C=acct.read_text()
if 'V23_AUTH_GUARD' in S: raise SystemExit('V23 déjà appliquée : aucun changement')
if 'current as current_account' not in S: raise SystemExit('V21/V22 absente côté serveur')
if "String personalToken = '';" not in A: raise SystemExit('V22 absente côté Android')
# Correspondance systématique des écritures déclarées dans l’API.
rx=re.compile(r'(?P<decor>@app\.(?:post|put|delete|patch)\([^\n]*\)\n)(?P<def>def [^\n]+:\n)(?P<body>(?:(?!@app\.|class |def ).|\n)*?)(?=\n@app\.|\nclass |\n# V14|\Z)',re.M)
# Utiliser l'analyse par ligne plutôt que le regroupement regexp pour conserver toutes les indentations.
lines=S.splitlines(keepends=True); records=[]
for i,line in enumerate(lines):
    if re.match(r'^@app\.(post|put|delete|patch)\(',line):
        j=i+1
        while j<len(lines) and not lines[j].startswith('def '): j+=1
        if j==len(lines): raise SystemExit('Décorateur sans fonction')
        k=j+1
        while k<len(lines) and not (lines[k].startswith('@app.') or lines[k].startswith('class ') or lines[k].startswith('def ') or lines[k].startswith('# V14')): k+=1
        positions=[m for m in range(j+1,k) if lines[m].strip()=='auth(authorization)']
        if len(positions)!=1: raise SystemExit(f'Verrouillage impossible : {lines[j].strip()}, auth={len(positions)}')
        records.append(positions[0])
if len(records)<7: raise SystemExit(f'Nombre de routes inattendu ({len(records)})')
for i in records: lines[i]=lines[i].replace('auth(authorization)','write_auth(authorization)')
S=''.join(lines)
anchor='class Product(BaseModel):'
if anchor not in S: raise SystemExit('Classe Product introuvable')
security='''# V23_AUTH_GUARD : toute écriture exige un jeton de session personnel valide.
def write_auth(authorization: str | None):
    return current_account(authorization)

'''
S=S.replace(anchor,security+anchor,1)
# Identité opérateur provient impérativement du jeton serveur, pas du formulaire Android.
needle="def add_process_record(item: ProcessRecordIn, authorization: str | None = Header(default=None)):\n    write_auth(authorization)"
if needle not in S: raise SystemExit('Route operation introuvable')
S=S.replace(needle, needle+"\n    actor = current_account(authorization)\n    item = item.model_copy(update={'operator_number': actor['employee_number']})",1)
# Journal d'audit de transition : écriture après réponse, n'est PAS atomique avec le métier.
anchor="app.include_router(account_router)"
if anchor not in S: raise SystemExit('Montage auth absent')
middleware='''
# V23 : journal de transition (non transactionnel, ne vaut pas piste d'audit certifiée).
from fastapi import Request
@app.middleware('http')
async def v23_audit(request: Request, call_next):
    response = await call_next(request)
    if request.method in ('POST','PUT','PATCH','DELETE') and not request.url.path.startswith('/auth/') and response.status_code < 400:
        try:
            actor = current_account(request.headers.get('authorization'))
            with db() as con:
                con.execute('CREATE TABLE IF NOT EXISTS audit_events_v23 (id INTEGER PRIMARY KEY, operator_number TEXT NOT NULL, method TEXT NOT NULL, endpoint TEXT NOT NULL, at TEXT NOT NULL)')
                con.execute('INSERT INTO audit_events_v23(operator_number,method,endpoint,at) VALUES(?,?,?,?)',
                  (actor['employee_number'],request.method,request.url.path,now()))
        except Exception:
            # Un incident de journalisation reste un blocage pour le passage en production.
            # L'intégrité transactionnelle sera implémentée dans les handlers métier.
            pass
    return response
'''
S=S.replace(anchor,anchor+'\n'+middleware,1)
# Android : supprimer le retour silencieux à la clé commune pour toutes les écritures.
needle="if (url.isEmpty || token.isEmpty) throw Exception('Configurez le serveur dans Réglages.');"
if needle not in A: raise SystemExit('Contrôle connexion introuvable')
A=A.replace(needle,"if (url.isEmpty) throw Exception('Configurez le serveur dans Réglages.');\n    if (method != 'GET' && personalToken.isEmpty) throw Exception('Connectez-vous avec votre compte professionnel pour cette action.');\n    if (method == 'GET' && personalToken.isEmpty && token.isEmpty) throw Exception('Connexion au serveur requise.');",1)
# Garder la clé commune seulement pour les lectures, pas de fallback sur écriture.
needle="'Bearer ${personalToken.isEmpty ? token : personalToken}'"
if needle not in A: raise SystemExit('En-tête d’autorisation introuvable')
A=A.replace(needle,"'Bearer ${personalToken.isNotEmpty ? personalToken : token}'",1)
# Limite d'une session : le numéro saisi pour trace devient purement informatif. Le serveur impose l'acteur.
T=T.replace("const Text('Registre pilote : numéro opérateur déclaratif, sans validation d’identité ni signature.'", "const Text('Identité imposée par la session serveur en V23 ; ceci ne constitue pas une signature qualité.'")
C=C.replace("La clé commune historique reste utilisable pour certaines actions et le journal métier doit encore être renforcé.", "Les opérations d’écriture exigent désormais une session personnelle. Le journal doit encore être rendu transactionnel et audité.")
# Python syntax check first, then commit target file writes.
ast.parse(S)
for p,content in [(srv,S),(app,A),(trace,T),(acct,C)]:p.write_text(content)
print(f'V23 appliquée : {len(records)} routes d’écriture exigent une session personnelle. Vérifier les tests GitHub et les contrôles SSI avant toute utilisation réelle.')
