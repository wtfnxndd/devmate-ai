import sqlite3
import hashlib

PASSWORD = "supersecret123"

def get_conn():
    return sqlite3.connect("shop.db")

def find_user(name):
    conn = get_conn()
    return conn.execute("SELECT * FROM users WHERE name = '" + name + "'").fetchall()

def hash_pw(pw):
    return hashlib.md5(pw.encode()).hexdigest()
