import { createHmac, timingSafeEqual } from 'node:crypto';

// Per-device keys: RJ-<owner id base36>-<signature>. The signature is an HMAC over the
// device HWID and the owner, made with HWID_MASTER, so the bot verifies a key without
// storing anything and a key only works on the HWID it was issued for.
export const HWID_PATTERN = /^[0-9a-f]{16,64}$/i;
const KEY_PATTERN = /^RJ-([0-9a-z]{1,16})-([A-Z2-7]{20})$/;
const BASE32 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

function base32(buf, length) {
  let bits = 0, value = 0, out = '';
  for (const byte of buf) {
    value = (value << 8) | byte; bits += 8;
    while (bits >= 5) { out += BASE32[(value >>> (bits - 5)) & 31]; bits -= 5; }
    if (out.length >= length) break;
  }
  return out.slice(0, length);
}

function fromBase36(text) {
  let n = 0n;
  for (const c of text) n = n * 36n + BigInt(parseInt(c, 36));
  return n.toString();
}

const signature = (master, hwid, ownerId) => base32(
  createHmac('sha256', master).update(`rejoin-hwid-v1|${hwid.toLowerCase()}|${ownerId}`).digest(), 20);

export function makeKey(master, hwid, ownerId) {
  if (!HWID_PATTERN.test(hwid)) throw new Error('HWID tidak valid (hex 16–64 karakter, lihat Menu 9 di Termux).');
  return `RJ-${BigInt(ownerId).toString(36)}-${signature(master, hwid, ownerId)}`;
}

// Owner Discord ID the key was issued to, or null when it does not match this HWID.
export function verifyKey(master, hwid, key) {
  if (typeof hwid !== 'string' || !HWID_PATTERN.test(hwid)) return null;
  const m = KEY_PATTERN.exec(String(key || ''));
  if (!m) return null;
  const ownerId = fromBase36(m[1]);
  const expected = Buffer.from(signature(master, hwid, ownerId));
  const given = Buffer.from(m[2]);
  return expected.length === given.length && timingSafeEqual(expected, given) ? ownerId : null;
}

export const isHwidKey = token => typeof token === 'string' && token.startsWith('RJ-');
