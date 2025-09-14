import { keccak256 } from 'viem';

// Minimal RLP encoder for [sender (bytes), nonce (empty array for 0)]
function rlpEncodeSenderNonce(senderHex: string, nonce: bigint) {
  const sender = Buffer.from(senderHex, 'hex');
  const senderEnc = encodeBytes(sender);
  const nonceEnc = encodeInteger(nonce);
  const payload = Buffer.concat([senderEnc, nonceEnc]);
  return Buffer.concat([Buffer.from([0xc0 + payload.length]), payload]);
}

function encodeBytes(buf: Buffer) {
  if (buf.length === 1 && buf[0] < 0x80) return buf;
  if (buf.length < 56) return Buffer.concat([Buffer.from([0x80 + buf.length]), buf]);
  // for our limited use-case sender is 20 bytes < 56
  throw new Error('unexpected long buffer in rlp encoder');
}

function encodeInteger(n: bigint) {
  if (n === 0n) return Buffer.from([0x80]);
  // encode big-endian minimal bytes
  let hex = n.toString(16);
  if (hex.length % 2 === 1) hex = '0' + hex;
  const buf = Buffer.from(hex, 'hex');
  if (buf.length === 1 && buf[0] < 0x80) return buf;
  if (buf.length < 56) return Buffer.concat([Buffer.from([0x80 + buf.length]), buf]);
  throw new Error('integer too large for this encoder');
}

// precompute factory address when EOA sends first tx (nonce = 0)
export function precomputeFactoryFromEOA(address: string, nonce: bigint = 0n) {
  // rlp encode [sender, nonce]
  const sender = address.toLowerCase().replace(/^0x/, '');
  const encoded = rlpEncodeSenderNonce(sender, nonce);
  const hash = keccak256(('0x' + encoded.toString('hex')) as `0x${string}` as any);
  return '0x' + hash.slice(-40);
}

export function computeCreate2Address(factory: string, saltHex: string, creationCodeHex: string) {
  const fac = factory.replace(/^0x/, '');
  const salt = saltHex.replace(/^0x/, '');
  const creationHash = keccak256((creationCodeHex.startsWith('0x') ? creationCodeHex : '0x' + creationCodeHex) as `0x${string}` as any);
  const concatenated = '0xff' + fac + salt + creationHash.replace(/^0x/, '');
  const full = keccak256(('0x' + concatenated) as `0x${string}` as any);
  return '0x' + full.slice(-40);
}
