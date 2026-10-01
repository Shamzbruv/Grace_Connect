import { listResetObjects, parseResetObjectKeys, RESET_CONFIRMATION, validateResetRequest } from './platform_reset.ts';
import { presignR2Url } from './r2.ts';
const assert = (condition: boolean, message = 'Assertion failed') => { if (!condition) throw new Error(message); };
const config = { accountId: 'example', endpoint: 'https://example.r2.cloudflarestorage.com', bucket: 'reel-grace-videos', accessKeyId: 'example', secretAccessKey: 'example-test-only' };
const xml = (keys: string[], truncated = false) => `<ListBucketResult><EncodingType>url</EncodingType><KeyCount>${keys.length}</KeyCount><IsTruncated>${truncated}</IsTruncated>${keys.map(key => `<Contents><Key>${encodeURIComponent(key)}</Key></Contents>`).join('')}</ListBucketResult>`;

Deno.test('reset requires exact confirmation and a bounded nonempty password', () => {
  assert(validateResetRequest({ confirmation: RESET_CONFIRMATION, password: 'password' }));
  for (const body of [{}, { confirmation: RESET_CONFIRMATION }, { confirmation: RESET_CONFIRMATION.toLowerCase(), password: 'x' }, { confirmation: RESET_CONFIRMATION, password: '' }, { confirmation: RESET_CONFIRMATION, password: 'x'.repeat(1025) }]) assert(!validateResetRequest(body));
});
Deno.test('R2 listing decodes keys without confusing XML and rejects incomplete listings', () => {
  const keys = ['reels/user/video.mp4', 'odd & <name> + % 日本語.png'];
  assert(JSON.stringify(parseResetObjectKeys(xml(keys))) === JSON.stringify(keys));
  assert(parseResetObjectKeys(xml([])).length === 0);
  for (const body of ['', '<Error>Forbidden</Error>', '<ListBucketResult></ListBucketResult>', xml([], true), xml(['a']).replace('<KeyCount>1', '<KeyCount>0'), xml(['']), xml(['\0']), xml(Array(51).fill('a'))]) {
    let rejected = false;
    try { parseResetObjectKeys(body); } catch { rejected = true; }
    assert(rejected, 'invalid listing must not be interpreted as an empty bucket');
  }
});
Deno.test('bucket listing is signed only for a bounded GET at the bucket root', async () => {
  const url = new URL(await presignR2Url({ config, method: 'GET', key: '', listObjects: true, expiresInSeconds: 60 }));
  assert(url.pathname === '/reel-grace-videos/');
  assert(url.searchParams.get('max-keys') === '50');
  assert(url.searchParams.get('encoding-type') === 'url');
  assert(url.searchParams.get('list-type') === '2');
  assert(!!url.searchParams.get('X-Amz-Signature'));
  assert(!url.href.includes(config.secretAccessKey));
  for (const options of [{ method: 'PUT' as const, key: '' }, { method: 'GET' as const, key: 'object' }]) {
    let rejected = false;
    try { await presignR2Url({ config, ...options, listObjects: true, expiresInSeconds: 60 }); } catch { rejected = true; }
    assert(rejected);
  }
});
Deno.test('failed R2 requests cannot advance cleanup', async () => {
  let rejected = false;
  try { await listResetObjects(config, (() => Promise.resolve(new Response('<Error/>', { status: 403 }))) as typeof fetch); } catch { rejected = true; }
  assert(rejected);
  const keys = await listResetObjects(config, (() => Promise.resolve(new Response(xml(['a'])))) as typeof fetch);
  assert(keys[0] === 'a');
});
