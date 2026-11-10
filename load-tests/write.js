import http from 'k6/http';
import { check } from 'k6';

const base = __ENV.BASE_URL || 'http://host.docker.internal:8081';
const json = { headers: { 'Content-Type': 'application/json' } };

export function setup() {
  const response = http.post(`${base}/api/tests`,
    JSON.stringify({ title: `Lab5-write-${Date.now()}`, description: 'Temporary load fixture' }), json);
  if (response.status !== 201) throw new Error(`Fixture creation failed: ${response.status}`);
  return { testId: response.json('id') };
}

export default function (data) {
  const created = http.post(`${base}/api/tests/${data.testId}/questions`,
    JSON.stringify({ text: `Load question ${__VU}-${__ITER}`, order: __VU, points: 1 }), json);
  if (!check(created, { 'question created': (r) => r.status === 201 })) return;
  const id = created.json('id');
  const deleted = http.del(`${base}/api/questions/${id}`);
  check(deleted, { 'question deleted': (r) => r.status === 204 });
}

export function teardown(data) {
  const response = http.del(`${base}/api/tests/${data.testId}`);
  if (response.status !== 204) throw new Error(`Fixture cleanup failed: ${response.status}`);
}
