"""Îlot Peinture - API locale. Pour une production: TLS, identité individuelle, audit et revue SSI."""
import os
import hmac
import sqlite3
from contextlib import contextmanager
from datetime import datetime, timezone
from pathlib import Path
from typing import Literal
from fastapi import FastAPI, Header, HTTPException
from pydantic import BaseModel, Field

DATA = os.getenv('DATA_PATH', '/data/ilot.db')
TOKEN = os.getenv('API_TOKEN', '')
if len(TOKEN) < 32 or TOKEN == 'CHANGEZ_CETTE_CLE_AVANT_UTILISATION':
    raise RuntimeError('API_TOKEN absent ou trop court (minimum 32 caractères).')
app = FastAPI(title='Îlot Peinture API', version='12.0', docs_url=None, redoc_url=None)

def now():
    return datetime.now(timezone.utc).isoformat()

@contextmanager
def db():
    Path(DATA).parent.mkdir(parents=True, exist_ok=True)
    con = sqlite3.connect(DATA, timeout=30, isolation_level=None)
    con.row_factory = sqlite3.Row
    con.execute('PRAGMA journal_mode=WAL')
    con.execute('PRAGMA busy_timeout=30000')
    try:
        con.execute('BEGIN IMMEDIATE')
        yield con
        con.commit()
    except BaseException:
        con.rollback()
        raise
    finally:
        con.close()

@app.on_event('startup')
def startup():
    with db() as c:
        c.execute("""CREATE TABLE IF NOT EXISTS products (
          id INTEGER PRIMARY KEY, name TEXT NOT NULL, category TEXT NOT NULL,
          unit TEXT NOT NULL, quantity REAL NOT NULL DEFAULT 0,
          alert_at REAL NOT NULL DEFAULT 0, location TEXT NOT NULL DEFAULT '',
          updated_at TEXT NOT NULL)""")
        c.execute("""CREATE TABLE IF NOT EXISTS files (
          id INTEGER PRIMARY KEY, reference TEXT NOT NULL UNIQUE,
          client TEXT NOT NULL, location TEXT NOT NULL, status TEXT NOT NULL DEFAULT 'Reçu',
          notes TEXT NOT NULL DEFAULT '', updated_at TEXT NOT NULL)""")
        c.execute("""CREATE TABLE IF NOT EXISTS movements (
          id INTEGER PRIMARY KEY, product_id INTEGER NOT NULL, delta REAL NOT NULL,
          reason TEXT NOT NULL, created_at TEXT NOT NULL)""")
        c.execute("""CREATE TABLE IF NOT EXISTS file_history (
          id INTEGER PRIMARY KEY, file_id INTEGER NOT NULL,
          previous_location TEXT NOT NULL, new_location TEXT NOT NULL,
          previous_status TEXT NOT NULL, new_status TEXT NOT NULL,
          changed_at TEXT NOT NULL)""")
        c.execute("""CREATE TABLE IF NOT EXISTS zones (
          id INTEGER PRIMARY KEY, name TEXT NOT NULL UNIQUE COLLATE NOCASE)""")
        c.execute("""CREATE TABLE IF NOT EXISTS locations (
          id INTEGER PRIMARY KEY, zone_id INTEGER NOT NULL REFERENCES zones(id),
          name TEXT NOT NULL UNIQUE COLLATE NOCASE)""")
        c.execute('CREATE INDEX IF NOT EXISTS idx_file_history_file ON file_history(file_id, id DESC)')
        c.execute('CREATE INDEX IF NOT EXISTS idx_movements_product ON movements(product_id, id DESC)')

def auth(authorization: str | None):
    if not authorization or not hmac.compare_digest(authorization, 'Bearer ' + TOKEN):
        raise HTTPException(401, 'Clé serveur incorrecte')

class Product(BaseModel):
    name: str = Field(min_length=1, max_length=150)
    category: Literal['Liquide', 'Poudre', 'Solvant', 'Autre']
    unit: Literal['kg', 'L', 'unité']
    quantity: float = Field(ge=0, allow_inf_nan=False)
    alert_at: float = Field(ge=0, allow_inf_nan=False)
    location: str = Field(default='', max_length=150)

class Movement(BaseModel):
    delta: float = Field(allow_inf_nan=False)
    reason: str = Field(min_length=1, max_length=250)

class WorkFile(BaseModel):
    reference: str = Field(min_length=1, max_length=80)
    client: str = Field(min_length=1, max_length=150)
    location: str = Field(min_length=1, max_length=150)
    status: Literal['Reçu', 'En attente', 'En peinture', 'Terminé', 'Expédié'] = 'Reçu'
    notes: str = Field(default='', max_length=1000)

class ZoneIn(BaseModel):
    name: str = Field(min_length=1, max_length=80)

class LocationIn(BaseModel):
    zone_id: int = Field(gt=0)
    name: str = Field(min_length=1, max_length=150)

@app.get('/health')
def health():
    return {'status': 'ok'}

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
        if item.quantity:
            c.execute('INSERT INTO movements(product_id,delta,reason,created_at) VALUES(?,?,?,?)',
                      (cur.lastrowid,item.quantity,'Stock initial',now()))
        return {'id':cur.lastrowid}

@app.post('/products/{product_id}/movement')
def move(product_id: int, item: Movement, authorization: str | None = Header(default=None)):
    auth(authorization)
    if item.delta == 0: raise HTTPException(400, 'Mouvement nul')
    with db() as c:
        row = c.execute('SELECT quantity FROM products WHERE id=?',(product_id,)).fetchone()
        if row is None: raise HTTPException(404,'Produit introuvable')
        new = round(row['quantity'] + item.delta, 6)
        if new < 0: raise HTTPException(400,'Stock insuffisant')
        c.execute('UPDATE products SET quantity=?, updated_at=? WHERE id=?',(new,now(),product_id))
        c.execute('INSERT INTO movements(product_id,delta,reason,created_at) VALUES(?,?,?,?)',(product_id,item.delta,item.reason,now()))
        return {'quantity': new}

@app.get('/products/{product_id}/history')
def product_history(product_id: int, authorization: str | None = Header(default=None)):
    auth(authorization)
    with db() as c:
        return [dict(x) for x in c.execute('SELECT * FROM movements WHERE product_id=? ORDER BY id DESC LIMIT 150',(product_id,))]

@app.get('/files')
def files(q: str = '', authorization: str | None = Header(default=None)):
    auth(authorization)
    with db() as c:
        needle = '%' + q.strip().replace('\\','\\\\').replace('%','\\%').replace('_','\\_') + '%'
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
            old = c.execute('SELECT * FROM files WHERE id=?', (file_id,)).fetchone()
            if old is None: raise HTTPException(404,'Dossier introuvable')
            c.execute('UPDATE files SET reference=?,client=?,location=?,status=?,notes=?,updated_at=? WHERE id=?',
              (item.reference,item.client,item.location,item.status,item.notes,now(),file_id))
            if old['location'] != item.location or old['status'] != item.status:
                c.execute('INSERT INTO file_history(file_id,previous_location,new_location,previous_status,new_status,changed_at) VALUES(?,?,?,?,?,?)',
                  (file_id,old['location'],item.location,old['status'],item.status,now()))
            return {'updated':True}
    except sqlite3.IntegrityError:
        raise HTTPException(409,'Ce numéro de dossier existe déjà')

@app.get('/files/{file_id}/history')
def file_history(file_id: int, authorization: str | None = Header(default=None)):
    auth(authorization)
    with db() as c:
        return [dict(x) for x in c.execute('SELECT * FROM file_history WHERE file_id=? ORDER BY id DESC LIMIT 150',(file_id,))]

@app.get('/zones')
def get_zones(authorization: str | None = Header(default=None)):
    auth(authorization)
    with db() as c:
        zones = [dict(x) for x in c.execute('SELECT * FROM zones ORDER BY name COLLATE NOCASE')]
        for z in zones:
            z['locations'] = [dict(x) for x in c.execute('SELECT id,name FROM locations WHERE zone_id=? ORDER BY name COLLATE NOCASE',(z['id'],))]
        return zones

@app.post('/zones')
def create_zone(item: ZoneIn, authorization: str | None = Header(default=None)):
    auth(authorization)
    try:
        with db() as c:
            cur=c.execute('INSERT INTO zones(name) VALUES(?)',(item.name.strip(),))
            return {'id':cur.lastrowid}
    except sqlite3.IntegrityError: raise HTTPException(409,'Zone déjà existante')

@app.post('/locations')
def create_location(item: LocationIn, authorization: str | None = Header(default=None)):
    auth(authorization)
    try:
        with db() as c:
            if c.execute('SELECT id FROM zones WHERE id=?',(item.zone_id,)).fetchone() is None:
                raise HTTPException(404,'Zone introuvable')
            cur=c.execute('INSERT INTO locations(zone_id,name) VALUES(?,?)',(item.zone_id,item.name.strip()))
            return {'id':cur.lastrowid}
    except sqlite3.IntegrityError: raise HTTPException(409,'Emplacement déjà existant')

@app.delete('/locations/{location_id}')
def delete_location(location_id: int, authorization: str | None = Header(default=None)):
    auth(authorization)
    with db() as c:
        loc=c.execute('SELECT name FROM locations WHERE id=?',(location_id,)).fetchone()
        if loc is None: raise HTTPException(404,'Emplacement introuvable')
        if c.execute('SELECT 1 FROM files WHERE location=? LIMIT 1',(loc['name'],)).fetchone():
            raise HTTPException(409,'Emplacement utilisé par un dossier')
        c.execute('DELETE FROM locations WHERE id=?',(location_id,))
        return {'deleted':True}

@app.delete('/zones/{zone_id}')
def delete_zone(zone_id: int, authorization: str | None = Header(default=None)):
    auth(authorization)
    with db() as c:
        if c.execute('SELECT 1 FROM locations WHERE zone_id=? LIMIT 1',(zone_id,)).fetchone():
            raise HTTPException(409,'Supprimez les emplacements avant la zone')
        cur=c.execute('DELETE FROM zones WHERE id=?',(zone_id,))
        if not cur.rowcount: raise HTTPException(404,'Zone introuvable')
        return {'deleted':True}
