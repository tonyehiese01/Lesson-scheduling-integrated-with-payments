
(define-data-var admin principal tx-sender)
(define-data-var last-lesson-id uint u0)  ;; Track the last assigned lesson ID

;; ========= DATA STRUCTURES =========

;; Tuples for lesson data
(define-map lessons
  { lesson-id: uint }
  {
    teacher: principal,
    student: principal,
    start-time: uint,
    duration: uint,
    price: uint,
    status: (string-ascii 20),
    payment-status: (string-ascii 20)
  }
)

;; Track all lessons for each teacher
(define-map teacher-lessons
  { teacher: principal }
  { lesson-ids: (list 100 uint) }
)

;; Track all lessons for each student
(define-map student-lessons
  { student: principal }
  { lesson-ids: (list 100 uint) }
)

;; Balances for teachers
(define-map teacher-balances
  { teacher: principal }
  { balance: uint }
)

;; ========= PRIVATE FUNCTIONS =========

;; Helper function to add a lesson ID to a principal's list of lessons
(define-private (add-lesson-to-list (lesson-id uint) (user principal) (is-teacher bool))
  (if is-teacher
    (map-set teacher-lessons
      { teacher: user }
      {
        lesson-ids: (unwrap-panic
          (as-max-len?
            (append
              (default-to (list) (get lesson-ids (map-get? teacher-lessons { teacher: user })))
              lesson-id
            )
            u100
          )
        )
      }
    )
    (map-set student-lessons
      { student: user }
      {
        lesson-ids: (unwrap-panic
          (as-max-len?
            (append
              (default-to (list) (get lesson-ids (map-get? student-lessons { student: user })))
              lesson-id
            )
            u100
          )
        )
      }
    )
  )
)
;; ========= PUBLIC FUNCTIONS =========

;; Initialize a new teacher in the system
(define-public (register-as-teacher)
  (begin
    (map-set teacher-balances
      { teacher: tx-sender }
      { balance: u0 }
    )
    (ok true)
  )
)

;; Create a new lesson
(define-public (schedule-lesson (student principal) (start-time uint) (duration uint) (price uint))
  (let
    (
      ;; Generate a new lesson ID by incrementing the last ID
      (lesson-id (+ u1 (var-get last-lesson-id)))
    )
    (asserts! (is-some (map-get? teacher-balances { teacher: tx-sender })) (err u1)) ;; ensure teacher is registered
    (map-set lessons
      { lesson-id: lesson-id }
      {
        teacher: tx-sender,
        student: student,
        start-time: start-time,
        duration: duration,
        price: price,
        status: "scheduled",
        payment-status: "unpaid"
      }
    )
    ;; Update the last lesson ID
    (var-set last-lesson-id lesson-id)
    ;; Add lesson to teacher's list
    (add-lesson-to-list lesson-id tx-sender true)
    ;; Add lesson to student's list
    (add-lesson-to-list lesson-id student false)
    (ok lesson-id)
  )
)

;; Pay for a lesson
(define-public (pay-for-lesson (lesson-id uint))
  (let
    (
      (lesson (unwrap! (map-get? lessons { lesson-id: lesson-id }) (err u2)))
      (price (get price lesson))
      (teacher (get teacher lesson))
    )
    ;; Check that sender is the student
    (asserts! (is-eq tx-sender (get student lesson)) (err u3))
    ;; Check that lesson is still unpaid
    (asserts! (is-eq (get payment-status lesson) "unpaid") (err u4))
    
    ;; Transfer STX tokens from student to contract
    (try! (stx-transfer? price tx-sender (as-contract tx-sender)))
    
    ;; Update teacher's balance
    (map-set teacher-balances
      { teacher: teacher }
      { balance: (+ price (default-to u0 (get balance (map-get? teacher-balances { teacher: teacher })))) }
    )
    
    ;; Update lesson status
    (map-set lessons
      { lesson-id: lesson-id }
      (merge lesson { payment-status: "paid" })
    )
    
    (ok true)
  )
)

;; Mark lesson as completed (can only be done by the teacher)
(define-public (complete-lesson (lesson-id uint))
  (let
    (
      (lesson (unwrap! (map-get? lessons { lesson-id: lesson-id }) (err u2)))
    )
    ;; Check that sender is the teacher
    (asserts! (is-eq tx-sender (get teacher lesson)) (err u5))
    ;; Update lesson status
    (map-set lessons
      { lesson-id: lesson-id }
      (merge lesson { status: "completed" })
    )
    (ok true)
  )
)

;; Cancel a lesson
(define-public (cancel-lesson (lesson-id uint) (current-time uint))
  (let
    (
      (lesson (unwrap! (map-get? lessons { lesson-id: lesson-id }) (err u2)))
      (lesson-time (get start-time lesson))
      (time-difference (- lesson-time current-time))
    )
    ;; Check that sender is either the teacher or the student
    (asserts! (or (is-eq tx-sender (get teacher lesson)) (is-eq tx-sender (get student lesson))) (err u6))
    
    ;; If already paid, and cancellation happens more than 24 hours before the lesson
    ;; Assuming time is in seconds, 24 hours = 86400 seconds
    (if (and
         (is-eq (get payment-status lesson) "paid")
         (> time-difference u86400)
        )
        ;; Refund the student
        (begin
          ;; Transfer STX tokens from contract to student
          (try! (as-contract (stx-transfer? (get price lesson) tx-sender (get student lesson))))
          
          ;; Update teacher's balance
          (map-set teacher-balances
            { teacher: (get teacher lesson) }
            { balance: (- (default-to u0 (get balance (map-get? teacher-balances { teacher: (get teacher lesson) }))) (get price lesson)) }
          )
          
          ;; Update lesson status
          (map-set lessons
            { lesson-id: lesson-id }
            (merge lesson { status: "cancelled", payment-status: "refunded" })
          )
        )
        ;; No refund for late cancellations or unpaid lessons
        (map-set lessons
          { lesson-id: lesson-id }
          (merge lesson { status: "cancelled" })
        )
    )
    (ok true)
  )
)

;; Teacher can withdraw their balance
(define-public (withdraw-balance)
  (let
    (
      (balance-data (unwrap! (map-get? teacher-balances { teacher: tx-sender }) (err u7)))
      (amount (get balance balance-data))
    )
    (asserts! (> amount u0) (err u8))
    
    ;; Transfer STX tokens from contract to teacher
    (try! (as-contract (stx-transfer? amount tx-sender tx-sender)))
    
    ;; Reset teacher's balance
    (map-set teacher-balances
      { teacher: tx-sender }
      { balance: u0 }
    )
    
    (ok true)
  )
)

;; ========= READ-ONLY FUNCTIONS =========

;; Get lesson details
(define-read-only (get-lesson (lesson-id uint))
  (map-get? lessons { lesson-id: lesson-id })
)

;; Get teacher balance
(define-read-only (get-teacher-balance (teacher principal))
  (default-to u0 (get balance (map-get? teacher-balances { teacher: teacher })))
)

;; Get all lessons for a teacher
(define-read-only (get-teacher-lessons (teacher principal))
  (default-to (list) (get lesson-ids (map-get? teacher-lessons { teacher: teacher })))
)

;; Get all lessons for a student
(define-read-only (get-student-lessons (student principal))
  (default-to (list) (get lesson-ids (map-get? student-lessons { student: student })))
)