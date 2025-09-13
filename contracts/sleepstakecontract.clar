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

;; public functions

;; Create a new health goal with financial stake
(define-public (create-goal (goal-type uint) (target-value uint) (duration-blocks uint) (stake-amount uint))
  (let 
    (
      (goal-id (var-get next-goal-id))
      (end-block (+ block-height duration-blocks))
    )
    (asserts! (or (is-eq goal-type GOAL_TYPE_SLEEP) 
                  (is-eq goal-type GOAL_TYPE_EXERCISE) 
                  (is-eq goal-type GOAL_TYPE_NUTRITION)) ERR_INVALID_GOAL)
    (asserts! (>= stake-amount MIN_STAKE_AMOUNT) ERR_INSUFFICIENT_STAKE)
    (asserts! (> duration-blocks u0) ERR_INVALID_TIMEFRAME)
    (asserts! (> target-value u0) ERR_INVALID_GOAL)
    
    ;; Transfer stake to contract
    (try! (stx-transfer? stake-amount tx-sender (as-contract tx-sender)))
    
    ;; Create goal record
    (map-set goals goal-id {
      creator: tx-sender,
      goal-type: goal-type,
      target-value: target-value,
      current-value: u0,
      stake-amount: stake-amount,
      start-block: block-height,
      end-block: end-block,
      completed: false,
      verified: false,
      reward-claimed: false
    })
    
    (map-set user-goals {user: tx-sender, goal-id: goal-id} true)
    
    ;; Update contract state
    (var-set next-goal-id (+ goal-id u1))
    (var-set total-staked (+ (var-get total-staked) stake-amount))
    
    (ok goal-id)
  )
)

;; Submit biometric data for goal verification
(define-public (submit-biometric-data (goal-id uint) (data-value uint) (oracle-signature (buff 65)))
  (let 
    (
      (goal (unwrap! (map-get? goals goal-id) ERR_GOAL_NOT_FOUND))
      (timestamp block-height)
    )
    (asserts! (is-eq (get creator goal) tx-sender) ERR_UNAUTHORIZED)
    (asserts! (not (get completed goal)) ERR_GOAL_ALREADY_COMPLETED)
    (asserts! (<= block-height (get end-block goal)) ERR_INVALID_TIMEFRAME)
    
    ;; Store biometric data
    (map-set biometric-data {user: tx-sender, timestamp: timestamp} {
      data-type: (get goal-type goal),
      value: data-value,
      verified: false,
      oracle-signature: (some oracle-signature)
    })
    
    ;; Update goal progress
    (map-set goals goal-id (merge goal {
      current-value: (+ (get current-value goal) data-value)
    }))
    
    (ok true)
  )
)

;; Oracle verification of biometric data
(define-public (verify-biometric-data (user principal) (timestamp uint) (is-valid bool))
  (let 
    (
      (data (unwrap! (map-get? biometric-data {user: user, timestamp: timestamp}) ERR_VERIFICATION_FAILED))
    )
    (asserts! (is-eq tx-sender (var-get oracle-address)) ERR_UNAUTHORIZED)
    
    (map-set biometric-data {user: user, timestamp: timestamp} (merge data {
      verified: is-valid
    }))
    
    (ok is-valid)
  )
)

;; Check goal completion and mark as completed
(define-public (complete-goal (goal-id uint))
  (let 
    (
      (goal (unwrap! (map-get? goals goal-id) ERR_GOAL_NOT_FOUND))
    )
    (asserts! (is-eq (get creator goal) tx-sender) ERR_UNAUTHORIZED)
    (asserts! (not (get completed goal)) ERR_GOAL_ALREADY_COMPLETED)
    (asserts! (>= (get current-value goal) (get target-value goal)) ERR_VERIFICATION_FAILED)
    
    (map-set goals goal-id (merge goal {
      completed: true,
      verified: true
    }))
    
    ;; Mint reward tokens
    (try! (ft-mint? sleepstake-reward (get stake-amount goal) tx-sender))
    
    (ok true)
  )
)

;; Claim rewards for completed goals
(define-public (claim-reward (goal-id uint))
  (let 
    (
      (goal (unwrap! (map-get? goals goal-id) ERR_GOAL_NOT_FOUND))
      (reward-amount (/ (* (get stake-amount goal) REWARD_MULTIPLIER) u100))
      (platform-fee (/ (* reward-amount PLATFORM_FEE_PERCENT) u100))
      (user-reward (- reward-amount platform-fee))
    )
    (asserts! (is-eq (get creator goal) tx-sender) ERR_UNAUTHORIZED)
    (asserts! (get completed goal) ERR_VERIFICATION_FAILED)
    (asserts! (get verified goal) ERR_VERIFICATION_FAILED)
    (asserts! (not (get reward-claimed goal)) ERR_GOAL_ALREADY_COMPLETED)
    
    ;; Transfer rewards
    (try! (as-contract (stx-transfer? user-reward tx-sender tx-sender)))
    
    ;; Update platform treasury
    (var-set platform-treasury (+ (var-get platform-treasury) platform-fee))
    
    ;; Mark reward as claimed
    (map-set goals goal-id (merge goal {
      reward-claimed: true
    }))
    
    (ok user-reward)
  )
)

;; Create accountability group
(define-public (create-accountability-group (name (string-ascii 50)))
  (let 
    (
      (group-id (var-get next-group-id))
    )
    (map-set accountability-groups group-id {
      name: name,
      creator: tx-sender,
      member-count: u1,
      total-stake: u0,
      active: true
    })
    
    (map-set group-members {group-id: group-id, member: tx-sender} {
      stake-amount: u0,
      goals-completed: u0,
      joined-block: block-height
    })
    
    (var-set next-group-id (+ group-id u1))
    (ok group-id)
  )
)

;; Join accountability group
(define-public (join-group (group-id uint) (stake-amount uint))
  (let 
    (
      (group (unwrap! (map-get? accountability-groups group-id) ERR_GROUP_NOT_FOUND))
    )
    (asserts! (get active group) ERR_GROUP_NOT_FOUND)
    (asserts! (is-none (map-get? group-members {group-id: group-id, member: tx-sender})) ERR_ALREADY_MEMBER)
    (asserts! (>= stake-amount MIN_STAKE_AMOUNT) ERR_INSUFFICIENT_STAKE)
    
    ;; Transfer stake to contract
    (try! (stx-transfer? stake-amount tx-sender (as-contract tx-sender)))
    
    (map-set group-members {group-id: group-id, member: tx-sender} {
      stake-amount: stake-amount,
      goals-completed: u0,
      joined-block: block-height
    })
    
    (map-set accountability-groups group-id (merge group {
      member-count: (+ (get member-count group) u1),
      total-stake: (+ (get total-stake group) stake-amount)
    }))
    
    (ok true)
  )
)

;; Register healthcare provider
(define-public (register-healthcare-provider (name (string-ascii 100)) (incentive-rate uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    
    (map-set healthcare-providers tx-sender {
      name: name,
      verified: true,
      incentive-rate: incentive-rate
    })
    
    (ok true)
  )
)

;; Link user to healthcare provider for incentives
(define-public (link-to-provider (provider principal) (bonus-rate uint))
  (let 
    (
      (provider-info (unwrap! (map-get? healthcare-providers provider) ERR_UNAUTHORIZED))
    )
    (asserts! (get verified provider-info) ERR_UNAUTHORIZED)
    
    (map-set provider-user-link {provider: provider, user: tx-sender} {
      active: true,
      bonus-rate: bonus-rate
    })
    
    (ok true)
  )
)
