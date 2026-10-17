from pathlib import Path
p=Path.home()/'ilot_peinture/server/main.py'
s=p.read_text(encoding='utf-8')
needle='app = FastAPI('
if s.count(needle)!=1:
    raise SystemExit('Structure serveur V14 absente, pas de modification')
if 'from accounts import router as account_router' not in s:
    at=s.index(needle)
    s=s[:at]+'from accounts import router as account_router, init_accounts\n'+s[at:]
if 'app.include_router(account_router)' not in s:
    marker='\n@contextmanager\ndef db():'
    # router registration after app declaration, before first endpoint
    import re
    pattern=r'(app = FastAPI\([^\n]+\)\n)'
    new,n=re.subn(pattern,r'\1app.include_router(account_router)\n',s,count=1)
    if n!=1:raise SystemExit('Déclaration FastAPI introuvable')
    s=new
if 'init_accounts()' not in s:
    marker='@app.on_event(\'startup\')\ndef startup():\n'
    if s.count(marker)!=1:raise SystemExit('Startup serveur introuvable')
    end=s.find('\ndef auth(',s.index(marker))
    if end<0: raise SystemExit('Fin startup introuvable')
    s=s[:end]+'    init_accounts()\n'+s[end:]
p.write_text(s,encoding='utf-8')
print('V21 serveur : API comptes ajoutée (sans changer l’authentification des opérations métier existantes)')
