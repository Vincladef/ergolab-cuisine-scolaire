import { neon } from '@neondatabase/serverless';
let cached = null;
export function db() {
  if (!process.env.DATABASE_URL) throw new Error('DATABASE_URL non configurée');
  cached ||= neon(process.env.DATABASE_URL);
  return cached;
}
