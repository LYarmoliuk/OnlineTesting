
export interface Test {
  id: number
  title: string
  description: string
  isPublished: boolean
  createdAt: string
}

export interface Question {
  id: number
  testId: number
  text: string
  order: number
  points: number
}

export interface AnswerOption {
  id: number
  questionId: number
  text: string
  isCorrect: boolean
}

export interface TestInput {
  title: string
  description: string
}

export interface QuestionInput {
  text: string
  order: number
  points: number
}

export interface AnswerOptionInput {
  text: string
  isCorrect: boolean
}

export interface StudentOption {
  id: number
  text: string
}

export interface StudentQuestion {
  id: number
  text: string
  order: number
  points: number
  selectedOptionId: number | null
  options: StudentOption[]
}

export interface AttemptStartResponse {
  attemptId: number
  testId: number
  testTitle: string
  accessToken: string
  status: string
  startedAt: string
  completedAt: string | null
  score: number | null
  questions: StudentQuestion[]
}

export interface AttemptResult {
  attemptId: number
  testTitle: string
  score: number
  maxScore: number
  answeredQuestions: number
  totalQuestions: number
  completedAt: string | null
}
