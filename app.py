from flask import Flask, render_template, request, redirect, url_for, session
import sqlite3
from datetime import datetime
import os
import string
import random

app = Flask(__name__)
app.secret_key = 'vnet_ledger_secure_key'

# --- SECURITY CONFIG ---
MASTER_PASSWORD = "nayagevapiyaHTTP2567" 

def is_logged_in():
    return session.get('authenticated') == True

def generate_slug(length=8):
    chars = string.ascii_lowercase + string.digits
    return ''.join(random.choice(chars) for _ in range(length))

def get_db_path():
    if 'selected_db' in session:
        return session['selected_db']
    return f"{datetime.now().strftime('%B_%Y')}.db"

def init_db(db_path):
    conn = sqlite3.connect(db_path)
    c = conn.cursor()
    # 7 Columns total
    c.execute('''CREATE TABLE IF NOT EXISTS entries 
                 (id INTEGER PRIMARY KEY AUTOINCREMENT, 
                  user TEXT, slug TEXT, date TEXT, 
                  description TEXT, amount REAL, type TEXT)''')
    conn.commit()
    conn.close()

def get_balance(db_path, username):
    if not os.path.exists(db_path): return 0
    conn = sqlite3.connect(db_path)
    c = conn.cursor()
    c.execute("SELECT amount, type FROM entries WHERE user = ?", (username,))
    rows = c.fetchall()
    conn.close()
    return sum(r[0] if r[1] == 'take' else -r[0] for r in rows)

# --- AUTH ROUTES ---

@app.route('/login', methods=['GET', 'POST'])
def login():
    if request.method == 'POST':
        if request.form.get('password') == MASTER_PASSWORD:
            session['authenticated'] = True
            return redirect(url_for('select_user'))
        return "Invalid Password. <a href='/login'>Try again</a>", 401
    return render_template('login.html')

@app.route('/logout')
def logout():
    session.clear()
    return redirect(url_for('login'))

# --- ADMIN ROUTES ---

@app.route('/')
def select_user():
    if not is_logged_in(): return redirect(url_for('login'))
    db_path = get_db_path()
    init_db(db_path)
    conn = sqlite3.connect(db_path)
    c = conn.cursor()
    c.execute("SELECT DISTINCT user FROM entries")
    users = [row[0] for row in c.fetchall()]
    conn.close()
    display_month = db_path.replace('.db', '').replace('_', ' ')
    return render_template('select.html', users=users, current_month=display_month)

@app.route('/user/<username>')
def index(username):
    if not is_logged_in(): return redirect(url_for('login'))
    db_path = get_db_path()
    conn = sqlite3.connect(db_path)
    c = conn.cursor()
    c.execute("SELECT * FROM entries WHERE user = ? ORDER BY date ASC, id ASC", (username,))
    rows = c.fetchall()
    balance = get_balance(db_path, username)
    conn.close()
    return render_template('index.html', rows=rows, balance=round(balance, 2), username=username)

@app.route('/add_user', methods=['POST'])
def add_user():
    if not is_logged_in(): return redirect(url_for('login'))
    new_user = request.form.get('new_username').strip()
    if new_user:
        db_path = get_db_path()
        new_slug = generate_slug()
        conn = sqlite3.connect(db_path)
        c = conn.cursor()
        c.execute("INSERT INTO entries (user, slug, date, description, amount, type) VALUES (?, ?, ?, ?, ?, ?)",
                  (new_user, new_slug, datetime.now().strftime("%m/%d"), "Account Opened", 0, "take"))
        conn.commit()
        conn.close()
        return redirect(url_for('index', username=new_user))
    return redirect(url_for('select_user'))

@app.route('/add/<username>', methods=['POST'])
def add_entry(username):
    if not is_logged_in(): return redirect(url_for('login'))
    db_path = get_db_path()
    conn = sqlite3.connect(db_path)
    c = conn.cursor()
    c.execute("SELECT slug FROM entries WHERE user = ? LIMIT 1", (username,))
    slug = c.fetchone()[0]
    description = request.form['description']
    amount = float(request.form['amount'])
    trans_type = request.form['type']
    date_str = request.form.get('custom_date') or datetime.now().strftime("%m/%d")
    c.execute("INSERT INTO entries (user, slug, date, description, amount, type) VALUES (?, ?, ?, ?, ?, ?)",
              (username, slug, date_str, description, amount, trans_type))
    conn.commit()
    conn.close()
    return redirect(url_for('index', username=username))

@app.route('/delete_entry/<username>/<int:entry_id>')
def delete_entry(username, entry_id):
    if not is_logged_in(): return redirect(url_for('login'))
    db_path = get_db_path()
    conn = sqlite3.connect(db_path)
    c = conn.cursor()
    c.execute("DELETE FROM entries WHERE id = ?", (entry_id,))
    conn.commit()
    conn.close()
    return redirect(url_for('index', username=username))

@app.route('/admin')
def admin():
    if not is_logged_in(): return redirect(url_for('login'))
    db_path = get_db_path()
    conn = sqlite3.connect(db_path)
    c = conn.cursor()
    c.execute("SELECT user, slug FROM entries GROUP BY user")
    rows = c.fetchall()
    user_data = []
    grand_total = 0
    for r in rows:
        bal = get_balance(db_path, r[0])
        user_data.append({'name': r[0], 'slug': r[1], 'balance': round(bal, 2)})
        grand_total += bal
    conn.close()
    return render_template('admin.html', users=user_data, grand_total=round(grand_total, 2), month=db_path.replace('.db',''))

@app.route('/delete_user/<username>')
def delete_user(username):
    if not is_logged_in(): return redirect(url_for('login'))
    db_path = get_db_path()
    conn = sqlite3.connect(db_path)
    c = conn.cursor()
    c.execute("DELETE FROM entries WHERE user = ?", (username,))
    conn.commit()
    conn.close()
    return redirect(url_for('admin'))

@app.route('/new_month', methods=['POST'])
def start_new_month():
    if not is_logged_in(): return redirect(url_for('login'))
    current_db = get_db_path()
    target_month = request.form.get('target_month').strip()
    next_db = f"{target_month}.db"
    if os.path.exists(next_db): return "Month exists!", 400
    init_db(next_db)
    conn_curr = sqlite3.connect(current_db)
    c_curr = conn_curr.cursor()
    c_curr.execute("SELECT DISTINCT user, slug FROM entries")
    users_info = c_curr.fetchall()
    conn_curr.close()
    conn_next = sqlite3.connect(next_db)
    c_next = conn_next.cursor()
    for user, slug in users_info:
        prev_bal = get_balance(current_db, user)
        etype = 'take' if prev_bal >= 0 else 'give'
        c_next.execute("INSERT INTO entries (user, slug, date, description, amount, type) VALUES (?, ?, ?, ?, ?, ?)",
                       (user, slug, "", "Previous Month Balance", abs(prev_bal), etype))
    conn_next.commit()
    conn_next.close()
    session['selected_db'] = next_db
    return redirect(url_for('select_user'))

@app.route('/history')
def history():
    if not is_logged_in(): return redirect(url_for('login'))
    files = [f for f in os.listdir('.') if f.endswith('.db')]
    return render_template('history.html', files=files)

@app.route('/set_month/<filename>')
def set_month(filename):
    if not is_logged_in(): return redirect(url_for('login'))
    session['selected_db'] = filename
    return redirect(url_for('select_user'))

# --- PUBLIC ROUTE ---

@app.route('/view/<slug>')
def user_view(slug):
    db_path = get_db_path()
    conn = sqlite3.connect(db_path)
    c = conn.cursor()
    c.execute("SELECT user FROM entries WHERE slug = ? LIMIT 1", (slug,))
    res = c.fetchone()
    if not res: return "Invalid Link", 404
    username = res[0]
    c.execute("SELECT * FROM entries WHERE user = ? ORDER BY date ASC, id ASC", (username,))
    rows = c.fetchall()
    balance = get_balance(db_path, username)
    conn.close()
    return render_template('user_view.html', rows=rows, balance=round(balance, 2), username=username)

if __name__ == '__main__':
    # Using 8888 because 8080 and 5000 are busy
    app.run(debug=False, host='0.0.0.0', port=8888)