import http from 'k6/http';
import { check } from 'k6';

const base = __ENV.BASE_URL || 'http://host.docker.internal:8081';
const mode = __ENV.MODE || 'protected';
const id = __ENV.KEY_ID || 'popular-product';
const expectedNotFound = http.expectedStatuses(404);

export default function () {
  const response = mode === 'penetration'
    ? http.get(`${base}/api/lab8/entity/9999999`, { responseCallback: expectedNotFound })
    : mode.startsWith('avalanche-')
      ? http.get(`${base}/api/lab8/avalanche?jitter=${mode === 'avalanche-jitter'}&ttlSeconds=5`)
      : http.get(`${base}/api/lab8/resource/${id}?protectedMode=${mode === 'protected'}&delayMs=300`);
  if (mode === 'penetration') {
    check(response, { 'missing entity returns 404': (r) => r.status === 404 });
  } else if (mode.startsWith('avalanche-')) {
    check(response, { 'avalanche group returned 200': (r) => r.status === 200 });
  } else {
    check(response, { 'resource returned 200': (r) => r.status === 200 });
  }
}
