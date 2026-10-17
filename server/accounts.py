"""Comptes pilote V21 : pas encore reliés aux écritures métier historiques."""
import hashlib
import hmac
import os
import secrets
import sqlite3
import time
from datetime import datetime, timezone
from fastapi import APIRouter, Header, HTTPException
from pydantic import BaseModel, Field

router = APIRouter(prefix='/auth', tags=['comptes-pilote'])
DATA_PATH = os.getenv('DATA_PATH', '/data/ilot.db')
ROLES = ('operateur', 'responsable', 'qualite', 'administrateur')

def connect():
    con = sqlite3.connect(DATA_PATH, timeout=30)
    con.row_factory = sqlite3.Row
    con.execute('PRAGMA busy_timeout=30000')
    return con

def init_accounts():
    with connect() as con:
        con.execute('''CREATE TABLE IF NOT EXISTS users_v21 (
            employee_number TEXT PRIMARY KEY, role TEXT NOT NULL,
            salt TEXT NOT NULL, password_hash TEXT NOT NULL,
            active INTEGER NOT NULL DEFAULT 1, created_at TEXT NOT NULL)''')
        con.execute('''CREATE TABLE IF NOT EXISTS sessions_v21 (
            token_hash TEXT PRIMARY KEY, employee_number TEXT NOT NULL,
            expires_at INTEGER NOT NULL, FOREIGN KEY(employee_number) REFERENCES users_v21(employee_number))''')
        con.execute('''CREATE TABLE IF NOT EXISTS auth_events_v21 (
            id INTEGER PRIMARY KEY, employee_number TEXT NOT NULL,
            action TEXT NOT NULL, at TEXT NOT NULL)''')

def derive(secret, salt):
    return hashlib.pbkdf2_hmac('sha256', secret.encode('utf-8'), bytes.fromhex(salt), 600000).hex()

def check_password(p, row):
    return hmac.compare_digest(derive(p, row['salt']), row['password_hash'])

def log(con, number, action):
    con.execute('INSERT INTO auth_events_v21(employee_number,action,at) VALUES(?,?,?)',
                (number, action, datetime.now(timezone.utc).isoformat()))

class Credentials(BaseModel):
    employee_number: str = Field(pattern=r'^\d{1,8}$')
    password: str = Field(min_length=12, max_length=128)

class NewUser(Credentials):
    role: str = 'operateur'

def current(authorization):
    if not authorization or not authorization.startswith('Bearer '):
        raise HTTPException(401, 'Connexion personnelle requise')
    digest = hashlib.sha256(authorization[7:].encode()).hexdigest()
    with connect() as con:
        r = con.execute('''SELECT u.employee_number,u.role FROM sessions_v21 s
               JOIN users_v21 u ON u.employee_number=s.employee_number
               WHERE s.token_hash=? AND s.expires_at>? AND u.active=1''',
               (digest, int(time.time()))).fetchone()
        if not r:
            raise HTTPException(401, 'Session expirée ou invalide')
        return dict(r)

@router.post('/login')
def login(item: Credentials):
    # Pilote LAN uniquement : un mécanisme de limitation centralisée des tentatives
    # et TLS devront être ajoutés avant un déploiement réel.
    with connect() as con:
        u = con.execute('SELECT * FROM users_v21 WHERE employee_number=?',
                        (item.employee_number,)).fetchone()
        if not u or not u['active'] or not check_password(item.password, u):
            log(con, item.employee_number, 'LOGIN_FAILED')
            raise HTTPException(401, 'Identifiants incorrects')
        token = secrets.token_urlsafe(48)
        expires = int(time.time()) + 8 * 3600
        con.execute('INSERT INTO sessions_v21 VALUES(?,?,?)',
                    (hashlib.sha256(token.encode()).hexdigest(), item.employee_number, expires))
        log(con, item.employee_number, 'LOGIN_OK')
        return {'access_token':token, 'expires_at':expires,
                'employee_number':u['employee_number'], 'role':u['role']}

@router.get('/me')
def me(authorization: str | None = Header(default=None)):
    return current(authorization)

@router.post('/logout')
def logout(authorization: str | None = Header(default=None)):
    user = current(authorization)
    with connect() as con:
        con.execute('DELETE FROM sessions_v21 WHERE token_hash=?',
                    (hashlib.sha256(authorization[7:].encode()).hexdigest(),))
        log(con, user['employee_number'], 'LOGOUT')
    return {'ok':True}

@router.post('/users', status_code=201)
def add_user(item: NewUser, authorization: str | None = Header(default=None)):
    actor = current(authorization)
    if actor['role'] != 'administrateur':
        raise HTTPException(403, 'Administrateur requis')
    if item.role not in ROLES:
        raise HTTPException(422, 'Rôle inconnu')
    salt = secrets.token_hex(16)
    try:
        with connect() as con:
            con.execute('INSERT INTO users_v21 VALUES(?,?,?,?,1,?)',
                       (item.employee_number,item.role,salt,derive(item.password,salt),
                        datetime.now(timezone.utc).isoformat()))
            log(con, actor['employee_number'], 'CREATE_USER:'+item.employee_number)
    except sqlite3.IntegrityError:
        raise HTTPException(409, 'Numéro déjà utilisé')
    return {'employee_number':item.employee_number, 'role':item.role}

@router.get('/events')
def auth_events(authorization: str | None = Header(default=None)):
    actor = current(authorization)
    if actor['role'] not in ('administrateur', 'qualite'):
        raise HTTPException(403, 'Accès réservé')
    with connect() as con:
        return [dict(x) for x in con.execute('SELECT * FROM auth_events_v21 ORDER BY id DESC LIMIT 300')]
