;; title: SleepStake Health Commitment Contract
;; version: 1.0.0
;; summary: A decentralized platform for health goal accountability with financial stakes
;; description: Users can stake STX tokens on health goals (sleep, exercise, nutrition) 
;;              with biometric verification from wearable devices and peer accountability

;; traits
(define-trait oracle-trait
  (
    (verify-data (principal uint uint) (response bool uint))
  )
)

;; token definitions
(define-fungible-token sleepstake-reward)

;; constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_INVALID_GOAL (err u101))
(define-constant ERR_INSUFFICIENT_STAKE (err u102))
(define-constant ERR_GOAL_NOT_FOUND (err u103))
(define-constant ERR_GOAL_ALREADY_COMPLETED (err u104))
(define-constant ERR_VERIFICATION_FAILED (err u105))
(define-constant ERR_INVALID_TIMEFRAME (err u106))
(define-constant ERR_INSUFFICIENT_BALANCE (err u107))
(define-constant ERR_ALREADY_MEMBER (err u108))
(define-constant ERR_GROUP_NOT_FOUND (err u109))

(define-constant GOAL_TYPE_SLEEP u1)
(define-constant GOAL_TYPE_EXERCISE u2)
(define-constant GOAL_TYPE_NUTRITION u3)

(define-constant MIN_STAKE_AMOUNT u1000000) ;; 1 STX in microSTX
(define-constant PLATFORM_FEE_PERCENT u5) ;; 5% platform fee
(define-constant REWARD_MULTIPLIER u120) ;; 120% reward for successful completion

;; data vars
(define-data-var next-goal-id uint u1)
(define-data-var next-group-id uint u1)
(define-data-var total-staked uint u0)
(define-data-var platform-treasury uint u0)
(define-data-var oracle-address principal tx-sender)

;; data maps
(define-map goals 
  uint 
  {
    creator: principal,
    goal-type: uint,
    target-value: uint,
    current-value: uint,
    stake-amount: uint,
    start-block: uint,
    end-block: uint,
    completed: bool,
    verified: bool,
    reward-claimed: bool
  }
)

(define-map user-goals 
  {user: principal, goal-id: uint}
  bool
)

(define-map accountability-groups
  uint
  {
    name: (string-ascii 50),
    creator: principal,
    member-count: uint,
    total-stake: uint,
    active: bool
  }
)

(define-map group-members
  {group-id: uint, member: principal}
  {
    stake-amount: uint,
    goals-completed: uint,
    joined-block: uint
  }
)

(define-map group-goals
  {group-id: uint, goal-id: uint}
  bool
)

(define-map biometric-data
  {user: principal, timestamp: uint}
  {
    data-type: uint,
    value: uint,
    verified: bool,
    oracle-signature: (optional (buff 65))
  }
)

(define-map healthcare-providers
  principal
  {
    name: (string-ascii 100),
    verified: bool,
    incentive-rate: uint
  }
)

(define-map provider-user-link
  {provider: principal, user: principal}
  {
    active: bool,
    bonus-rate: uint
  }
)
