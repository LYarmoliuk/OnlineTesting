
import type {
  Test,
  TestInput,
  Question,
  QuestionInput,
  AnswerOption,
  AnswerOptionInput,
  AttemptStartResponse,
  AttemptResult,
} from '@/types/testing'

const API_URL = import.meta.env.VITE_API_URL || ''

async function request<T>(path: string, options: RequestInit = {}): Promise<T> {
  const response = await fetch(`${API_URL}${path}`, {
    ...options,
    headers: {
      'Content-Type': 'application/json',
      ...options.headers,
    },
  })

  if (!response.ok) {
    const message = await response.text()
    throw new Error(message || `Помилка HTTP ${response.status}`)
  }

  if (response.status === 204) {
    return undefined as T
  }

  return response.json() as Promise<T>
}

function json(method: string, body?: unknown): RequestInit {
  return {
    method,
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
  }
}

export const api = {
  getTests: () => request<Test[]>('/api/tests'),
  createTest: (data: TestInput) =>
    request<Test>('/api/tests', json('POST', data)),
  updateTest: (id: number, data: TestInput & { isPublished: boolean }) =>
    request<Test>(`/api/tests/${id}`, json('PUT', data)),
  deleteTest: (id: number) =>
    request<void>(`/api/tests/${id}`, json('DELETE')),

  getQuestions: (testId: number) =>
    request<Question[]>(`/api/tests/${testId}/questions`),
  createQuestion: (testId: number, data: QuestionInput) =>
    request<Question>(`/api/tests/${testId}/questions`, json('POST', data)),
  updateQuestion: (id: number, data: QuestionInput) =>
    request<Question>(`/api/questions/${id}`, json('PUT', data)),
  deleteQuestion: (id: number) =>
    request<void>(`/api/questions/${id}`, json('DELETE')),

  getOptions: (questionId: number) =>
    request<AnswerOption[]>(`/api/questions/${questionId}/options`),
  createOption: (questionId: number, data: AnswerOptionInput) =>
    request<AnswerOption>(
      `/api/questions/${questionId}/options`,
      json('POST', data),
    ),
  updateOption: (id: number, data: AnswerOptionInput) =>
    request<AnswerOption>(`/api/options/${id}`, json('PUT', data)),
  deleteOption: (id: number) =>
    request<void>(`/api/options/${id}`, json('DELETE')),

  startAttempt: (testId: number) =>
    request<AttemptStartResponse>(
      `/api/tests/${testId}/attempts`,
      json('POST'),
    ),

  saveAttemptAnswer: (
    attemptId: number,
    accessToken: string,
    questionId: number,
    selectedOptionId: number,
  ) =>
    request<void>(
      `/api/attempts/${attemptId}/answers`,
      {
        ...json('PUT', { questionId, selectedOptionId }),
        headers: { 'X-Attempt-Token': accessToken },
      },
    ),

  submitAttempt: (attemptId: number, accessToken: string) =>
    request<AttemptResult>(
      `/api/attempts/${attemptId}/submit`,
      {
        ...json('POST'),
        headers: { 'X-Attempt-Token': accessToken },
      },
    ),

}
