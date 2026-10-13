
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
