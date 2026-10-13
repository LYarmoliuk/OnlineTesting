
import http from 'k6/http';
import { check, sleep } from 'k6';
import { Trend, Rate } from 'k6/metrics';

const BASE = __ENV.API_URL || 'http://localhost:8080';
const TEST_ID = Number(__ENV.TEST_ID);

if (!TEST_ID) {
  throw new Error('Передай TEST_ID опублікованого тесту з 40 питаннями');
}

const answerLatency = new Trend('answer_latency', true);
const failures = new Rate('operation_failures');

export const options = {
  scenarios: {
    students: {
      executor: 'per-vu-iterations',
      vus: 500,
      iterations: 1,
      maxDuration: '15m',
    },
  },
  thresholds: {
    operation_failures: ['rate<0.05'],
  },
};

function requestOk(response, expectedStatus) {
  const ok = response.status === expectedStatus;
  failures.add(!ok);
  return ok;
}

export default function () {
  const start = http.post(`${BASE}/api/tests/${TEST_ID}/attempts`, null);

  if (!requestOk(start, 201)) return;

  const attempt = start.json();
console.log('START RESPONSE:', JSON.stringify(attempt));
  const attemptId = attempt.attemptId ?? attempt.id;
  const token = attempt.accessToken;

  if (!attemptId || !token) {
    failures.add(true);
    return;
  }

  const headers = {
    'Content-Type': 'application/json',
    'X-Attempt-Token': token,
  };

  const details = http.get(`${BASE}/api/attempts/${attemptId}`, { headers });
console.log('DETAILS RESPONSE:', details.body);
  if (!requestOk(details, 200)) return;

  const questions = details.json().questions;

  if (!Array.isArray(questions) || questions.length !== 40) {
    failures.add(true);
    return;
  }

  for (const question of questions) {
    const option = (question.answerOptions ?? question.options ?? [])[0];

    if (!option) {
      failures.add(true);
      return;
    }

    const response = http.put(
      `${BASE}/api/attempts/${attemptId}/answers`,
      JSON.stringify({
        questionId: question.id,
        selectedOptionId: option.id,
      }),
      { headers }
    );

    answerLatency.add(response.timings.duration);

    if (!requestOk(response, 200)) return;
  }

  const submitted = http.post(
    `${BASE}/api/attempts/${attemptId}/submit`,
    null,
    { headers }
  );

  if (!requestOk(submitted, 200)) return;

  const result = http.get(
    `${BASE}/api/attempts/${attemptId}/result`,
    { headers }
  );

  check(result, {
    'result returned 200': (r) => r.status === 200,
  });

  requestOk(result, 200);
}
