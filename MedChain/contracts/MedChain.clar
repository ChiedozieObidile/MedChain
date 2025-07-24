;; MedChain - Healthcare Device Lifecycle Management Protocol
;; Enables transparent tracking of medical device lifecycle and regulatory compliance

(define-trait healthcare-device-management-trait
  (
    (register-medical-device (uint uint) (response bool uint))
    (update-lifecycle-status (uint uint) (response bool uint))
    (get-device-audit-trail (uint) (response (list 10 {status: uint, timestamp: uint}) uint))
    (issue-regulatory-certification (uint uint principal) (response bool uint))
    (validate-device-compliance (uint uint) (response bool uint))
  )
)

;; Define device lifecycle status constants
(define-constant LIFECYCLE_MANUFACTURED u1)
(define-constant LIFECYCLE_QUALITY_TESTING u2)
(define-constant LIFECYCLE_DEPLOYED u3)
(define-constant LIFECYCLE_MAINTENANCE u4)

;; Define regulatory certification type constants
(define-constant CERTIFICATION_FDA u1)
(define-constant CERTIFICATION_CE_MARK u2)
(define-constant CERTIFICATION_ISO_13485 u3)
(define-constant CERTIFICATION_SAFETY_STANDARD u4)

;; Error constants
(define-constant ERR_ACCESS_DENIED (err u1))
(define-constant ERR_DEVICE_NOT_FOUND (err u2))
(define-constant ERR_STATUS_UPDATE_FAILED (err u3))
(define-constant ERR_INVALID_LIFECYCLE_STATUS (err u4))
(define-constant ERR_INVALID_CERTIFICATION_TYPE (err u5))
(define-constant ERR_CERTIFICATION_ALREADY_EXISTS (err u6))

;; Protocol administrator
(define-data-var protocol-admin principal tx-sender)

;; Global timestamp counter for audit trail
(define-data-var audit-timestamp-counter uint u0)

;; Healthcare device registry
(define-map healthcare-device-registry
  {device-id: uint} 
  {
    manufacturer: principal,
    current-lifecycle-status: uint,
    audit-trail: (list 10 {status: uint, timestamp: uint})
  }
)

;; Regulatory certification registry
(define-map regulatory-certification-registry
  {device-id: uint, certification-type: uint}
  {
    certifying-authority: principal,
    issuance-timestamp: uint,
    certification-valid: bool
  }
)

;; Approved regulatory authorities
(define-map authorized-regulatory-bodies
  {authority: principal, certification-type: uint}
  {authorized: bool}
)

;; Generate audit timestamp and increment counter
(define-private (generate-audit-timestamp)
  (begin
    (var-set audit-timestamp-counter (+ (var-get audit-timestamp-counter) u1))
    (var-get audit-timestamp-counter)
  )
)

;; Check if sender is protocol administrator
(define-read-only (is-protocol-admin (sender principal))
  (is-eq sender (var-get protocol-admin))
)

;; Validate lifecycle status
(define-private (is-valid-lifecycle-status (status uint))
  (or 
    (is-eq status LIFECYCLE_MANUFACTURED)
    (is-eq status LIFECYCLE_QUALITY_TESTING)
    (is-eq status LIFECYCLE_DEPLOYED)
    (is-eq status LIFECYCLE_MAINTENANCE)
  )
)

;; Validate certification type
(define-private (is-valid-certification-type (cert-type uint))
  (or
    (is-eq cert-type CERTIFICATION_FDA)
    (is-eq cert-type CERTIFICATION_CE_MARK)
    (is-eq cert-type CERTIFICATION_ISO_13485)
    (is-eq cert-type CERTIFICATION_SAFETY_STANDARD)
  )
)

;; Validate device identifier
(define-private (is-valid-device-identifier (device-id uint))
  (and (> device-id u0) (<= device-id u1000000))
)

;; Check if sender is authorized regulatory body
(define-private (is-authorized-regulatory-body (authority principal) (cert-type uint))
  (default-to 
    false
    (get authorized (map-get? authorized-regulatory-bodies {authority: authority, certification-type: cert-type}))
  )
)

;; Register a new healthcare device
(define-public (register-medical-device (device-id uint) (initial-status uint))
  (begin
    (asserts! (is-valid-device-identifier device-id) ERR_DEVICE_NOT_FOUND)
    (asserts! (is-valid-lifecycle-status initial-status) ERR_INVALID_LIFECYCLE_STATUS)
    (asserts! (or (is-protocol-admin tx-sender) (is-eq initial-status LIFECYCLE_MANUFACTURED)) ERR_ACCESS_DENIED)
    
    (map-set healthcare-device-registry
      {device-id: device-id}
      {
        manufacturer: tx-sender,
        current-lifecycle-status: initial-status,
        audit-trail: (list {status: initial-status, timestamp: (generate-audit-timestamp)})
      }
    )
    (ok true)
  )
)

;; Update device lifecycle status
(define-public (update-lifecycle-status (device-id uint) (new-status uint))
  (let 
    (
      (device-record (unwrap! (map-get? healthcare-device-registry {device-id: device-id}) ERR_DEVICE_NOT_FOUND))
    )
    (asserts! (is-valid-device-identifier device-id) ERR_DEVICE_NOT_FOUND)
    (asserts! (is-valid-lifecycle-status new-status) ERR_INVALID_LIFECYCLE_STATUS)
    (asserts! 
      (or 
        (is-protocol-admin tx-sender)
        (is-eq (get manufacturer device-record) tx-sender)
      ) 
      ERR_ACCESS_DENIED
    )
    
    (map-set healthcare-device-registry
      {device-id: device-id}
      (merge device-record 
        {
          current-lifecycle-status: new-status,
          audit-trail: (unwrap-panic 
            (as-max-len? 
              (append (get audit-trail device-record) {status: new-status, timestamp: (generate-audit-timestamp)}) 
              u10
            )
          )
        }
      )
    )
    (ok true)
  )
)

;; Validate regulatory authority principal
(define-private (is-valid-regulatory-authority (authority principal))
  (and 
    (not (is-eq authority (var-get protocol-admin)))  ;; Authority can't be protocol admin
    (not (is-eq authority tx-sender))                 ;; Authority can't be the sender
    (not (is-eq authority 'SP000000000000000000002Q6VF78))  ;; Not zero address
  )
)

;; Add authorized regulatory body with validation
(define-public (authorize-regulatory-body (authority principal) (cert-type uint))
  (begin
    (asserts! (is-protocol-admin tx-sender) ERR_ACCESS_DENIED)
    (asserts! (is-valid-certification-type cert-type) ERR_INVALID_CERTIFICATION_TYPE)
    (asserts! (is-valid-regulatory-authority authority) ERR_ACCESS_DENIED)
    
    ;; After validation, authorize the regulatory body
    (map-set authorized-regulatory-bodies
      {authority: authority, certification-type: cert-type}
      {authorized: true}
    )
    (ok true)
  )
)

;; Issue regulatory certification to device
(define-public (issue-regulatory-certification (device-id uint) (cert-type uint))
  (begin
    (asserts! (is-valid-device-identifier device-id) ERR_DEVICE_NOT_FOUND)
    (asserts! (is-valid-certification-type cert-type) ERR_INVALID_CERTIFICATION_TYPE)
    (asserts! (is-authorized-regulatory-body tx-sender cert-type) ERR_ACCESS_DENIED)
    
    (asserts! 
      (is-none 
        (map-get? regulatory-certification-registry {device-id: device-id, certification-type: cert-type})
      )
      ERR_CERTIFICATION_ALREADY_EXISTS
    )
    
    (let
      ((validated-device-id device-id)
       (validated-cert-type cert-type))
      (map-set regulatory-certification-registry
        {device-id: validated-device-id, certification-type: validated-cert-type}
        {
          certifying-authority: tx-sender,
          issuance-timestamp: (generate-audit-timestamp),
          certification-valid: true
        }
      )
      (ok true)
    )
  )
)

;; Validate device regulatory compliance
(define-read-only (validate-device-compliance (device-id uint) (cert-type uint))
  (let
    (
      (certification-record (unwrap! 
        (map-get? regulatory-certification-registry {device-id: device-id, certification-type: cert-type})
        ERR_INVALID_CERTIFICATION_TYPE
      ))
    )
    (ok (get certification-valid certification-record))
  )
)

;; Revoke regulatory certification
(define-public (revoke-regulatory-certification (device-id uint) (cert-type uint))
  (begin
    (asserts! (is-valid-device-identifier device-id) ERR_DEVICE_NOT_FOUND)
    (asserts! (is-valid-certification-type cert-type) ERR_INVALID_CERTIFICATION_TYPE)
    
    (let
      (
        (certification-record (unwrap! 
          (map-get? regulatory-certification-registry {device-id: device-id, certification-type: cert-type})
          ERR_INVALID_CERTIFICATION_TYPE
        ))
        (validated-device-id device-id)
        (validated-cert-type cert-type)
      )
      (asserts! 
        (or
          (is-protocol-admin tx-sender)
          (is-eq (get certifying-authority certification-record) tx-sender)
        )
        ERR_ACCESS_DENIED
      )
      
      (map-set regulatory-certification-registry
        {device-id: validated-device-id, certification-type: validated-cert-type}
        (merge certification-record {certification-valid: false})
      )
      (ok true)
    )
  )
)

;; Get device audit trail
(define-read-only (get-device-audit-trail (device-id uint))
  (let 
    (
      (device-record (unwrap! (map-get? healthcare-device-registry {device-id: device-id}) ERR_DEVICE_NOT_FOUND))
    )
    (ok (get audit-trail device-record))
  )
)

;; Get current device lifecycle status
(define-read-only (get-device-lifecycle-status (device-id uint))
  (let 
    (
      (device-record (unwrap! (map-get? healthcare-device-registry {device-id: device-id}) ERR_DEVICE_NOT_FOUND))
    )
    (ok (get current-lifecycle-status device-record))
  )
)

;; Get certification record details
(define-read-only (get-certification-record (device-id uint) (cert-type uint))
  (ok (map-get? regulatory-certification-registry {device-id: device-id, certification-type: cert-type}))
)