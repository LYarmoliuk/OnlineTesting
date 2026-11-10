import http from 'k6/http';
import { check } from 'k6';

const base = __ENV.BASE_URL || 'http://host.docker.internal:8081';
const testId = Number(__ENV.TEST_ID);
const questionId = Number(__ENV.QUESTION_ID);
const optionId = Number(__ENV.OPTION_ID);
if (!testId || !questionId || !optionId) throw new Error('TEST_ID, QUESTION_ID and OPTION_ID are required');

export default function () {
  const catalog = http.get(`${base}/api/tests`);
  if (!check(catalog, { 'catalog returned 200': (r) => r.status === 200 })) return;

  const started = http.post(`${base}/api/tests/${testId}/attempts`);
  if (!check(started, { 'attempt started': (r) => r.status === 201 })) return;
  const attemptId = started.json('attemptId');
  const token = started.json('accessToken');
  const headers = { headers: { 'X-Attempt-Token': token, 'Content-Type': 'application/json' } };

  const read = http.get(`${base}/api/attempts/${attemptId}`, headers);
  if (!check(read, { 'attempt read': (r) => r.status === 200 })) return;

  const answer = http.put(`${base}/api/attempts/${attemptId}/answers`,
    JSON.stringify({ questionId, selectedOptionId: optionId }), headers);
  if (!check(answer, { 'answer saved': (r) => r.status === 204 })) return;

  const submitted = http.post(`${base}/api/attempts/${attemptId}/submit`, null, headers);
  if (!check(submitted, {
    'attempt completed': (r) => r.status === 200,
    'score calculated': (r) => r.status === 200 && r.json('score') === 1,
  })) return;

  const result = http.get(`${base}/api/attempts/${attemptId}/result`, headers);
  check(result, { 'saved result returned': (r) => r.status === 200 && r.json('score') === 1 });
}
