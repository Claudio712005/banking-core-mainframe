       IDENTIFICATION DIVISION.
       PROGRAM-ID. ACCTPOST.
      *================================================================*
      * PROGRAM  : ACCTPOST                                            *
      * TYPE     : BUSINESS SUBPROGRAM (POSTING ENGINE)                *
      * PURPOSE  : SINGLE IMPLEMENTATION OF A FINANCIAL POSTING        *
      *            (DEPOSIT OR WITHDRAWAL). CALLED ONLY BY THE ENTRY   *
      *            PROGRAMS ACCTDEP AND ACCTWDR.                       *
      * INTERFACE: CALL 'ACCTPOST' USING REQUEST RESPONSE PSTCTL-AREA  *
      *----------------------------------------------------------------*
      * FLOW                                                           *
      *   1000 INITIALIZE                                              *
      *   2000 VALIDATE-INPUT        LAYOUT, OPERATION, FIELDS         *
      *   3000 CHECK-IDEMPOTENCY     SAME KEY + SAME PAYLOAD -> 0001   *
      *                              SAME KEY + OTHER PAYLOAD -> 2007  *
      *   4000 LOAD-ACCOUNT          EXISTS, ACTIVE, SAME CURRENCY,    *
      *                              CUSTOMER ACTIVE                   *
      *   5000 APPLY-BUSINESS-RULE   NEW BALANCE, FUNDS, LIMITS        *
      *   6000 PERSIST-POSTING       UPDATE ACCOUNT + INSERT JOURNAL   *
      *   8000 BUILD-RESPONSE                                          *
      *   9000 FINALIZE                                                *
      * EACH STEP RUNS ONLY WHILE THE RESPONSE CODE IS STILL 0000.     *
      *----------------------------------------------------------------*
      * ATOMICITY                                                      *
      *   Z/OS: STEPS 6100 AND 6200 FORM ONE UNIT OF WORK. ON FAILURE  *
      *         THE TRANSACTION ISSUES EXEC CICS SYNCPOINT ROLLBACK    *
      *         AND 6300-COMPENSATE-ACCOUNT IS REMOVED.                *
      *   LAB : NO TRANSACTION MANAGER EXISTS. IF THE JOURNAL INSERT   *
      *         FAILS AFTER THE ACCOUNT UPDATE, 6300 RESTORES THE      *
      *         PREVIOUS BALANCE. IF THAT ALSO FAILS THE RESULT IS     *
      *         9003 (STATE UNCERTAIN, MANUAL RECONCILIATION).         *
      *================================================================*
       ENVIRONMENT DIVISION.

       DATA DIVISION.
       WORKING-STORAGE SECTION.
       01  WS-PROGRAM-NAMES.
           05  WS-THIS-PROGRAM              PIC X(08) VALUE 'ACCTPOST'.
           05  WS-PGM-VALIDATOR             PIC X(08) VALUE 'BKVALID'.
           05  WS-PGM-RESPONSE-BUILDER      PIC X(08) VALUE 'BKRESP'.
           05  WS-PGM-ACCOUNT-DAO           PIC X(08) VALUE 'ACCTDAO'.
           05  WS-PGM-TRANSACTION-DAO       PIC X(08) VALUE 'TRXDAO'.

       01  WS-CONSTANTS.
           05  WS-REASON-MODULE-MISSING     PIC X(08) VALUE 'NOMODULE'.

       01  WS-RESULT.
           COPY RSPCODE REPLACING ==:TAG:== BY ==WS==.

       01  WS-TECH-CODE                     PIC X(08).

       01  WS-RESPONSE-CONTROL.
           COPY RSPCTL REPLACING ==:TAG:== BY ==RCT==.

       01  WS-VALIDATION.
           COPY VALCTL REPLACING ==:TAG:== BY ==VAL==.

       01  WS-DAO-CONTROL.
           COPY DAOCTL REPLACING ==:TAG:== BY ==DAO==.

      *    ACCOUNT AS CURRENTLY STORED / TO BE STORED
       01  WS-ACCOUNT.
           COPY ACCOUNT REPLACING ==:TAG:== BY ==ACC==.

      *    ACCOUNT IMAGE BEFORE POSTING (LAB COMPENSATION ONLY)
       01  WS-ACCOUNT-BEFORE.
           COPY ACCOUNT REPLACING ==:TAG:== BY ==BFR==.

      *    NEW POSTING, OR THE ORIGINAL ONE WHEN A REQUEST IS REPLAYED
       01  WS-TRANSACTION.
           COPY TRANSACT REPLACING ==:TAG:== BY ==TRX==.

      *    MONETARY ARITHMETIC IS DONE ONLY ON PACKED DECIMAL FIELDS
       01  WS-MONETARY-WORK.
           05  WS-POSTING-AMOUNT            PIC S9(13)V99 COMP-3.
           05  WS-CURRENT-BALANCE           PIC S9(13)V99 COMP-3.
           05  WS-NEW-BALANCE               PIC S9(13)V99 COMP-3.

      *    FUNCTION CURRENT-DATE LAYOUT (21 CHARACTERS)
       01  WS-CURRENT-DATE-DATA.
           05  WS-CD-YEAR                   PIC X(04).
           05  WS-CD-MONTH                  PIC X(02).
           05  WS-CD-DAY                    PIC X(02).
           05  WS-CD-HOUR                   PIC X(02).
           05  WS-CD-MINUTE                 PIC X(02).
           05  WS-CD-SECOND                 PIC X(02).
           05  WS-CD-HUNDREDTHS             PIC X(02).
           05  WS-CD-UTC-OFFSET             PIC X(05).

      *    DB2 TIMESTAMP FORMAT YYYY-MM-DD-HH.MM.SS.NNNNNN
       01  WS-POSTING-TIMESTAMP             PIC X(26).

       LINKAGE SECTION.
       01  LK-REQUEST.
           COPY REQUEST.
       01  LK-RESPONSE.
           COPY RESPONSE.
       01  LK-POSTING-CONTROL.
           COPY PSTCTL REPLACING ==:TAG:== BY ==PST==.

       PROCEDURE DIVISION USING LK-REQUEST
                                LK-RESPONSE
                                LK-POSTING-CONTROL.
      *================================================================*
       0000-MAIN.
           PERFORM 1000-INITIALIZE
           PERFORM 2000-VALIDATE-INPUT
           IF WS-RC-SUCCESS
               PERFORM 3000-CHECK-IDEMPOTENCY
           END-IF
           IF WS-RC-SUCCESS
               PERFORM 4000-LOAD-ACCOUNT
           END-IF
           IF WS-RC-SUCCESS
               PERFORM 5000-APPLY-BUSINESS-RULE
           END-IF
           IF WS-RC-SUCCESS
               PERFORM 6000-PERSIST-POSTING
           END-IF
           PERFORM 8000-BUILD-RESPONSE
           PERFORM 9000-FINALIZE
           GOBACK
           .

      *================================================================*
       1000-INITIALIZE.
           SET WS-RC-SUCCESS TO TRUE
           MOVE SPACES TO WS-TECH-CODE
           INITIALIZE WS-VALIDATION
                      WS-DAO-CONTROL
                      WS-ACCOUNT
                      WS-ACCOUNT-BEFORE
                      WS-TRANSACTION
                      WS-MONETARY-WORK
                      WITH FILLER
           PERFORM 1100-CAPTURE-TIMESTAMP
           INITIALIZE WS-RESPONSE-CONTROL
           SET RCT-FN-INIT TO TRUE
           PERFORM 8900-CALL-RESPONSE-BUILDER
           .

      *    ONE TIMESTAMP PER POSTING, SHARED BY ACCOUNT AND JOURNAL.
      *    Z/OS: USE DB2 CURRENT TIMESTAMP INSIDE THE UNIT OF WORK.
       1100-CAPTURE-TIMESTAMP.
           MOVE FUNCTION CURRENT-DATE TO WS-CURRENT-DATE-DATA
           STRING WS-CD-YEAR       '-'
                  WS-CD-MONTH      '-'
                  WS-CD-DAY        '-'
                  WS-CD-HOUR       '.'
                  WS-CD-MINUTE     '.'
                  WS-CD-SECOND     '.'
                  WS-CD-HUNDREDTHS '0000'
                  DELIMITED BY SIZE
                  INTO WS-POSTING-TIMESTAMP
           END-STRING
           .

      *================================================================*
      * 2000 - INPUT VALIDATION (NOTHING FROM THE REQUEST IS TRUSTED)  *
      *================================================================*
       2000-VALIDATE-INPUT.
           EVALUATE TRUE
               WHEN NOT REQ-LAYOUT-V01
                   SET WS-RC-INVALID-REQUEST TO TRUE
               WHEN PST-DEPOSIT    AND REQ-OP-DEPOSIT
               WHEN PST-WITHDRAWAL AND REQ-OP-WITHDRAWAL
                   CONTINUE
               WHEN OTHER
                   SET WS-RC-INVALID-REQUEST TO TRUE
           END-EVALUATE
           IF WS-RC-SUCCESS
               SET VAL-FN-ACCOUNT-ID TO TRUE
               MOVE REQ-PO-ACCOUNT-ID TO VAL-FIELD
               PERFORM 2900-CALL-VALIDATOR
           END-IF
           IF WS-RC-SUCCESS
               SET VAL-FN-AMOUNT TO TRUE
               MOVE REQ-PO-AMOUNT-X TO VAL-FIELD
               PERFORM 2900-CALL-VALIDATOR
           END-IF
           IF WS-RC-SUCCESS
               SET VAL-FN-CURRENCY TO TRUE
               MOVE REQ-PO-CURRENCY TO VAL-FIELD
               PERFORM 2900-CALL-VALIDATOR
           END-IF
           IF WS-RC-SUCCESS
               SET VAL-FN-IDEMPOTENCY-KEY TO TRUE
               MOVE REQ-PO-IDEMPOTENCY-KEY TO VAL-FIELD
               PERFORM 2900-CALL-VALIDATOR
           END-IF
           IF WS-RC-SUCCESS
               MOVE REQ-PO-AMOUNT TO WS-POSTING-AMOUNT
           END-IF
           .

       2900-CALL-VALIDATOR.
           CALL WS-PGM-VALIDATOR USING WS-VALIDATION
               ON EXCEPTION
                   SET WS-RC-UNEXPECTED-ERROR TO TRUE
                   MOVE WS-REASON-MODULE-MISSING TO WS-TECH-CODE
               NOT ON EXCEPTION
                   MOVE VAL-RESULT-CODE TO WS-RESPONSE-CODE
           END-CALL
           .

      *================================================================*
      * 3000 - IDEMPOTENCY                                             *
      * A KEY IDENTIFIES ONE FINANCIAL INTENT. A RETRY WITH THE SAME   *
      * KEY AND PAYLOAD RETURNS THE ORIGINAL RESULT (0001) AND MOVES   *
      * NO MONEY. THE SAME KEY WITH A DIFFERENT PAYLOAD IS REJECTED.   *
      *================================================================*
       3000-CHECK-IDEMPOTENCY.
           MOVE REQ-PO-IDEMPOTENCY-KEY TO TRX-IDEMPOTENCY-KEY
           INITIALIZE WS-DAO-CONTROL
           SET DAO-FN-FIND-BY-KEY TO TRUE
           PERFORM 7300-CALL-TRANSACTION-DAO
           EVALUATE TRUE
               WHEN DAO-ST-NOT-FOUND
                   INITIALIZE WS-TRANSACTION WITH FILLER
               WHEN DAO-ST-OK
                   PERFORM 3100-EVALUATE-PRIOR-POSTING
               WHEN OTHER
                   PERFORM 7900-HANDLE-DAO-FAILURE
           END-EVALUATE
           .

       3100-EVALUATE-PRIOR-POSTING.
           IF  TRX-ACCOUNT-ID       = REQ-PO-ACCOUNT-ID
           AND TRX-TRANSACTION-TYPE = PST-POSTING-TYPE
           AND TRX-AMOUNT           = WS-POSTING-AMOUNT
           AND TRX-CURRENCY         = REQ-PO-CURRENCY
               SET WS-RC-DUPLICATE-REPLAYED TO TRUE
           ELSE
               SET WS-RC-IDEMP-KEY-CONFLICT TO TRUE
           END-IF
           .

      *================================================================*
      * 4000 - ACCOUNT AND CUSTOMER STATE                              *
      *================================================================*
       4000-LOAD-ACCOUNT.
           MOVE REQ-PO-ACCOUNT-ID TO ACC-ACCOUNT-ID
           INITIALIZE WS-DAO-CONTROL
           SET DAO-FN-READ TO TRUE
           PERFORM 7100-CALL-ACCOUNT-DAO
           EVALUATE TRUE
               WHEN DAO-ST-OK
                   PERFORM 4100-CHECK-ACCOUNT-STATE
               WHEN DAO-ST-NOT-FOUND
                   SET WS-RC-ACCOUNT-NOT-FOUND TO TRUE
               WHEN OTHER
                   PERFORM 7900-HANDLE-DAO-FAILURE
           END-EVALUATE
           .

       4100-CHECK-ACCOUNT-STATE.
           EVALUATE TRUE
               WHEN NOT ACC-STATUS-ACTIVE
                   SET WS-RC-ACCOUNT-NOT-ACTIVE TO TRUE
               WHEN NOT ACC-CUSTOMER-ACTIVE
                   SET WS-RC-CUSTOMER-NOT-ACTIVE TO TRUE
               WHEN ACC-CURRENCY NOT = REQ-PO-CURRENCY
                   SET WS-RC-CURRENCY-MISMATCH TO TRUE
               WHEN OTHER
                   MOVE WS-ACCOUNT TO WS-ACCOUNT-BEFORE
           END-EVALUATE
           .

      *================================================================*
      * 5000 - BUSINESS RULE                                           *
      * THE STORED BALANCE IS NEVER NEGATIVE (ACCTDAO GUARANTEES IT)   *
      * AND THE NEW BALANCE IS CHECKED AGAIN BEFORE PERSISTING.        *
      *================================================================*
       5000-APPLY-BUSINESS-RULE.
           MOVE ACC-BALANCE TO WS-CURRENT-BALANCE
           EVALUATE TRUE
               WHEN PST-DEPOSIT
                   PERFORM 5100-COMPUTE-DEPOSIT
               WHEN PST-WITHDRAWAL
                   PERFORM 5200-COMPUTE-WITHDRAWAL
               WHEN OTHER
                   SET WS-RC-UNEXPECTED-ERROR TO TRUE
           END-EVALUATE
           IF WS-RC-SUCCESS AND WS-NEW-BALANCE < ZERO
               SET WS-RC-DATA-INTEGRITY-ERROR TO TRUE
           END-IF
           .

       5100-COMPUTE-DEPOSIT.
           ADD WS-POSTING-AMOUNT TO WS-CURRENT-BALANCE
               GIVING WS-NEW-BALANCE
               ON SIZE ERROR
                   SET WS-RC-BALANCE-LIMIT TO TRUE
           END-ADD
           .

       5200-COMPUTE-WITHDRAWAL.
           IF WS-POSTING-AMOUNT > WS-CURRENT-BALANCE
               SET WS-RC-INSUFFICIENT-FUNDS TO TRUE
           ELSE
               SUBTRACT WS-POSTING-AMOUNT FROM WS-CURRENT-BALANCE
                   GIVING WS-NEW-BALANCE
               END-SUBTRACT
           END-IF
           .

      *================================================================*
      * 6000 - PERSISTENCE (ONE LOGICAL UNIT OF WORK, SEE HEADER)      *
      *================================================================*
       6000-PERSIST-POSTING.
           PERFORM 6100-UPDATE-ACCOUNT
           IF WS-RC-SUCCESS
               PERFORM 6200-RECORD-TRANSACTION
           END-IF
           .

       6100-UPDATE-ACCOUNT.
           MOVE WS-NEW-BALANCE       TO ACC-BALANCE
           MOVE WS-POSTING-TIMESTAMP TO ACC-LAST-UPDATE-TS
           INITIALIZE WS-DAO-CONTROL
           SET DAO-FN-UPDATE TO TRUE
           PERFORM 7100-CALL-ACCOUNT-DAO
           EVALUATE TRUE
               WHEN DAO-ST-OK
                   CONTINUE
               WHEN DAO-ST-VERSION-CONFLICT
               WHEN DAO-ST-NOT-FOUND
                   SET WS-RC-CONCURRENT-UPDATE TO TRUE
                   MOVE DAO-STATUS TO WS-TECH-CODE
               WHEN OTHER
                   PERFORM 7900-HANDLE-DAO-FAILURE
           END-EVALUATE
           .

      *    A DUPLICATE HERE MEANS A CONCURRENT REQUEST WITH THE SAME
      *    KEY WON THE RACE: UNDO, AND LET THE CLIENT RETRY (-> 0001).
       6200-RECORD-TRANSACTION.
           INITIALIZE WS-TRANSACTION WITH FILLER
           MOVE ACC-ACCOUNT-ID         TO TRX-ACCOUNT-ID
           MOVE PST-POSTING-TYPE       TO TRX-TRANSACTION-TYPE
           MOVE WS-POSTING-AMOUNT      TO TRX-AMOUNT
           MOVE ACC-CURRENCY           TO TRX-CURRENCY
           SET TRX-STATUS-COMPLETED    TO TRUE
           MOVE WS-POSTING-TIMESTAMP   TO TRX-TRANSACTION-TS
           MOVE REQ-PO-IDEMPOTENCY-KEY TO TRX-IDEMPOTENCY-KEY
           MOVE WS-NEW-BALANCE         TO TRX-BALANCE-AFTER
           INITIALIZE WS-DAO-CONTROL
           SET DAO-FN-INSERT TO TRUE
           PERFORM 7300-CALL-TRANSACTION-DAO
           EVALUATE TRUE
               WHEN DAO-ST-OK
                   CONTINUE
               WHEN DAO-ST-DUPLICATE
                   SET WS-RC-CONCURRENT-UPDATE TO TRUE
                   MOVE DAO-STATUS TO WS-TECH-CODE
               WHEN OTHER
                   PERFORM 7900-HANDLE-DAO-FAILURE
           END-EVALUATE
           IF NOT WS-RC-SUCCESS
               PERFORM 6300-COMPENSATE-ACCOUNT
           END-IF
           .

      *    *** LAB ONLY *** REPLACED BY SYNCPOINT ROLLBACK ON Z/OS.
      *    WS-ACCOUNT HOLDS THE UPDATED IMAGE WITH ITS NEW VERSION.
       6300-COMPENSATE-ACCOUNT.
           MOVE BFR-BALANCE TO ACC-BALANCE
           INITIALIZE WS-DAO-CONTROL
           SET DAO-FN-UPDATE TO TRUE
           PERFORM 7100-CALL-ACCOUNT-DAO
           IF NOT DAO-ST-OK
               SET WS-RC-POSTING-INCOMPLETE TO TRUE
               MOVE DAO-TECH-CODE TO WS-TECH-CODE
           END-IF
           .

      *================================================================*
      * 7000 - DATA ACCESS CALLS                                       *
      * A MISSING MODULE IS REPORTED AS AN I/O FAILURE (FAIL-SAFE).    *
      *================================================================*
       7100-CALL-ACCOUNT-DAO.
           CALL WS-PGM-ACCOUNT-DAO USING WS-DAO-CONTROL
                                         WS-ACCOUNT
               ON EXCEPTION
                   PERFORM 7800-SET-MODULE-MISSING
           END-CALL
           .

       7300-CALL-TRANSACTION-DAO.
           CALL WS-PGM-TRANSACTION-DAO USING WS-DAO-CONTROL
                                             WS-TRANSACTION
               ON EXCEPTION
                   PERFORM 7800-SET-MODULE-MISSING
           END-CALL
           .

       7800-SET-MODULE-MISSING.
           SET DAO-ST-IO-ERROR TO TRUE
           MOVE WS-REASON-MODULE-MISSING TO DAO-TECH-CODE
           .

       7900-HANDLE-DAO-FAILURE.
           MOVE DAO-TECH-CODE TO WS-TECH-CODE
           EVALUATE TRUE
               WHEN DAO-ST-DATA-ERROR
                   SET WS-RC-DATA-INTEGRITY-ERROR TO TRUE
               WHEN DAO-ST-IO-ERROR
                   SET WS-RC-DATA-ACCESS-ERROR TO TRUE
               WHEN OTHER
                   SET WS-RC-UNEXPECTED-ERROR TO TRUE
           END-EVALUATE
           .

      *================================================================*
      * 8000 - RESPONSE                                                *
      * A REPLAY RETURNS THE ORIGINAL POSTING FROM THE JOURNAL.        *
      *================================================================*
       8000-BUILD-RESPONSE.
           IF WS-RC-SUCCESS OR WS-RC-DUPLICATE-REPLAYED
               MOVE TRX-TRANSACTION-ID   TO RSP-PO-TRANSACTION-ID
               MOVE TRX-ACCOUNT-ID       TO RSP-PO-ACCOUNT-ID
               MOVE TRX-TRANSACTION-TYPE TO RSP-PO-TRANSACTION-TYPE
               MOVE TRX-AMOUNT           TO RSP-PO-AMOUNT
               MOVE TRX-BALANCE-AFTER    TO RSP-PO-NEW-BALANCE
               MOVE TRX-CURRENCY         TO RSP-PO-CURRENCY
               MOVE TRX-TRANSACTION-TS   TO RSP-PO-TRANSACTION-TS
           END-IF
           .

       8900-CALL-RESPONSE-BUILDER.
           MOVE WS-THIS-PROGRAM  TO RCT-PROGRAM-ID
           MOVE WS-RESPONSE-CODE TO RCT-RESPONSE-CODE
           MOVE WS-TECH-CODE     TO RCT-TECH-CODE
           CALL WS-PGM-RESPONSE-BUILDER USING WS-RESPONSE-CONTROL
                                              LK-REQUEST
                                              LK-RESPONSE
               ON EXCEPTION
                   MOVE SPACES TO LK-RESPONSE
           END-CALL
           .

      *================================================================*
       9000-FINALIZE.
           SET RCT-FN-FINISH TO TRUE
           PERFORM 8900-CALL-RESPONSE-BUILDER
           .
