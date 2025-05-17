import { describe, it, expect, beforeEach } from 'vitest'

// Mocks or abstractions (you'll need to implement or import these)
import {
  deployContract,
  registerAsTeacher,
  scheduleLesson,
  payForLesson,
  completeLesson,
  cancelLesson,
  withdrawBalance,
  getLesson,
  getTeacherBalance,
  getTeacherLessons,
  getStudentLessons,
  setCurrentSender
} from './contract-mock' // <-- your Clarity simulation/mocking layer

const teacher = 'ST1TEACHER00000000000000000000000000000000'
const student = 'ST1STUDENT0000000000000000000000000000000'

describe('Lesson Scheduling Contract', () => {
  beforeEach(() => {
    deployContract()
  })

  it('should allow a user to register as a teacher', () => {
    setCurrentSender(teacher)
    const result = registerAsTeacher()
    expect(result).toEqual({ ok: true })
    expect(getTeacherBalance(teacher)).toBe(0)
  })

  it('should allow scheduling a lesson', () => {
    setCurrentSender(teacher)
    registerAsTeacher()

    const startTime = 100000
    const duration = 3600
    const price = 5000

    const result = scheduleLesson(student, startTime, duration, price)
    expect(result.ok).toBeDefined()
    const lessonId = result.ok

    const lesson = getLesson(lessonId)
    expect(lesson.teacher).toBe(teacher)
    expect(lesson.student).toBe(student)
    expect(lesson.status).toBe('scheduled')
    expect(lesson.payment_status).toBe('unpaid')
  })

  it('should allow student to pay for a lesson', () => {
    setCurrentSender(teacher)
    registerAsTeacher()
    const lessonId = scheduleLesson(student, 100000, 3600, 10000).ok

    setCurrentSender(student)
    const result = payForLesson(lessonId)
    expect(result.ok).toBe(true)

    const lesson = getLesson(lessonId)
    expect(lesson.payment_status).toBe('paid')
    expect(getTeacherBalance(teacher)).toBe(10000)
  })

  it('should allow a teacher to complete a lesson', () => {
    setCurrentSender(teacher)
    registerAsTeacher()
    const lessonId = scheduleLesson(student, 100000, 3600, 5000).ok

    setCurrentSender(student)
    payForLesson(lessonId)

    setCurrentSender(teacher)
    const result = completeLesson(lessonId)
    expect(result.ok).toBe(true)

    const lesson = getLesson(lessonId)
    expect(lesson.status).toBe('completed')
  })

  it('should allow cancelling a lesson and refund if >24h', () => {
    setCurrentSender(teacher)
    registerAsTeacher()
    const lessonId = scheduleLesson(student, 100000, 3600, 5000).ok

    setCurrentSender(student)
    payForLesson(lessonId)

    setCurrentSender(student)
    const result = cancelLesson(lessonId, 100000 - 90000) // >24h = 86400s
    expect(result.ok).toBe(true)

    const lesson = getLesson(lessonId)
    expect(lesson.status).toBe('cancelled')
    expect(lesson.payment_status).toBe('refunded')
    expect(getTeacherBalance(teacher)).toBe(0)
  })

  it('should allow teacher to withdraw balance', () => {
    setCurrentSender(teacher)
    registerAsTeacher()
    const lessonId = scheduleLesson(student, 100000, 3600, 9000).ok

    setCurrentSender(student)
    payForLesson(lessonId)

    setCurrentSender(teacher)
    const result = withdrawBalance()
    expect(result.ok).toBe(true)

    expect(getTeacherBalance(teacher)).toBe(0)
  })

  it('should track teacher and student lessons correctly', () => {
    setCurrentSender(teacher)
    registerAsTeacher()
    const lessonId1 = scheduleLesson(student, 100000, 3600, 1000).ok
    const lessonId2 = scheduleLesson(student, 110000, 3600, 2000).ok

    expect(getTeacherLessons(teacher)).toEqual([lessonId1, lessonId2])
    expect(getStudentLessons(student)).toEqual([lessonId1, lessonId2])
  })
})
