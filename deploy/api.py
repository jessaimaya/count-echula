#!/usr/bin/env python3
"""Play stats for the hosted build: stores events from web/analytics.js, serves /stats.

Runs next to Caddy in the Railway container (Caddy proxies /api/* and /stats* here).
Standard library only. Data: SQLite at $STATS_DB (a Railway volume, /data/stats.db).
The dashboard needs $STATS_PASSWORD (any user name, that password); without it /stats
is closed. No IP addresses are stored; they only feed an in-memory rate limit.
"""
import base64
import hmac
import json
import os
import re
import sqlite3
import threading
import time
from collections import defaultdict
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT = int(os.environ.get('STATS_PORT', '8081'))
DB = os.environ.get('STATS_DB', '/data/stats.db')
PASSWORD = os.environ.get('STATS_PASSWORD', '')
HERE = os.path.dirname(os.path.abspath(__file__))

TYPES = {'session_start', 'heartbeat', 'song_start', 'song_end', 'session_end'}
ID = re.compile(r'^[a-z0-9]{4,24}$')
MAX_BODY = 2048
RATE = 240  # events per IP per 10 minutes (a heartbeat is 1 per 15 s)

lock = threading.Lock()
hits = defaultdict(list)


def db():
    os.makedirs(os.path.dirname(DB) or '.', exist_ok=True)
    con = sqlite3.connect(DB, timeout=10)
    con.execute('''CREATE TABLE IF NOT EXISTS events (
        ts INTEGER NOT NULL, sid TEXT NOT NULL, vid TEXT, type TEXT NOT NULL,
        device TEXT, os TEXT, browser TEXT, data TEXT)''')
    con.execute('CREATE INDEX IF NOT EXISTS events_sid ON events (sid)')
    con.execute('CREATE INDEX IF NOT EXISTS events_ts ON events (ts)')
    return con


def agent(ua):
    """Coarse device / OS / browser from the user agent (nothing finer is kept)."""
    ua = ua or ''
    if 'iPad' in ua or ('Android' in ua and 'Mobile' not in ua):
        device = 'tablet'
    elif any(k in ua for k in ('iPhone', 'Android', 'Mobile')):
        device = 'phone'
    else:
        device = 'desktop'
    os_ = next((n for k, n in (('iPhone', 'iOS'), ('iPad', 'iOS'), ('Android', 'Android'),
                               ('Windows', 'Windows'), ('Mac OS X', 'macOS'), ('CrOS', 'ChromeOS'),
                               ('Linux', 'Linux')) if k in ua), 'other')
    browser = next((n for k, n in (('CriOS', 'Chrome'), ('FxiOS', 'Firefox'), ('EdgiOS', 'Edge'),
                                    ('Edg/', 'Edge'), ('OPR/', 'Opera'), ('SamsungBrowser', 'Samsung'),
                                    ('Firefox/', 'Firefox'), ('Chrome/', 'Chrome'), ('Safari/', 'Safari'))
                    if k in ua), 'other')
    return device, os_, browser


def limited(ip):
    now = time.time()
    with lock:
        q = [t for t in hits[ip] if now - t < 600]
        q.append(now)
        hits[ip] = q
        if len(hits) > 5000:  # forget idle addresses
            for k in [k for k, v in hits.items() if not v or now - v[-1] > 600]:
                del hits[k]
        return len(q) > RATE


def clean(data):
    """Keep short scalar fields only."""
    out = {}
    if isinstance(data, dict):
        for k, v in list(data.items())[:12]:
            if isinstance(k, str) and len(k) <= 12 and isinstance(v, (int, float, bool, str)):
                out[k] = v[:60] if isinstance(v, str) else v
    return out


def stats(tz_minutes):
    """Everything the dashboard shows, from one pass over the sessions."""
    con = db()
    rows = con.execute('SELECT ts, sid, vid, type, device, os, browser, data FROM events ORDER BY ts').fetchall()
    con.close()
    sessions = {}
    songs = []
    open_songs = {}
    for ts, sid, vid, typ, device, os_, browser, data in rows:
        d = json.loads(data or '{}')
        s = sessions.get(sid)
        if s is None:
            s = sessions[sid] = {'sid': sid, 'vid': vid, 'start': ts, 'end': ts, 'device': device,
                                 'os': os_, 'browser': browser, 'ref': '', 'songs': 0, 'play': 0,
                                 'best': 0, 'touch': None}
        s['end'] = max(s['end'], ts)
        if typ == 'session_start':
            s['ref'] = d.get('ref', '')
            s['touch'] = d.get('touch')
        elif typ == 'song_start':
            s['songs'] += 1
            open_songs[sid] = ts
        elif typ == 'song_end':
            secs = max(0, min(int(d.get('secs', 0) or 0), 600))
            s['play'] += secs
            s['best'] = max(s['best'], int(d.get('score', 0) or 0))
            open_songs.pop(sid, None)
            songs.append({'ts': ts, 'disc': d.get('disc', '?'), 'result': d.get('result', '?'),
                          'secs': secs, 'score': int(d.get('score', 0) or 0), 'grade': d.get('grade', '')})
    off = tz_minutes * 60000
    day = lambda ts: time.strftime('%Y-%m-%d', time.gmtime((ts + off) / 1000))
    daily = defaultdict(lambda: {'sessions': 0, 'players': set(), 'songs': 0, 'play': 0})
    for s in sessions.values():
        b = daily[day(s['start'])]
        b['sessions'] += 1
        b['players'].add(s['vid'] or s['sid'])
        b['songs'] += s['songs']
        b['play'] += s['play']
    per_vid = defaultdict(int)
    for s in sessions.values():
        per_vid[s['vid'] or s['sid']] += 1
    discs = defaultdict(lambda: {'plays': 0, 'done': 0, 'over': 0, 'quit': 0, 'left': 0,
                                 'secs': 0, 'best': 0, 'scores': [], 'grades': defaultdict(int)})
    for g in songs:
        x = discs[g['disc']]
        x['plays'] += 1
        x[g['result']] = x.get(g['result'], 0) + 1
        x['secs'] += g['secs']
        x['best'] = max(x['best'], g['score'])
        if g['result'] in ('done', 'over'):
            x['scores'].append(g['score'])
        if g['grade']:
            x['grades'][g['grade']] += 1
    count = lambda key: dict(sorted(_tally(sessions.values(), key).items(), key=lambda kv: -kv[1]))
    lengths = [(s['end'] - s['start']) / 1000 for s in sessions.values()]
    return {
        'generated': int(time.time() * 1000),
        'totals': {
            'players': len(per_vid),
            'returning': sum(1 for n in per_vid.values() if n > 1),
            'sessions': len(sessions),
            'played': sum(1 for s in sessions.values() if s['songs']),
            'songs': len(songs),
            'finished': sum(1 for g in songs if g['result'] == 'done'),
            'gameovers': sum(1 for g in songs if g['result'] == 'over'),
            'playSecs': sum(s['play'] for s in sessions.values()),
            'avgSession': sum(lengths) / len(lengths) if lengths else 0,
            'live': sum(1 for s in sessions.values() if time.time() * 1000 - s['end'] < 45000),
        },
        'daily': [{'day': k, 'sessions': v['sessions'], 'players': len(v['players']),
                   'songs': v['songs'], 'play': v['play']} for k, v in sorted(daily.items())],
        'discs': [{'disc': k, 'plays': v['plays'], 'done': v['done'], 'over': v['over'],
                   'quit': v['quit'] + v['left'], 'avgSecs': v['secs'] / v['plays'] if v['plays'] else 0,
                   'avgScore': sum(v['scores']) / len(v['scores']) if v['scores'] else 0,
                   'best': v['best'], 'grades': dict(v['grades'])}
                  for k, v in sorted(discs.items(), key=lambda kv: -kv[1]['plays'])],
        'devices': count('device'), 'os': count('os'), 'browsers': count('browser'),
        'referrers': {k: v for k, v in count('ref').items() if k},
        'recent': [{k: s[k] for k in ('start', 'end', 'device', 'os', 'browser', 'ref', 'songs', 'play', 'best')}
                   for s in sorted(sessions.values(), key=lambda s: -s['start'])[:40]],
    }


def _tally(items, key):
    t = defaultdict(int)
    for s in items:
        t[s[key] or ''] += 1
    return t


class Handler(BaseHTTPRequestHandler):
    server_version = 'echula-stats'

    def log_message(self, *args):
        pass

    def reply(self, code, body=b'', ctype='text/plain; charset=utf-8', extra=None):
        self.send_response(code)
        self.send_header('Content-Type', ctype)
        self.send_header('Cache-Control', 'no-store')
        for k, v in (extra or {}).items():
            self.send_header(k, v)
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def client_ip(self):
        return (self.headers.get('X-Forwarded-For') or self.client_address[0]).split(',')[0].strip()

    def do_POST(self):
        if self.path != '/api/event':
            return self.reply(404)
        n = int(self.headers.get('Content-Length') or 0)
        if n <= 0 or n > MAX_BODY:
            return self.reply(413)
        raw = self.rfile.read(n)
        if limited(self.client_ip()):
            return self.reply(429)
        try:
            ev = json.loads(raw)
            typ, sid, vid = ev.get('type'), ev.get('sid'), ev.get('vid')
            assert typ in TYPES and isinstance(sid, str) and ID.match(sid)
            if not (isinstance(vid, str) and ID.match(vid)):
                vid = None
        except Exception:
            return self.reply(400)
        device, os_, browser = agent(self.headers.get('User-Agent'))
        con = db()
        with con:
            con.execute('INSERT INTO events VALUES (?,?,?,?,?,?,?,?)',
                        (int(time.time() * 1000), sid, vid, typ, device, os_, browser,
                         json.dumps(clean(ev.get('data')))))
        con.close()
        self.reply(204)

    def authorized(self):
        if not PASSWORD:
            return False
        h = self.headers.get('Authorization', '')
        if not h.startswith('Basic '):
            return False
        try:
            _, _, given = base64.b64decode(h[6:]).decode().partition(':')
        except Exception:
            return False
        return hmac.compare_digest(given.encode(), PASSWORD.encode())

    def do_GET(self):
        path, _, query = self.path.partition('?')
        if path not in ('/stats', '/stats/', '/stats/data'):
            return self.reply(404)
        if not self.authorized():
            msg = b'Set STATS_PASSWORD to open the stats.' if not PASSWORD else b'Sign in to see the stats.'
            return self.reply(401, msg, extra={'WWW-Authenticate': 'Basic realm="Count Echula stats"'})
        if path == '/stats/data':
            m = re.search(r'tz=(-?\d+)', query)
            body = json.dumps(stats(int(m.group(1)) if m else 0)).encode()
            return self.reply(200, body, 'application/json')
        with open(os.path.join(HERE, 'stats.html'), 'rb') as f:
            self.reply(200, f.read(), 'text/html; charset=utf-8')


if __name__ == '__main__':
    db().close()
    print(f'stats api on :{PORT}, db {DB}', flush=True)
    ThreadingHTTPServer(('127.0.0.1', PORT), Handler).serve_forever()
