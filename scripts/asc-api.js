#!/usr/bin/env node
// Minimal App Store Connect API client (ES256 JWT + fetch), so build/signing
// automation never needs Xcode's account UI.
//
//   node scripts/asc-api.js GET "/v1/builds?limit=5"
//   node scripts/asc-api.js POST /v1/profiles body.json
//
// Reads ASC_KEY_ID, ASC_ISSUER and ASC_KEY_PATH (defaults to the team key in
// ~/.appstoreconnect/private_keys). Prints "HTTP <status>" then the JSON body.
const fs = require('fs');
const os = require('os');
const crypto = require('crypto');

const KEY_ID = process.env.ASC_KEY_ID || '7325UTJ2UZ';
const ISSUER = process.env.ASC_ISSUER || '425dc43b-2d68-4902-8a14-6935a90efa9a';
const KEY_PATH = (process.env.ASC_KEY_PATH || `~/.appstoreconnect/private_keys/AuthKey_${KEY_ID}.p8`)
  .replace(/^~/, os.homedir());

const b64 = (value) => Buffer.from(typeof value === 'string' ? value : JSON.stringify(value)).toString('base64url');

function token() {
  const now = Math.floor(Date.now() / 1000);
  const header = b64({ alg: 'ES256', kid: KEY_ID, typ: 'JWT' });
  const payload = b64({ iss: ISSUER, iat: now, exp: now + 900, aud: 'appstoreconnect-v1' });
  const key = fs.readFileSync(KEY_PATH, 'utf8');
  const signature = crypto.sign('sha256', Buffer.from(`${header}.${payload}`), { key, dsaEncoding: 'ieee-p1363' });
  return `${header}.${payload}.${signature.toString('base64url')}`;
}

async function main() {
  const [method, path, bodyPath] = process.argv.slice(2);
  if (!method || !path) {
    console.error('usage: asc-api.js <METHOD> <path> [bodyFile]');
    process.exit(2);
  }
  const options = { method, headers: { Authorization: `Bearer ${token()}` } };
  if (bodyPath) {
    options.headers['Content-Type'] = 'application/json';
    options.body = fs.readFileSync(bodyPath, 'utf8');
  }
  const response = await fetch(`https://api.appstoreconnect.apple.com${path}`, options);
  console.log('HTTP', response.status);
  const text = await response.text();
  try { console.log(JSON.stringify(JSON.parse(text), null, 2)); } catch { console.log(text); }
  process.exit(response.ok ? 0 : 1);
}

main();
