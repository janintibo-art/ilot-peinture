"""Simple authenticated LAN API. Add HTTPS/reverse proxy before Internet exposure."""
import os
import sqlite3
from contextlib import contextmanager
from datetime import datetime, timezone
from pathlib import Path
from typing import Literal
from fastapi import FastAPI, Header, HTTPException
from pydantic import BaseModel, Field

DATA = os.getenv('DATA_PATH', 'ilot.db')
TOKEN = os.getenv('API_TOKEN', 'CHANGEZ_CETTE_CLE_AVANT_UTILISATION')
app = FastAPI(title='Îlot Peinture API', version='1.0')

@contextmanager
def db():
    Path(DATA).parent.mkdir(parents=True, exist_ok=True)
    con = sqlite3.connect(DATA, timeout=30)
    con.row_factory = sqlite3.Row
    con.execute('PRAGMA journal_mode=WAL')
    con.execute('PRAGMA busy_timeout=30000')
    try:
        yield con
        con.commit()
    finally:
        con.close()

@app.on_event('startup')
def startup():
    with db() as c:
        c.execute('''CREATE TABLE IF NOT EXISTS products (
          id INTEGER PRIMARY KEY, name TEXT NOT NULL, category TEXT NOT NULL,
          unit TEXT NOT NULL, quantity REAL NOT NULL DEFAULT 0,
          alert_at REAL NOT NULL DEFAULT 0, location TEXT NOT NULL DEFAULT '',
          updated_at TEXT NOT NULL)''')
        c.execute('''CREATE TABLE IF NOT EXISTS files (
          id INTEGER PRIMARY KEY, reference TEXT NOT NULL UNIQUE,
          client TEXT NOT NULL, location TEXT NOT NULL, status TEXT NOT NULL DEFAULT 'Reçu',
          notes TEXT NOT NULL DEFAULT '', updated_at TEXT NOT NULL)''')
        c.execute('''CREATE TABLE IF NOT EXISTS movements (
          id INTEGER PRIMARY KEY, product_id INTEGER NOT NULL, delta REAL NOT NULL,
          reason TEXT NOT NULL, created_at TEXT NOT NULL)''')

def auth(authorization: str | None):
    if not authorization or authorization != 'Bearer ' + TOKEN:
        raise HTTPException(401, 'Clé serveur incorrecte')

def now():
    return datetime.now(timezone.utc).isoformat()

class Product(BaseModel):
    name: str = Field(min_length=1, max_length=150)
    category: Literal['Liquide', 'Poudre', 'Solvant', 'Autre']
    unit: Literal['kg', 'L', 'unité']
    quantity: float = Field(ge=0)
    alert_at: float = Field(ge=0)
    location: str = Field(default='', max_length=150)

class Movement(BaseModel):
    delta: float
    reason: str = Field(min_length=1, max_length=250)

class WorkFile(BaseModel):
    reference: str = Field(min_length=1, max_length=80)
    client: str = Field(min_length=1, max_length=150)
    location: str = Field(min_length=1, max_length=150)
    status: Literal['Reçu', 'En attente', 'En peinture', 'Terminé', 'Expédié'] = 'Reçu'
    notes: str = Field(default='', max_length=1000)

@app.get('/health')
def health():
    return {'status':'ok'}

@app.get('/products')
def products(authorization: str | None = Header(default=None)):
    auth(authorization)
    with db() as c:
        return [dict(x) for x in c.execute('SELECT * FROM products ORDER BY name COLLATE NOCASE')]

@app.post('/products')
def add_product(item: Product, authorization: str | None = Header(default=None)):
    auth(authorization)
    with db() as c:
        cur = c.execute('INSERT INTO products(name,category,unit,quantity,alert_at,location,updated_at) VALUES(?,?,?,?,?,?,?)',
          (item.name,item.category,item.unit,item.quantity,item.alert_at,item.location,now()))
        return {'id':cur.lastrowid}

@app.post('/products/{product_id}/movement')
def move(product_id: int, item: Movement, authorization: str | None = Header(default=None)):
    auth(authorization)
    if item.delta == 0:
        raise HTTPException(400, 'Mouvement nul')
    with db() as c:
        c.execute('BEGIN IMMEDIATE')
        row = c.execute('SELECT quantity FROM products WHERE id=?',(product_id,)).fetchone()
        if row is None: raise HTTPException(404,'Produit introuvable')
        if row['quantity'] + item.delta < 0: raise HTTPException(400,'Stock insuffisant')
        c.execute('UPDATE products SET quantity=quantity+?, updated_at=? WHERE id=?',(item.delta,now(),product_id))
        c.execute('INSERT INTO movements(product_id,delta,reason,created_at) VALUES(?,?,?,?)',(product_id,item.delta,item.reason,now()))
        return {'quantity': row['quantity']+item.delta}

@app.get('/files')
def files(q: str = '', authorization: str | None = Header(default=None)):
    auth(authorization)
    with db() as c:
        needle = '%' + q.strip().replace('%','\\%').replace('_','\\_') + '%'
        return [dict(x) for x in c.execute("SELECT * FROM files WHERE reference LIKE ? ESCAPE '\\' OR client LIKE ? ESCAPE '\\' OR location LIKE ? ESCAPE '\\' ORDER BY updated_at DESC LIMIT 300",(needle,needle,needle))]

@app.post('/files')
def add_file(item: WorkFile, authorization: str | None = Header(default=None)):
    auth(authorization)
    try:
        with db() as c:
            cur = c.execute('INSERT INTO files(reference,client,location,status,notes,updated_at) VALUES(?,?,?,?,?,?)',
              (item.reference,item.client,item.location,item.status,item.notes,now()))
            return {'id':cur.lastrowid}
    except sqlite3.IntegrityError:
        raise HTTPException(409,'Ce numéro de dossier existe déjà')

@app.put('/files/{file_id}')
def edit_file(file_id: int, item: WorkFile, authorization: str | None = Header(default=None)):
    auth(authorization)
    try:
        with db() as c:
            cur=c.execute('UPDATE files SET reference=?,client=?,location=?,status=?,notes=?,updated_at=? WHERE id=?',
              (item.reference,item.client,item.location,item.status,item.notes,now(),file_id))
            if not cur.rowcount: raise HTTPException(404,'Dossier introuvable')
            return {'updated':True}
    except sqlite3.IntegrityError:
        raise HTTPException(409,'Ce numéro de dossier existe déjà')
