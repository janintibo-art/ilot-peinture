"""Sauvegarde SQLite cohérente (API SQLite backup), à lancer dans le conteneur."""
import os,sqlite3,datetime
from pathlib import Path
source=Path(os.getenv('DATA_PATH','/data/ilot.db'))
folder=Path(os.getenv('BACKUP_DIR','/data/backups'))
if not source.is_file(): raise SystemExit('Base absente: '+str(source))
folder.mkdir(parents=True,exist_ok=True)
target=folder/('ilot-'+datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%SZ')+'.sqlite3')
with sqlite3.connect(source) as src, sqlite3.connect(target) as dst:
    src.backup(dst)
    check=dst.execute('PRAGMA integrity_check').fetchone()[0]
    if check != 'ok':
        target.unlink(missing_ok=True)
        raise RuntimeError('Sauvegarde invalide: '+check)
os.chmod(target,0o600)
print(target)
