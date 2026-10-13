
<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { RouterLink } from 'vue-router'
import { api } from '@/services/api'
import type {
  Test,
  AttemptStartResponse,
  AttemptResult,
} from '@/types/testing'

const tests = ref<Test[]>([])
const attempt = ref<AttemptStartResponse | null>(null)
const result = ref<AttemptResult | null>(null)
const answers = ref<Record<number, number>>({})
const saveErrors = ref<Record<number, string>>({})

const accessToken = ref('')
const loading = ref(false)
const busy = ref(false)
const savingAnswers = ref(0)
const error = ref('')

const publishedTests = computed(() =>
  tests.value.filter(test => test.isPublished),
)

const answeredCount = computed(() =>
  attempt.value
    ? attempt.value.questions.filter(
        question => answers.value[question.id] != null,
      ).length
    : 0,
)

const progressPercent = computed(() => {
  const total = attempt.value?.questions.length ?? 0
  return total > 0 ? (answeredCount.value / total) * 100 : 0
})

onMounted(loadTests)

async function loadTests() {
  loading.value = true
  error.value = ''

  try {
    tests.value = await api.getTests()
  } catch (e) {
    error.value = messageOf(e)
  } finally {
    loading.value = false
  }
}

async function startTest(test: Test) {
  busy.value = true
  error.value = ''

  try {
    const started = await api.startAttempt(test.id)

    attempt.value = started
    accessToken.value = started.accessToken
    result.value = null
    answers.value = {}
    saveErrors.value = {}

    for (const question of started.questions) {
      if (question.selectedOptionId != null) {
        answers.value[question.id] = question.selectedOptionId
      }
    }
  } catch (e) {
    error.value = messageOf(e)
  } finally {
    busy.value = false
  }
}

async function saveAnswer(
  questionId: number,
  selectedOptionId: number,
) {
  if (!attempt.value || !accessToken.value) return

  savingAnswers.value++
  error.value = ''

  try {
    await api.saveAttemptAnswer(
      attempt.value.attemptId,
      accessToken.value,
      questionId,
      selectedOptionId,
    )

    const updated = { ...saveErrors.value }
    delete updated[questionId]
    saveErrors.value = updated
  } catch (e) {
    saveErrors.value = {
      ...saveErrors.value,
      [questionId]: messageOf(e),
    }
  } finally {
    savingAnswers.value--
  }
}

async function submitTest() {
  if (!attempt.value || savingAnswers.value > 0) return

  if (Object.keys(saveErrors.value).length > 0) {
    error.value = 'Є відповіді, які не вдалося зберегти. Повтори їх збереження.'
    return
  }

  const confirmed = window.confirm(
    'Завершити тест? Після завершення змінити відповіді не можна.',
  )

  if (!confirmed) return

  busy.value = true
  error.value = ''

  try {
    result.value = await api.submitAttempt(
      attempt.value.attemptId,
      accessToken.value,
    )
  } catch (e) {
    error.value = messageOf(e)
  } finally {
    busy.value = false
  }
}

function backToTests() {
  attempt.value = null
  result.value = null
  answers.value = {}
  saveErrors.value = {}
  accessToken.value = ''
  error.value = ''
}

function messageOf(e: unknown): string {
  return e instanceof Error ? e.message : 'Сталася невідома помилка.'
}
</script>

<template>
  <main class="student-page">
    <header class="page-header">
      <div>
        <p class="eyebrow">ONLINE TESTING</p>
        <h1>Проходження тестів</h1>
        <p class="subtitle">
          Обери опублікований тест і перевір свої знання.
        </p>
      </div>
      <RouterLink to="/" class="back-link">
        Панель організатора
      </RouterLink>
    </header>

    <p v-if="error" class="error-message" role="alert">
      {{ error }}
    </p>

    <section v-if="result" class="result-card">
      <h2>Тест завершено!</h2>
      <p class="result-title">{{ result.testTitle }}</p>
      <p class="score">
        {{ result.score }} / {{ result.maxScore }} балів
      </p>
      <p>
        Відповіді надано: {{ result.answeredQuestions }}
        із {{ result.totalQuestions }}
      </p>
      <button class="primary-button" @click="backToTests">
        Повернутися до тестів
      </button>
    </section>

    <section v-else-if="attempt" class="test-card">
      <div class="test-heading">
        <div>
          <h2>{{ attempt.testTitle }}</h2>
          <p>{{ attempt.questions.length }} запитань</p>
        </div>
        <button class="secondary-button" @click="backToTests">
          До списку
        </button>
      </div>

      <form @submit.prevent="submitTest">

<div class="progress-section">
  <div class="progress-labels">
    <span>Прогрес проходження</span>
    <strong>{{ answeredCount }} із {{ attempt.questions.length }}</strong>
  </div>

  <div
    class="progress-track"
    role="progressbar"
    :aria-valuenow="answeredCount"
    :aria-valuemin="0"
    :aria-valuemax="attempt.questions.length"
    :aria-label="`Відповіді надано: ${answeredCount} із ${attempt.questions.length}`"
  >
    <div
      class="progress-fill"
      :style="{ width: `${progressPercent}%` }"
    ></div>
  </div>

  <p class="progress-hint">
    {{
      answeredCount === attempt.questions.length
        ? 'Усі запитання мають відповіді.'
        : `Залишилося відповісти: ${attempt.questions.length - answeredCount}`
    }}
  </p>
</div>

        <article
          v-for="(question, index) in attempt.questions"
          :key="question.id"
          class="question-card"
        >
          <h3>
            {{ index + 1 }}. {{ question.text }}
          </h3>
          <p class="points">{{ question.points }} балів</p>

          <label
            v-for="option in question.options"
            :key="option.id"
            class="option-row"
          >
            <input
              v-model.number="answers[question.id]"
              type="radio"
              :name="`question-${question.id}`"
              :value="option.id"
              :disabled="busy || savingAnswers > 0"
              @change="saveAnswer(question.id, option.id)"
            />
            <span>{{ option.text }}</span>
          </label>

          <div
            v-if="saveErrors[question.id]"
            class="save-error"
          >
            <p>{{ saveErrors[question.id] }}</p>
         
<button
  type="button"
  class="retry-button"
  :disabled="
    savingAnswers > 0 ||
    answers[question.id] == null
  "
  @click="saveAnswer(question.id, answers[question.id]!)"
>
  Повторити збереження
</button>

          </div>
        </article>

        <p v-if="savingAnswers > 0" class="saving-note">
          Зберігаємо відповідь…
        </p>

        <button
          class="primary-button submit-button"
          type="submit"
          :disabled="
            busy ||
            savingAnswers > 0 ||
            Object.keys(saveErrors).length > 0
          "
        >
          {{ busy ? 'Обробка…' : 'Завершити тест' }}
        </button>
      </form>
    </section>

    <section v-else class="tests-section">
      <p v-if="loading">Завантаження тестів…</p>

      <p v-else-if="publishedTests.length === 0">
        Наразі немає опублікованих тестів.
        Попроси організатора опублікувати тест.
      </p>

      <div v-else class="tests-grid">
        <article
          v-for="test in publishedTests"
          :key="test.id"
          class="test-card"
        >
          <h2>{{ test.title }}</h2>
          <p>{{ test.description || 'Опис відсутній.' }}</p>
          <button
            class="primary-button"
            :disabled="busy"
            @click="startTest(test)"
          >
            Почати тест
          </button>
        </article>
      </div>
    </section>
  </main>
</template>

<style scoped>
.student-page {
  width: min(100% - 32px, 900px);
  margin: 36px auto;
  color: #1f2937;
}

.page-header,
.test-heading {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 20px;
}

.page-header {
  margin-bottom: 28px;
}

.eyebrow {
  color: #64748b;
  font-size: 12px;
  font-weight: 700;
  letter-spacing: 2px;
}

h1 {
  margin: 8px 0;
  font-size: clamp(26px, 4vw, 36px);
}

.subtitle,
.test-card > p,
.test-heading p {
  color: #64748b;
}

.back-link {
  color: #2563eb;
  text-decoration: none;
}

.tests-grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(240px, 1fr));
  gap: 16px;
}

.test-card,
.question-card,
.result-card {
  padding: 22px;
  border: 1px solid #e2e8f0;
  border-radius: 14px;
  background: white;
  margin-bottom: 16px;
}

.test-card h2,
.question-card h3 {
  margin-top: 0;
}

.primary-button,
.secondary-button,
.retry-button {
  border: 0;
  border-radius: 8px;
  padding: 11px 16px;
  font: inherit;
  cursor: pointer;
}

.primary-button {
  background: #2563eb;
  color: white;
}

.secondary-button {
  background: #e2e8f0;
  color: #1f2937;
}

.retry-button {
  background: #ffedd5;
  color: #9a3412;
}

button:disabled {
  opacity: 0.55;
  cursor: not-allowed;
}

.option-row {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 12px;
  margin-top: 8px;
  border: 1px solid #e2e8f0;
  border-radius: 8px;
  cursor: pointer;
}

.option-row:has(input:checked) {
  border-color: #2563eb;
  background: #eff6ff;
}

.option-row input {
  width: 17px;
  height: 17px;
}

.points,
.saving-note {
  color: #64748b;
  font-size: 14px;
}

.submit-button {
  width: 100%;
  margin-top: 8px;
}

.error-message,
.save-error {
  padding: 12px;
  border-radius: 8px;
  background: #fef2f2;
  color: #b91c1c;
  overflow-wrap: anywhere;
}

.result-card {
  text-align: center;
}

.score {
  font-size: 32px;
  font-weight: 700;
}

.result-title {
  color: #64748b;
}

@media (max-width: 600px) {
  .page-header,
  .test-heading {
    align-items: flex-start;
    flex-direction: column;
  }
}

.progress-section {
  margin-bottom: 22px;
  padding: 18px;
  border: 1px solid #e2e8f0;
  border-radius: 12px;
  background: #f8fafc;
}

.progress-labels {
  display: flex;
  justify-content: space-between;
  align-items: center;
  gap: 12px;
  margin-bottom: 10px;
  font-size: 14px;
}

.progress-labels strong {
  color: #2563eb;
}

.progress-track {
  height: 10px;
  overflow: hidden;
  border-radius: 999px;
  background: #e2e8f0;
}

.progress-fill {
  height: 100%;
  border-radius: inherit;
  background: #2563eb;
  transition: width 0.25s ease;
}

.progress-hint {
  margin: 10px 0 0;
  color: #64748b;
  font-size: 13px;
}

</style>
