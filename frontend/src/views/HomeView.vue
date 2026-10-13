
<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { api } from '@/services/api'
import type {
  Test,
  Question,
  AnswerOption,
} from '@/types/testing'

const tests = ref<Test[]>([])
const questions = ref<Question[]>([])
const options = ref<AnswerOption[]>([])
const selectedTest = ref<Test | null>(null)
const selectedQuestion = ref<Question | null>(null)
const loading = ref(false)
const error = ref('')
const notice = ref('')
const editingTestId = ref<number | null>(null)
const editingQuestionId = ref<number | null>(null)
const editingOptionId = ref<number | null>(null)

const testForm = ref({ title: '', description: '', isPublished: false })
const questionForm = ref({ text: '', order: 1, points: 1 })
const optionForm = ref({ text: '', isCorrect: false })

const publishedCount = computed(() =>
  tests.value.filter((test) => test.isPublished).length,
)

function showError(e: unknown) {
  error.value = e instanceof Error ? e.message : 'Сталася невідома помилка'
  notice.value = ''
}

function resetTestForm() {
  editingTestId.value = null
  testForm.value = { title: '', description: '', isPublished: false }
}

function resetQuestionForm() {
  editingQuestionId.value = null
  questionForm.value = {
    text: '',
    order: questions.value.length + 1,
    points: 1,
  }
}

function resetOptionForm() {
  editingOptionId.value = null
  optionForm.value = { text: '', isCorrect: false }
}

async function loadTests() {
  loading.value = true
  error.value = ''
  try {
    tests.value = await api.getTests()
  } catch (e) {
    showError(e)
  } finally {
    loading.value = false
  }
}

async function saveTest() {
  error.value = ''
  try {
    const title = testForm.value.title.trim()
    if (!title) throw new Error('Вкажи назву тесту.')

    if (editingTestId.value !== null) {
      await api.updateTest(editingTestId.value, {
        title,
        description: testForm.value.description.trim(),
        isPublished: testForm.value.isPublished,
      })
      notice.value = 'Тест оновлено.'
    } else {
      await api.createTest({
        title,
        description: testForm.value.description.trim(),
      })
      notice.value = 'Тест створено.'
    }

    resetTestForm()
    await loadTests()
  } catch (e) {
    showError(e)
  }
}

function editTest(test: Test) {
  editingTestId.value = test.id
  testForm.value = {
    title: test.title,
    description: test.description,
    isPublished: test.isPublished,
  }
  error.value = ''
  notice.value = ''
}

async function deleteTest(test: Test) {
  if (!confirm(`Видалити тест «${test.title}» разом із запитаннями?`)) return
  try {
    await api.deleteTest(test.id)
    if (selectedTest.value?.id === test.id) {
      selectedTest.value = null
      selectedQuestion.value = null
      questions.value = []
      options.value = []
    }
    notice.value = 'Тест видалено.'
    await loadTests()
  } catch (e) {
    showError(e)
  }
}

async function selectTest(test: Test) {
  selectedTest.value = test
  selectedQuestion.value = null
  options.value = []
  resetQuestionForm()
  resetOptionForm()
  error.value = ''
  try {
    questions.value = await api.getQuestions(test.id)
  } catch (e) {
    showError(e)
  }
}

async function saveQuestion() {
  if (!selectedTest.value) return
  try {
    const text = questionForm.value.text.trim()
    if (!text) throw new Error('Введи текст запитання.')
    const data = {
      text,
      order: questionForm.value.order,
      points: questionForm.value.points,
    }

    if (editingQuestionId.value !== null) {
      await api.updateQuestion(editingQuestionId.value, data)
      notice.value = 'Запитання оновлено.'
    } else {
      await api.createQuestion(selectedTest.value.id, data)
      notice.value = 'Запитання створено.'
    }

    resetQuestionForm()
    questions.value = await api.getQuestions(selectedTest.value.id)
  } catch (e) {
    showError(e)
  }
}

function editQuestion(question: Question) {
  selectedQuestion.value = question
  editingQuestionId.value = question.id
  questionForm.value = {
    text: question.text,
    order: question.order,
    points: question.points,
  }
  options.value = []
  void loadOptions(question.id)
  error.value = ''
  notice.value = ''
}

async function chooseQuestion(question: Question) {
  selectedQuestion.value = question
  resetOptionForm()
  await loadOptions(question.id)
}

async function loadOptions(questionId: number) {
  try {
    options.value = await api.getOptions(questionId)
  } catch (e) {
    showError(e)
  }
}

async function deleteQuestion(question: Question) {
  if (!confirm('Видалити це запитання разом із варіантами?')) return
  try {
    await api.deleteQuestion(question.id)
    if (selectedQuestion.value?.id === question.id) {
      selectedQuestion.value = null
      options.value = []
      resetOptionForm()
    }
    questions.value = await api.getQuestions(question.testId)
    resetQuestionForm()
    notice.value = 'Запитання видалено.'
  } catch (e) {
    showError(e)
  }
}

async function saveOption() {
  if (!selectedQuestion.value) return
  try {
    const text = optionForm.value.text.trim()
    if (!text) throw new Error('Введи текст варіанта відповіді.')
    const data = { text, isCorrect: optionForm.value.isCorrect }

    if (editingOptionId.value !== null) {
      await api.updateOption(editingOptionId.value, data)
      notice.value = 'Варіант оновлено.'
    } else {
      await api.createOption(selectedQuestion.value.id, data)
      notice.value = 'Варіант додано.'
    }

    resetOptionForm()
    await loadOptions(selectedQuestion.value.id)
  } catch (e) {
    showError(e)
  }
}

function editOption(option: AnswerOption) {
  editingOptionId.value = option.id
  optionForm.value = { text: option.text, isCorrect: option.isCorrect }
  error.value = ''
  notice.value = ''
}

async function deleteOption(option: AnswerOption) {
  if (!confirm('Видалити цей варіант відповіді?')) return
  try {
    await api.deleteOption(option.id)
    await loadOptions(option.questionId)
    notice.value = 'Варіант видалено.'
  } catch (e) {
    showError(e)
  }
}

onMounted(loadTests)
</script>

<template>
  <main class="dashboard">
    <header class="topbar">
      <a class="brand" href="/">
        <span class="brand-mark">OT</span>
        <span>Online<span class="brand-light">Testing</span></span>
      </a>
      <span class="topbar-label">Панель організатора</span>
    </header>

    <section class="welcome">
      <div>
        <p class="eyebrow">КЕРУВАННЯ НАВЧАННЯМ</p>
        <h1>Твоя тестова <span>лабораторія.</span></h1>
        <p class="subtitle">Створюй тести, додавай запитання та налаштовуй варіанти відповідей.</p>
      </div>
      <div class="welcome-icon">✳</div>
    </section>

    <section class="stats">
      <article class="stat-card">
        <span class="stat-label">Усього тестів</span>
        <strong>{{ tests.length }}</strong>
        <span class="stat-foot">У базі даних</span>
      </article>
      <article class="stat-card">
        <span class="stat-label">Опубліковано</span>
        <strong>{{ publishedCount }}</strong>
        <span class="stat-foot">Із загальної кількості</span>
      </article>
      <article class="stat-card">
        <span class="stat-label">Запитань у тесті</span>
        <strong>{{ questions.length }}</strong>
        <span class="stat-foot">{{ selectedTest?.title || 'Обери тест нижче' }}</span>
      </article>
    </section>

    <p v-if="error" class="message error-message">{{ error }}</p>
    <p v-if="notice" class="message success-message">{{ notice }}</p>

    <section class="workspace">
      <aside class="panel test-panel">
        <div class="panel-heading">
          <div>
            <p class="eyebrow">БІБЛІОТЕКА</p>
            <h2>Мої тести</h2>
          </div>
          <button class="icon-button" title="Оновити список" @click="loadTests">↻</button>
        </div>

        <p v-if="loading" class="empty-state">Завантаження тестів…</p>
        <p v-else-if="!tests.length" class="empty-state">Поки немає тестів. Створи перший праворуч.</p>

        <article
          v-for="test in tests"
          :key="test.id"
          class="test-item"
          :class="{ active: selectedTest?.id === test.id }"
        >
          <button class="test-select" @click="selectTest(test)">
            <span class="test-symbol">▤</span>
            <span class="test-info">
              <strong>{{ test.title }}</strong>
              <small>{{ test.description || 'Без опису' }}</small>
              <span class="status" :class="test.isPublished ? 'published' : 'draft'">
                {{ test.isPublished ? 'Опубліковано' : 'Чернетка' }}
              </span>
            </span>
          </button>
          <div class="item-actions">
            <button class="text-button" @click="editTest(test)">Змінити</button>
            <button class="text-button danger" @click="deleteTest(test)">Видалити</button>
          </div>
        </article>
      </aside>

      <section class="panel editor-panel">
        <p class="eyebrow">КОНСТРУКТОР</p>
        <h2>{{ editingTestId ? 'Редагування тесту' : 'Створити тест' }}</h2>

        <form class="form-stack" @submit.prevent="saveTest">
          <label>
            Назва тесту
            <input v-model="testForm.title" required maxlength="150" placeholder="Наприклад, Основи програмування" />
          </label>
          <label>
            Опис
            <textarea v-model="testForm.description" maxlength="2000" rows="3" placeholder="Короткий опис тесту…"></textarea>
          </label>
          <label v-if="editingTestId" class="checkbox-label">
            <input v-model="testForm.isPublished" type="checkbox" />
            Опублікувати тест
          </label>
          <div class="form-actions">
            <button class="primary-button" type="submit">
              {{ editingTestId ? 'Зберегти зміни' : '+ Створити тест' }}
            </button>
            <button v-if="editingTestId" class="secondary-button" type="button" @click="resetTestForm">
              Скасувати
            </button>
          </div>
        </form>

        <div class="section-divider"></div>

        <template v-if="selectedTest">
          <p class="eyebrow">ТЕСТ #{{ selectedTest.id }}</p>
          <h2>Запитання</h2>
          <p class="subtitle compact">{{ selectedTest.title }}</p>

          <div v-if="!questions.length" class="empty-state">Додай перше запитання до цього тесту.</div>

          <article v-for="question in questions" :key="question.id" class="question-item">
            <button class="question-select" @click="chooseQuestion(question)">
              <span class="question-number">{{ question.order }}</span>
              <span class="question-copy">
                <strong>{{ question.text }}</strong>
                <small>{{ question.points }} б. · {{ question.id === selectedQuestion?.id ? 'Обрано' : 'Натисни для варіантів' }}</small>
              </span>
            </button>
            <div class="item-actions">
              <button class="text-button" @click="editQuestion(question)">Змінити</button>
              <button class="text-button danger" @click="deleteQuestion(question)">Видалити</button>
            </div>
          </article>

          <h3>{{ editingQuestionId ? 'Редагувати запитання' : 'Нове запитання' }}</h3>
          <form class="form-stack" @submit.prevent="saveQuestion">
            <label>
              Текст запитання
              <textarea v-model="questionForm.text" required maxlength="2000" rows="3" placeholder="Введи запитання…"></textarea>
            </label>
            <div class="form-row">
              <label>
                Порядок
                <input v-model.number="questionForm.order" type="number" min="0" required />
              </label>
              <label>
                Бали
                <input v-model.number="questionForm.points" type="number" min="1" required />
              </label>
            </div>
            <div class="form-actions">
              <button class="primary-button" type="submit">
                {{ editingQuestionId ? 'Зберегти запитання' : '+ Додати запитання' }}
              </button>
              <button v-if="editingQuestionId" class="secondary-button" type="button" @click="resetQuestionForm">
                Скасувати
              </button>
            </div>
          </form>

          <template v-if="selectedQuestion">
            <div class="section-divider"></div>
            <p class="eyebrow">ЗАПИТАННЯ #{{ selectedQuestion.id }}</p>
            <h2>Варіанти відповідей</h2>

            <article v-for="option in options" :key="option.id" class="option-item">
              <span class="option-indicator" :class="{ correct: option.isCorrect }">
                {{ option.isCorrect ? '✓' : '○' }}
              </span>
              <span class="option-text">{{ option.text }}</span>
              <div class="item-actions">
                <button class="text-button" @click="editOption(option)">Змінити</button>
                <button class="text-button danger" @click="deleteOption(option)">Видалити</button>
              </div>
            </article>

            <p v-if="!options.length" class="empty-state">Для цього запитання ще немає варіантів.</p>

            <h3>{{ editingOptionId ? 'Редагувати варіант' : 'Додати варіант відповіді' }}</h3>
            <form class="form-stack" @submit.prevent="saveOption">
              <label>
                Текст відповіді
                <input v-model="optionForm.text" required maxlength="1000" placeholder="Введи варіант…" />
              </label>
              <label class="checkbox-label">
                <input v-model="optionForm.isCorrect" type="checkbox" />
                Це правильна відповідь
              </label>
              <div class="form-actions">
                <button class="primary-button" type="submit">
                  {{ editingOptionId ? 'Зберегти варіант' : '+ Додати варіант' }}
                </button>
                <button v-if="editingOptionId" class="secondary-button" type="button" @click="resetOptionForm">
                  Скасувати
                </button>
              </div>
            </form>
          </template>
          <p v-else class="hint">Обери запитання, щоб переглянути й редагувати його варіанти відповідей.</p>
        </template>

        <div v-else class="selection-prompt">
          <span class="prompt-icon">↖</span>
          <h3>Почни з тесту</h3>
          <p>Створи новий тест або обери наявний зі списку, щоб додавати запитання та відповіді.</p>
        </div>
      </section>
    </section>

    <footer>OnlineTesting · Панель керування тестами</footer>
  </main>
</template>
