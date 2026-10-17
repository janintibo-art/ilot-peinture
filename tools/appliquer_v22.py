"""Applique la V22 à la V21/V20, sans écraser les autres modifications."""
from pathlib import Path
root = Path(__file__).resolve().parents[1]
main = root / 'lib/main.dart'
server = root / 'server/main.py'
s = main.read_text(encoding='utf-8')
t = server.read_text(encoding='utf-8')

def replace_once(text, old, new, label):
    if new in text: return text
    if text.count(old) != 1: raise SystemExit(f'V22 : repère introuvable ou ambigu : {label} (aucun fichier modifié).')
    return text.replace(old, new, 1)

s=replace_once(s, "import 'demo_store.dart';", "import 'demo_store.dart';\nimport 'account_screen.dart';", 'import')
s=replace_once(s, "  bool demo = false;", "  bool demo = false;\n  String personalToken = '';\n  String personalRole = '';", 'état session')
s=replace_once(s, "final headers = {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'};", "final headers = {'Authorization': 'Bearer ${personalToken.isEmpty ? token : personalToken}', 'Content-Type': 'application/json'};", 'token requête')
needle="  Future<void> settings() async {"
insert="""  Future<void> accountScreen() async {
    if (api.demo) { message('Le mode démonstration ne nécessite pas de compte.'); return; }
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => AccountScreen(
      server: api.url, initialNumber: employeeNumber, currentToken: api.personalToken,
      onSession: (token, number, role) {
        api.personalToken = token;
        api.personalRole = role;
        if (number.isNotEmpty) employeeNumber = number;
        if (mounted) setState(() {});
      },
    )));
    if (mounted) await refresh();
  }
"""
s=replace_once(s, needle, insert+needle, 'écran compte')
s=replace_once(s, "IconButton(tooltip:'Actualiser',onPressed:refresh", "IconButton(tooltip:'Compte professionnel',onPressed:accountScreen,icon:Icon(api.personalToken.isEmpty?Icons.person_outline:Icons.verified_user_outlined)),IconButton(tooltip:'Actualiser',onPressed:refresh", 'bouton compte')
# On change d'adresse ou de clé serveur : la session personnelle précédente n'est plus réutilisée.
s=replace_once(s, "await api.save(server.text,key.text); if(dialog.mounted)", "await api.save(server.text,key.text); api.personalToken=''; api.personalRole=''; if(dialog.mounted)", 'changement de serveur')
# Les routes existantes ne deviennent PAS une preuve d'identité : elles acceptent temporairement
# le jeton personnel OU la clé partagée historique. Cette dérogation doit disparaître avant production.
t=replace_once(t,"from accounts import router as account_router, init_accounts", "from accounts import router as account_router, init_accounts, current as current_account", 'imports serveur')
old="""def auth(authorization: str | None):
    if not authorization or not hmac.compare_digest(authorization, 'Bearer ' + TOKEN):
        raise HTTPException(401, 'Clé serveur incorrecte')"""
new="""def auth(authorization: str | None):
    # Transition V22 : clé API historique ou session individuelle valide.
    # Les anciennes écritures par clé partagée restent possibles : PAS d'audit nominatif garanti.
    if authorization and hmac.compare_digest(authorization, 'Bearer ' + TOKEN):
        return None
    return current_account(authorization)"""
t=replace_once(t,old,new,'authentification API')
# Write only after all assertions succeed.
main.write_text(s,encoding='utf-8')
server.write_text(t,encoding='utf-8')
print('V22 : écran de connexion et support des sessions appliqués.')
