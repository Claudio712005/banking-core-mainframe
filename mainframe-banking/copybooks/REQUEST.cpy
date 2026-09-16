      *================================================================*
      * COPYBOOK : REQUEST                                             *
      * PURPOSE  : INBOUND MESSAGE CONTRACT (JAVA -> MQ -> COBOL).     *
      *            ONE FIXED-LENGTH HEADER + ONE OPERATION BODY.       *
      * LENGTH   : 200 BYTES, CHARACTER DATA ONLY (NO BINARY/PACKED),  *
      *            SO MQ/CICS CODE PAGE CONVERSION IS SAFE.            *
      * VERSION  : LAYOUT 01. ANY INCOMPATIBLE CHANGE REQUIRES A NEW   *
      *            LAYOUT VERSION. NEW FIELDS ONLY CONSUME FILLER.     *
      * USAGE    : 01  LK-REQUEST.                                     *
      *                COPY REQUEST.                                   *
      * CONTRACT : DOCS/CONTRACT.MD (AUTHORITATIVE FIELD REFERENCE).   *
      *----------------------------------------------------------------*
      * HEADER               POS  LEN  REQ  NOTES                      *
      * LAYOUT-VERSION         1    2   Y   '01'                       *
      * OPERATION-CODE         3    8   Y   ACCTINQ ACCTDEP ACCTWDR    *
      *                                     TRXINQ (LEFT-JUSTIFIED)    *
      * CORRELATION-ID        11   36   N   OPAQUE, ECHOED BACK        *
      * FILLER                47    4       RESERVED                   *
      * BODY                  51  150   Y   SEE REDEFINES BELOW        *
      *================================================================*
           05  REQ-HEADER.
               10  REQ-LAYOUT-VERSION       PIC X(02).
                   88  REQ-LAYOUT-V01                VALUE '01'.
               10  REQ-OPERATION-CODE       PIC X(08).
                   88  REQ-OP-ACCOUNT-INQUIRY        VALUE 'ACCTINQ '.
                   88  REQ-OP-DEPOSIT                VALUE 'ACCTDEP '.
                   88  REQ-OP-WITHDRAWAL             VALUE 'ACCTWDR '.
                   88  REQ-OP-TRANSACTION-INQUIRY    VALUE 'TRXINQ  '.
               10  REQ-CORRELATION-ID       PIC X(36).
               10  FILLER                   PIC X(04).
           05  REQ-BODY                     PIC X(150).
      *----------------------------------------------------------------*
      * BODY FOR ACCTINQ                     POS  LEN  REQ             *
      *   ACCOUNT-ID                          51   10   Y              *
      *----------------------------------------------------------------*
           05  REQ-ACCOUNT-INQUIRY REDEFINES REQ-BODY.
               10  REQ-AI-ACCOUNT-ID        PIC X(10).
               10  FILLER                   PIC X(140).
      *----------------------------------------------------------------*
      * BODY FOR ACCTDEP / ACCTWDR           POS  LEN  REQ             *
      *   ACCOUNT-ID                          51   10   Y              *
      *   AMOUNT  (SIGN + 15 DIGITS, V99)     61   16   Y  > 0         *
      *   CURRENCY (ISO 4217)                 77    3   Y              *
      *   IDEMPOTENCY-KEY                     80   36   Y  16..36 CHARS*
      *----------------------------------------------------------------*
           05  REQ-POSTING REDEFINES REQ-BODY.
               10  REQ-PO-ACCOUNT-ID        PIC X(10).
               10  REQ-PO-AMOUNT            PIC S9(13)V99
                                            SIGN LEADING SEPARATE.
               10  REQ-PO-AMOUNT-X REDEFINES REQ-PO-AMOUNT
                                            PIC X(16).
               10  REQ-PO-CURRENCY          PIC X(03).
               10  REQ-PO-IDEMPOTENCY-KEY   PIC X(36).
               10  FILLER                   PIC X(85).
      *----------------------------------------------------------------*
      * BODY FOR TRXINQ                      POS  LEN  REQ             *
      *   TRANSACTION-ID                      51   16   Y              *
      *----------------------------------------------------------------*
           05  REQ-TRANSACTION-INQUIRY REDEFINES REQ-BODY.
               10  REQ-TI-TRANSACTION-ID    PIC X(16).
               10  FILLER                   PIC X(134).
