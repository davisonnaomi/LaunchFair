;; Token Launchpad - Platform for launching new tokens with fair distribution mechanisms
;; Author: Claude
;; Date: 2025-05-20
;; Description: Smart contract implementing a fair token launch platform

;; Constants
(define-constant contract-owner tx-sender)
(define-constant min-launch-duration u5000) ;; Minimum blocks for a token launch
(define-constant max-projects u50) ;; Maximum number of concurrent projects
(define-constant precision u1000000) ;; For percentage calculations

;; Error codes
(define-constant err-owner-only (err u200))
(define-constant err-invalid-params (err u201))
(define-constant err-project-exists (err u202))
(define-constant err-project-not-found (err u203))
(define-constant err-not-active (err u204))
(define-constant err-zero-amount (err u205))
(define-constant err-insufficient-balance (err u206))
(define-constant err-allocation-exceeded (err u207))
(define-constant err-project-ended (err u208))
(define-constant err-project-not-ended (err u209))
(define-constant err-already-claimed (err u210))
(define-constant err-no-contribution (err u211))
(define-constant err-max-cap-reached (err u212))
(define-constant err-launch-in-progress (err u213))
(define-constant err-max-projects-reached (err u214))
(define-constant err-not-whitelisted (err u215))

;; Project statuses
(define-constant status-pending u0)
(define-constant status-active u1)
(define-constant status-ended u2)
(define-constant status-canceled u3)

;; Distribution types
(define-constant dist-fixed-price u0)
(define-constant dist-dutch-auction u1)
(define-constant dist-fair-launch u2)

;; Data variables
(define-data-var project-count uint u0)

;; Project data structure
(define-map projects
  { project-id: uint }
  {
    name: (string-ascii 64),
    token-contract: principal,
    creator: principal,
    token-symbol: (string-ascii 10),
    start-block: uint,
    end-block: uint,
    total-tokens: uint,
    tokens-sold: uint,
    status: uint,
    distribution-type: uint,
    price-per-token: uint,
    min-price: uint, ;; For dutch auction
    max-price: uint, ;; For dutch auction
    min-raise: uint, ;; Minimum amount to raise
    max-raise: uint, ;; Maximum amount to raise (hard cap)
    individual-min: uint, ;; Minimum contribution per wallet
    individual-max: uint, ;; Maximum contribution per wallet
    use-whitelist: bool
  }
)

;; Track user contributions
(define-map contributions
  { project-id: uint, user: principal }
  {
    amount: uint,
    tokens-claimed: bool
  }
)

;; Total contributions per project
(define-map project-contributions
  { project-id: uint }
  { total-raised: uint }
)

;; Whitelist for projects
(define-map whitelist
  { project-id: uint, user: principal }
  { whitelisted: bool }
)

;; Project tokens - map token-contract to project-id
(define-map project-tokens
  { token-contract: principal }
  { project-id: uint }
)

;; Contract fungible token for stablecoin-like deposits (in a real implementation, use an existing stablecoin)
(define-fungible-token payment-token)

;; ===========================================
;; Admin Functions
;; ===========================================

;; Create a new token launch project
(define-public (create-project
                (name (string-ascii 64))
                (token-contract principal)
                (token-symbol (string-ascii 10))
                (duration uint)
                (total-tokens uint)
                (distribution-type uint)
                (price-params (tuple (price-per-token uint) (min-price uint) (max-price uint)))
                (raise-params (tuple (min-raise uint) (max-raise uint)))
                (individual-limits (tuple (min uint) (max uint)))
                (use-whitelist bool))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (> duration min-launch-duration) err-invalid-params)
    (asserts! (> total-tokens u0) err-invalid-params)
    (asserts! (< (var-get project-count) max-projects) err-max-projects-reached)
    
    ;; Validate distribution type and params
    (asserts! (or (is-eq distribution-type dist-fixed-price)
                 (is-eq distribution-type dist-dutch-auction)
                 (is-eq distribution-type dist-fair-launch))
             err-invalid-params)
             
    ;; Check price params based on distribution type
    (if (is-eq distribution-type dist-fixed-price)
        (asserts! (> (get price-per-token price-params) u0) err-invalid-params)
        true)
        
    (if (is-eq distribution-type dist-dutch-auction)
        (asserts! (and (> (get max-price price-params) u0)
                      (> (get max-price price-params) (get min-price price-params)))
                 err-invalid-params)
        true)
        
    ;; Check raise parameters
    (asserts! (and (> (get max-raise raise-params) u0)
                  (>= (get max-raise raise-params) (get min-raise raise-params)))
             err-invalid-params)
             
    ;; Check individual limits if set
    (if (> (get max individual-limits) u0)
        (asserts! (>= (get max individual-limits) (get min individual-limits)) err-invalid-params)
        true)
        
    ;; Check if token contract is already used
    (asserts! (is-none (map-get? project-tokens { token-contract: token-contract })) err-project-exists)
    
    (let ((current-block burn-block-height)
          (next-id (var-get project-count)))
          
      ;; Create project
      (map-set projects
        { project-id: next-id }
        {
          name: name,
          token-contract: token-contract,
          creator: tx-sender,
          token-symbol: token-symbol,
          start-block: current-block,
          end-block: (+ current-block duration),
          total-tokens: total-tokens,
          tokens-sold: u0,
          status: status-active,
          distribution-type: distribution-type,
          price-per-token: (get price-per-token price-params),
          min-price: (get min-price price-params),
          max-price: (get max-price price-params),
          min-raise: (get min-raise raise-params),
          max-raise: (get max-raise raise-params),
          individual-min: (get min individual-limits),
          individual-max: (get max individual-limits),
          use-whitelist: use-whitelist
        }
      )
      
      ;; Initialize project contributions
      (map-set project-contributions
        { project-id: next-id }
        { total-raised: u0 }
      )
      
      ;; Map token contract to project id
      (map-set project-tokens
        { token-contract: token-contract }
        { project-id: next-id }
      )
      
      ;; Increment project count
      (var-set project-count (+ next-id u1))
      
      (ok next-id)
    )
  )
)

;; Add users to whitelist
(define-public (add-to-whitelist (project-id uint) (users (list 200 principal)))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (is-some (map-get? projects { project-id: project-id })) err-project-not-found)
    
    (let ((project (unwrap-panic (map-get? projects { project-id: project-id }))))
      (asserts! (is-eq (get status project) status-pending) err-launch-in-progress)
      
      ;; Add each user to whitelist
      (map add-user-to-whitelist users)
      
      (ok true)
    )
  )
)

;; Helper function to add a single user to whitelist
(define-private (add-user-to-whitelist (user principal))
  (let ((project-id (var-get project-count)))
    (map-set whitelist
      { project-id: project-id, user: user }
      { whitelisted: true }
    )
    true
  )
)

;; Cancel a project
(define-public (cancel-project (project-id uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (is-some (map-get? projects { project-id: project-id })) err-project-not-found)
    
    (let ((project (unwrap-panic (map-get? projects { project-id: project-id }))))
      (asserts! (or (is-eq (get status project) status-pending)
                   (is-eq (get status project) status-active))
               err-project-ended)
               
      ;; Update project status
      (map-set projects
        { project-id: project-id }
        (merge project { status: status-canceled })
      )
      
      (ok true)
    )
  )
)

;; ===========================================
;; User Functions
;; ===========================================

;; Contribute to a token launch
(define-public (contribute (project-id uint) (amount uint))
  (begin
    (asserts! (> amount u0) err-zero-amount)
    (asserts! (is-some (map-get? projects { project-id: project-id })) err-project-not-found)
    
    (let ((project (unwrap-panic (map-get? projects { project-id: project-id })))
          (current-block burn-block-height)
          (user tx-sender))
    
      ;; Check project is active
      (asserts! (is-eq (get status project) status-active) err-not-active)
      (asserts! (<= current-block (get end-block project)) err-project-ended)
      
      ;; Check whitelist if required
      (if (get use-whitelist project)
          (let ((user-whitelist (default-to { whitelisted: false } 
                                (map-get? whitelist { project-id: project-id, user: user }))))
            (asserts! (get whitelisted user-whitelist) err-not-whitelisted))
          true)
      
      ;; Check contribution limits
      (let ((user-contribution (default-to { amount: u0, tokens-claimed: false }
                               (map-get? contributions { project-id: project-id, user: user })))
            (new-amount (+ (get amount user-contribution) amount))
            (individual-min (get individual-min project))
            (individual-max (get individual-max project)))
      
        ;; Check minimum contribution
        (if (> individual-min u0)
            (asserts! (>= new-amount individual-min) err-invalid-params)
            true)
            
        ;; Check maximum contribution
        (if (> individual-max u0)
            (asserts! (<= new-amount individual-max) err-allocation-exceeded)
            true)
            
        ;; Check hard cap
        (let ((project-contrib (unwrap-panic (map-get? project-contributions { project-id: project-id })))
              (new-total (+ (get total-raised project-contrib) amount)))
          
          (asserts! (<= new-total (get max-raise project)) err-max-cap-reached)
          
          ;; Transfer payment tokens from user to contract
          (try! (ft-transfer? payment-token amount user (as-contract tx-sender)))
          
          ;; Update user contribution
          (map-set contributions
            { project-id: project-id, user: user }
            { amount: new-amount, tokens-claimed: false }
          )
          
          ;; Update total contributions
          (map-set project-contributions
            { project-id: project-id }
            { total-raised: new-total }
          )
          
          (ok new-amount)
        )
      )
    )
  )
)

;; Calculate token allocation based on contribution
(define-private (calculate-allocation (project-id uint) (user principal))
  (let ((project (unwrap-panic (map-get? projects { project-id: project-id })))
        (user-contrib (unwrap-panic (map-get? contributions { project-id: project-id, user: user })))
        (project-contrib (unwrap-panic (map-get? project-contributions { project-id: project-id })))
        (contribution-amount (get amount user-contrib))
        (distribution-type (get distribution-type project)))
    
    ;; Different distribution mechanisms
    (if (is-eq distribution-type dist-fixed-price)
        ;; Fixed price: tokens = contribution / price-per-token
        (/ (* contribution-amount precision) (get price-per-token project))
        
        (if (is-eq distribution-type dist-dutch-auction)
            ;; Dutch auction: calculate final price based on demand
            (let ((final-price (calculate-dutch-auction-price project-id)))
              (/ (* contribution-amount precision) final-price))
            
            ;; Fair launch: proportional to contribution
            (let ((total-raised (get total-raised project-contrib))
                  (total-tokens (get total-tokens project)))
              (if (> total-raised u0)
                  (/ (* contribution-amount total-tokens) total-raised)
                  u0))
        )
    )
  )
)

;; Calculate final price for Dutch auction
(define-private (calculate-dutch-auction-price (project-id uint))
  (let ((project (unwrap-panic (map-get? projects { project-id: project-id })))
        (project-contrib (unwrap-panic (map-get? project-contributions { project-id: project-id })))
        (total-raised (get total-raised project-contrib))
        (min-price (get min-price project))
        (max-price (get max-price project))
        (total-tokens (get total-tokens project)))
    
    (if (>= total-raised (get max-raise project))
        ;; If max raise is reached, calculate price based on demand
        (let ((implied-price (/ (* total-raised precision) total-tokens)))
          (if (> implied-price max-price)
              max-price
              (if (< implied-price min-price)
                  min-price
                  implied-price)))
        ;; Otherwise use minimum price
        min-price)
  )
)

;; Finalize project after end date
(define-public (finalize-project (project-id uint))
  (begin
    (asserts! (is-some (map-get? projects { project-id: project-id })) err-project-not-found)
    
    (let ((project (unwrap-panic (map-get? projects { project-id: project-id })))
          (current-block burn-block-height))
    
      ;; Check project can be finalized
      (asserts! (is-eq (get status project) status-active) err-not-active)
      (asserts! (> current-block (get end-block project)) err-project-not-ended)
      
      (let ((project-contrib (unwrap-panic (map-get? project-contributions { project-id: project-id })))
            (total-raised (get total-raised project-contrib)))
        
        ;; Check if minimum raise was met
        (if (>= total-raised (get min-raise project))
            ;; Success - update project status
            (map-set projects
              { project-id: project-id }
              (merge project { status: status-ended })
            )
            ;; Failed - update project status to canceled for refunds
            (map-set projects
              { project-id: project-id }
              (merge project { status: status-canceled })
            )
        )
        
        (ok true)
      )
    )
  )
)

;; Claim tokens after successful launch
(define-public (claim-tokens (project-id uint))
  (begin
    (asserts! (is-some (map-get? projects { project-id: project-id })) err-project-not-found)
    
    (let ((project (unwrap-panic (map-get? projects { project-id: project-id })))
          (user tx-sender))
    
      ;; Check project is ended
      (asserts! (is-eq (get status project) status-ended) err-project-not-ended)
      
      ;; Check user contribution
      (let ((user-contrib (default-to { amount: u0, tokens-claimed: false }
                          (map-get? contributions { project-id: project-id, user: user }))))
      
        (asserts! (> (get amount user-contrib) u0) err-no-contribution)
        (asserts! (not (get tokens-claimed user-contrib)) err-already-claimed)
        
        ;; Calculate token allocation
        (let ((token-amount (calculate-allocation project-id user))
              (token-contract (get token-contract project)))
          
          ;; Mark as claimed
          (map-set contributions
            { project-id: project-id, user: user }
            { amount: (get amount user-contrib), tokens-claimed: true }
          )
          
          ;; Update tokens sold
          (map-set projects
            { project-id: project-id }
            (merge project { tokens-sold: (+ (get tokens-sold project) token-amount) })
          )
          
          ;; Transfer tokens to user (would use imported token contract)
          ;; For demonstration purposes, we'll just return the amount
          ;; In a real implementation, you would call the token contract's transfer function
          (ok token-amount)
        )
      )
    )
  )
)

;; Get refund if project was canceled or didn't meet minimum raise
(define-public (get-refund (project-id uint))
  (begin
    (asserts! (is-some (map-get? projects { project-id: project-id })) err-project-not-found)
    
    (let ((project (unwrap-panic (map-get? projects { project-id: project-id })))
          (user tx-sender))
    
      ;; Check project is canceled
      (asserts! (is-eq (get status project) status-canceled) err-not-active)
      
      ;; Check user contribution
      (let ((user-contrib (default-to { amount: u0, tokens-claimed: false }
                          (map-get? contributions { project-id: project-id, user: user }))))
      
        (asserts! (> (get amount user-contrib) u0) err-no-contribution)
        (asserts! (not (get tokens-claimed user-contrib)) err-already-claimed)
        
        ;; Mark as claimed to prevent double refunds
        (map-set contributions
          { project-id: project-id, user: user }
          { amount: (get amount user-contrib), tokens-claimed: true }
        )
        
        ;; Transfer payment tokens back to user
        (as-contract (ft-transfer? payment-token 
                               (get amount user-contrib) 
                               tx-sender 
                               user))
      )
    )
  )
)

;; ===========================================
;; Read-Only Functions
;; ===========================================

;; Get project details
(define-read-only (get-project-details (project-id uint))
  (let ((project (map-get? projects { project-id: project-id }))
        (project-contrib (map-get? project-contributions { project-id: project-id })))
    (if (and (is-some project) (is-some project-contrib))
        (ok (merge (unwrap-panic project) 
                  { total-raised: (get total-raised (unwrap-panic project-contrib)) }))
        err-project-not-found)
  )
)

;; Get user contribution and allocation
(define-read-only (get-user-allocation (project-id uint) (user principal))
  (let ((project (map-get? projects { project-id: project-id }))
        (user-contrib (map-get? contributions { project-id: project-id, user: user })))
    (if (and (is-some project) (is-some user-contrib))
        (ok {
          contribution: (get amount (unwrap-panic user-contrib)),
          tokens-claimed: (get tokens-claimed (unwrap-panic user-contrib)),
          token-allocation: (calculate-allocation project-id user)
        })
        err-project-not-found)
  )
)

;; Check if user is whitelisted
(define-read-only (is-whitelisted (project-id uint) (user principal))
  (let ((project (map-get? projects { project-id: project-id }))
        (user-whitelist (map-get? whitelist { project-id: project-id, user: user })))
    (if (is-some project)
        (if (get use-whitelist (unwrap-panic project))
            (if (is-some user-whitelist)
                (get whitelisted (unwrap-panic user-whitelist))
                false)
            true)
        false)
  )
)

;; Get active projects - iterative approach without recursion
(define-read-only (get-active-projects)
  (let ((count (var-get project-count))
        (current-block burn-block-height))
    (fold check-and-collect-project 
          (list u0 u1 u2 u3 u4 u5 u6 u7 u8 u9 u10 u11 u12 u13 u14 u15 u16 u17 u18 u19
                u20 u21 u22 u23 u24 u25 u26 u27 u28 u29 u30 u31 u32 u33 u34 u35 u36 u37 u38 u39
                u40 u41 u42 u43 u44 u45 u46 u47 u48 u49)
          (list))
  )
)

;; Helper function to check and collect active projects
(define-private (check-and-collect-project (project-id uint) (result (list 50 uint)))
  (if (>= project-id (var-get project-count))
    result
    (let ((project (map-get? projects { project-id: project-id }))
          (current-block burn-block-height))
      (if (and (is-some project)
              (is-eq (get status (unwrap-panic project)) status-active)
              (<= current-block (get end-block (unwrap-panic project))))
          (unwrap-panic (as-max-len? (append result project-id) u50))
          result)))
)

;; Calculate current price for Dutch auction
(define-read-only (get-current-price (project-id uint))
  (let ((project (map-get? projects { project-id: project-id })))
    (if (is-some project)
        (let ((project-data (unwrap-panic project)))
          (if (is-eq (get distribution-type project-data) dist-dutch-auction)
              (ok (calculate-dutch-auction-price project-id))
              err-invalid-params))
        err-project-not-found)
  )
)