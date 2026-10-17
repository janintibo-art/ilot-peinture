"""À exécuter une seule fois par un administrateur, depuis la VM et hors GitHub."""
import getpass
import os
import re
import secrets
from datetime import datetime, timezone
from accounts import connect, derive, init_accounts

if __name__ == '__main__':
    init_accounts()
    number = input('Numéro administrateur (1-8 chiffres) : ').strip()
    if not re.fullmatch(r'\d{1,8}', number):
        raise SystemExit('Numéro invalide')
    password = getpass.getpass('Mot de passe (minimum 12 caractères) : ')
    if len(password) < 12 or len(password) > 128:
        raise SystemExit('Longueur du mot de passe invalide')
    with connect() as con:
        existing = con.execute('SELECT COUNT(*) FROM users_v21').fetchone()[0]
        if existing:
            raise SystemExit('Des comptes existent déjà : amorçage refusé')
        salt = secrets.token_hex(16)
        con.execute('INSERT INTO users_v21 VALUES(?,?,?,?,1,?)',
                    (number, 'administrateur', salt, derive(password,salt),
                     datetime.now(timezone.utc).isoformat()))
    print('Administrateur initial créé ; identifiant et mot de passe non affichés.')
