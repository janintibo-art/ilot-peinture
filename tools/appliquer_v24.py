from pathlib import Path
import re
p=Path.home()/'ilot_peinture/server/main.py'
s=p.read_text(encoding='utf-8')
if 'V24_ATOMIC_AUDIT' in s:
 print('V24 déjà appliquée');raise SystemExit(0)
assert 'async def v23_audit' in s and 'def write_auth(' in s
# Remove best-effort middleware: writes will audit inside SQLite transactions.
start=s.index('# V23 : journal de transition')
end=s.index('\ndef now():',start)
s=s[:start]+'# V24_ATOMIC_AUDIT : le journal métier est écrit dans chaque transaction SQLite.\n'+s[end:]
anchor='    init_accounts()'
assert s.count(anchor)==1
s=s.replace(anchor,"""    with db() as c:
        c.execute('''CREATE TABLE IF NOT EXISTS audit_events_v24 (
            id INTEGER PRIMARY KEY, actor TEXT NOT NULL, role TEXT NOT NULL,
            action TEXT NOT NULL, target TEXT NOT NULL, details TEXT NOT NULL,
            at TEXT NOT NULL)''')
        c.execute('CREATE INDEX IF NOT EXISTS idx_audit_v24_actor ON audit_events_v24(actor,id DESC)')
    init_accounts()""",1)
needle='# V23_AUTH_GUARD : toute écriture exige un jeton de session personnel valide.\ndef write_auth(authorization: str | None):\n    return current_account(authorization)'
assert needle in s
s=s.replace(needle,"""# V24 : roles d'ecriture. Le role qualite peut consulter le registre,
# et l'administrateur garde les fonctions de gestion des zones.
def write_auth(authorization: str | None, required_role: str = 'operateur'):
    actor = current_account(authorization)
    grants = {
        'operateur': {'operateur','responsable','qualite','administrateur'},
        'responsable': {'responsable','administrateur'},
        'administrateur': {'administrateur'},
    }
    if actor['role'] not in grants[required_role]:
        raise HTTPException(403, 'Habilitation insuffisante')
    return actor

def audit_v24(c, actor, action, target, details=''):
    # Appeler à l'intérieur du même `with db()` que la modification.
    c.execute('''INSERT INTO audit_events_v24(actor,role,action,target,details,at)
                 VALUES(?,?,?,?,?,?)''',
              (actor['employee_number'],actor['role'],action,str(target),str(details)[:2000],now()))

@app.get('/audit/events')
def audit_events_v24(authorization: str | None = Header(default=None),
                     employee_number: str = '', action: str = '', limit: int = 100):
    actor = current_account(authorization)
    if actor['role'] not in ('qualite','administrateur'):
        raise HTTPException(403, 'Réservé au service qualité et aux administrateurs')
    if limit < 1 or limit > 300: raise HTTPException(422, 'Limite invalide')
    with db() as c:
        return [dict(row) for row in c.execute('''SELECT * FROM audit_events_v24
          WHERE (?='' OR actor=?) AND (?='' OR action=?) ORDER BY id DESC LIMIT ?''',
          (employee_number,employee_number,action,action,limit))]
""")
# Find each mutation body and insert logging before its last return, while still inside `with db()`.
mutations={
 'add_product':('CREATE_PRODUCT',"cur.lastrowid",'item.name'),
 'move':('MOVE_STOCK','product_id','item.delta'),
 'add_file':('CREATE_FILE','cur.lastrowid','item.reference'),
 'edit_file':('EDIT_FILE','file_id',"f'{old[\"location\"]} -> {item.location}; {old[\"status\"]} -> {item.status}'"),
 'create_zone':('CREATE_ZONE','cur.lastrowid','item.name'),
 'create_location':('CREATE_LOCATION','cur.lastrowid','item.name'),
 'delete_location':('DELETE_LOCATION','location_id','loc[\'name\']'),
 'delete_zone':('DELETE_ZONE','zone_id',"''"),
 'add_material_lot':('CREATE_LOT','cur.lastrowid','item.lot_number'),
 'add_process_record':('CREATE_PROCESS','cur.lastrowid','item.process_type'),
}
for name,(action,target,details) in mutations.items():
    m=re.search(r'^def '+name+r'\(.*?(?=^@app\.|^class |\Z)',s,re.M|re.S)
    assert m,name
    body=m.group()
    assert 'write_auth(authorization)' in body,name
    body=body.replace('write_auth(authorization)',"write_auth(authorization, 'administrateur')" if name in {'delete_zone','delete_location'} else ("write_auth(authorization, 'responsable')" if name in {'create_zone','create_location'} else 'write_auth(authorization)'),1)
    matches=list(re.finditer(r'^([ \t]*)return \{',body,re.M))
    assert matches,name
    ret=matches[-1]
    indent=ret.group(1)
    insert=f"{indent}audit_v24(c, current_account(authorization), '{action}', {target}, {details})\n"
    body=body[:ret.start()]+insert+body[ret.start():]
    s=s[:m.start()]+body+s[m.end():]
p.write_text(s,encoding='utf-8')
print('V24 appliquée: 10 mutations avec journal transactionnel et droits par rôle')
