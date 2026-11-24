import http from 'k6/http';
import { check } from 'k6';

const base = __ENV.BASE_URL || 'http://host.docker.internal:8081';
const mode = __ENV.LAB7_MODE || 'read-local';
const strategy = __ENV.LAB7_STRATEGY || 'bucket';
const attemptBase = Number(__ENV.LAB7_ATTEMPT_BASE || '7000000');
const seedCount = Number(__ENV.LAB7_SEED_COUNT || '300');
const seedType = __ENV.LAB7_SEED_TYPE || 'lab7-seed';

export default function () {
  let response;
  if (mode === 'read-fanout') {
    response = http.get(`${base}/api/lab7/events/search?strategy=bucket&term=${seedType}&limit=50`);
    check(response, { 'fanout reached both shards': (r) =>
      r.status === 200 && r.json('shards').length === 2 });
  } else if (mode === 'read-local') {
    const index = (__VU + __ITER) % Math.max(1, Math.min(seedCount, 90));
    response = http.get(`${base}/api/lab7/events/local?studentId=hot-student&attemptId=${attemptBase + index}&strategy=${strategy}&term=${seedType}`);
    check(response, { 'local read reached one shard': (r) =>
      r.status === 200 && r.json('shards').length === 1 && r.json('items').length > 0 });
  } else if (mode === 'write-hot') {
    const hot = __ITER % 10 !== 0;
    const studentId = hot ? 'hot-student' : `student-${__VU % 40}`;
    const attemptId = attemptBase + 100000 + __VU * 1000000 + __ITER;
    response = http.post(`${base}/api/lab7/events`, JSON.stringify({
      studentId, attemptId, eventType: 'hot', payload: 'Lab7 hot shard', strategy,
    }), { headers: { 'Content-Type': 'application/json' } });
    check(response, { 'hot write created': (r) => r.status === 201 });
  } else {
    throw new Error(`Unknown LAB7_MODE: ${mode}`);
  }
}
