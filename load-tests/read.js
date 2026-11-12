import http from 'k6/http';
import { check } from 'k6';
import { Counter } from 'k6/metrics';

const base = __ENV.BASE_URL || 'http://host.docker.internal:8081';
const expectedCache = __ENV.EXPECT_CACHE || '';
const cacheHits = new Counter('cache_hits');
const cacheMisses = new Counter('cache_misses');

export default function () {
  const response = http.get(`${base}/api/tests`, {
    headers: {
      ...(expectedCache === 'BYPASS' ? { 'X-Lab5-Cache-Bypass': '1' } : {}),
      ...(__ENV.LAB6_PRIMARY_ONLY === '1' ? { 'X-Lab6-Primary-Only': '1' } : {}),
    },
    tags: { business: 'read_catalog' },
  });
  const cacheStatus = response.headers['X-Cache'];
  if (cacheStatus === 'HIT') cacheHits.add(1);
  if (cacheStatus === 'MISS') cacheMisses.add(1);
  check(response, {
    'catalog returned 200': (r) => r.status === 200,
    'cache mode matches': () => !expectedCache || (expectedCache === 'HIT'
      ? cacheStatus === 'HIT' || cacheStatus === 'MISS'
      : cacheStatus === expectedCache),
  });
}
