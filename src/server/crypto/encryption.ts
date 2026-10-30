import crypto from 'node:crypto';

const ALGORITHM = 'aes-256-gcm';
const IV_LENGTH = 12; // 96 bits for GCM
const AUTH_TAG_LENGTH = 16; // 128 bits

/**
 * 確保 Master Key 符合 32 bytes (256 bits)
 */
function deriveKey(secret: string): Buffer {
  return crypto.createHash('sha256').update(secret).digest();
}

/**
 * 使用 AES-256-GCM 加密敏感 API Key
 */
export function encryptApiKey(apiKey: string, masterKey: string): { ciphertext: string; iv: string; authTag: string } {
  const iv = crypto.randomBytes(IV_LENGTH);
  const key = deriveKey(masterKey);
  const cipher = crypto.createCipheriv(ALGORITHM, key, iv, { authTagLength: AUTH_TAG_LENGTH });

  let encrypted = cipher.update(apiKey, 'utf8', 'hex');
  encrypted += cipher.final('hex');

  const authTag = cipher.getAuthTag().toString('hex');

  return {
    ciphertext: encrypted,
    iv: iv.toString('hex'),
    authTag,
  };
}

/**
 * 使用 AES-256-GCM 解密敏感 API Key，失敗立即拋出安全異常
 */
export function decryptApiKey(encryptedData: { ciphertext: string; iv: string; authTag: string }, masterKey: string): string {
  const key = deriveKey(masterKey);
  const iv = Buffer.from(encryptedData.iv, 'hex');
  const decipher = crypto.createDecipheriv(ALGORITHM, key, iv, { authTagLength: AUTH_TAG_LENGTH });

  decipher.setAuthTag(Buffer.from(encryptedData.authTag, 'hex'));

  let decrypted = decipher.update(encryptedData.ciphertext, 'hex', 'utf8');
  decrypted += decipher.final('utf8');

  return decrypted;
}

/**
 * 前端安全遮罩掩碼處理 (例如: AIzaSy...8x1k)
 */
export function maskApiKey(apiKey: string): string {
  if (!apiKey || apiKey.length <= 8) return '••••••••';
  const prefix = apiKey.slice(0, 6);
  const suffix = apiKey.slice(-4);
  return `${prefix}${'•'.repeat(Math.max(4, apiKey.length - 10))}${suffix}`;
}
