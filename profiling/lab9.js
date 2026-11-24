import http from 'k6/http';
import { check } from 'k6';

const base = __ENV.BASE_URL || 'http://host.docker.internal:8081';
const attemptId = __ENV.ATTEMPT_ID;
const token = __ENV.ATTEMPT_TOKEN;
const mode = __ENV.QUERY_MODE || 'single';
const vus = Number(__ENV.VUS || '10');
const duration = __ENV.DURATION || '30s';

export const options = {
  vus,
  duration,
  thresholds: { http_req_failed: ['rate<0.01'] },
  tags: { lab: 'lab9', query_mode: mode },
};

export default function () {
  const response = http.get(`${base}/api/attempts/${attemptId}?splitQuery=${mode === 'split'}`, {
    headers: { 'X-Attempt-Token': token },
    tags: { name: `attempt-${mode}` },
  });
  check(response, {
    'attempt read returns 200': (r) => r.status === 200,
    'response has expected query mode': (r) => r.headers['X-Lab9-Query-Mode'] === mode,
    'response contains fixture questions': (r) => r.status === 200 && r.json('questions').length > 0,
  });
}
