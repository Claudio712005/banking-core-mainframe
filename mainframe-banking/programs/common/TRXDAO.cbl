       IDENTIFICATION DIVISION.
       PROGRAM-ID. TRXDAO.
      *================================================================*
      * PROGRAM  : TRXDAO                                              *
      * TYPE     : DATA ACCESS MODULE - *** LAB IMPLEMENTATION ***     *
      * PURPOSE  : ACCESS TO THE FINANCIAL TRANSACTION JOURNAL.        *
      * INTERFACE: CALL 'TRXDAO' USING DAOCTL-AREA TRANSACTION-RECORD  *
      *   READ    : IN  TRANSACTION-ID       OUT FULL RECORD           *
      *   FINDKEY : IN  IDEMPOTENCY-KEY      OUT FULL RECORD           *
      *   INSERT  : IN  RECORD WITHOUT ID    OUT ASSIGNED ID           *
      *             DUPLICATE WHEN IDEMPOTENCY-KEY ALREADY EXISTS.     *
      *----------------------------------------------------------------*
      * LAB STORAGE : DD TRXJRNL, LINE SEQUENTIAL, APPEND-ONLY         *
      *               (ENV DD_TRXJRNL). EVERY CALL SCANS THE FILE.     *
      *               ID = HIGHEST EXISTING ID + 1.                    *
      *               A MISSING FILE IS TREATED AS AN EMPTY JOURNAL.   *
      *               BLANK OR MALFORMED LINES STOP INSERTS (FAIL-SAFE)*
      * Z/OS        : TABLE ACCOUNT_TRANSACTION                        *
      *   READ    : SELECT ... WHERE TRANSACTION_ID = :ID              *
      *   FINDKEY : SELECT ... WHERE IDEMPOTENCY_KEY = :KEY            *
      *   INSERT  : ID FROM A DB2 SEQUENCE (NEXT VALUE FOR ...);       *
      *             UNIQUE INDEX ON IDEMPOTENCY_KEY,                   *
      *             SQLCODE -803 -> DUPLICATE.                         *
      *================================================================*
       ENVIRONMENT DIVISION.
       INPUT-OUTPUT SECTION.
       FILE-CONTROL.
           SELECT OPTIONAL TRANSACTION-JOURNAL-FILE
               ASSIGN TO TRXJRNL
               ORGANIZATION IS LINE SEQUENTIAL
               FILE STATUS IS WS-JOURNAL-FILE-STATUS.

       DATA DIVISION.
       FILE SECTION.
       FD  TRANSACTION-JOURNAL-FILE.
       01  TRANSACTION-JOURNAL-RECORD       PIC X(150).

       WORKING-STORAGE SECTION.
       01  WS-CONSTANTS.
           05  WS-REASON-BAD-RECORD         PIC X(08) VALUE 'BADREC'.
           05  WS-REASON-ID-EXHAUSTED       PIC X(08) VALUE 'IDEXHAUS'.

       01  WS-FILE-STATUSES.
           05  WS-JOURNAL-FILE-STATUS       PIC X(02).
               88  WS-JOURNAL-OK                     VALUE '00'.
               88  WS-JOURNAL-END-OF-FILE            VALUE '10'.
               88  WS-JOURNAL-OPTIONAL-MISSING       VALUE '05'.

       01  WS-CONTROL-FLAGS.
           05  WS-SCAN-FLAG                 PIC X(01).
               88  WS-SCAN-IN-PROGRESS               VALUE 'N'.
               88  WS-SCAN-FINISHED                  VALUE 'Y'.
           05  WS-FOUND-FLAG                PIC X(01).
               88  WS-TRANSACTION-NOT-LOCATED        VALUE 'N'.
               88  WS-TRANSACTION-LOCATED            VALUE 'Y'.
           05  WS-RECORD-CHECK-FLAG         PIC X(01).
               88  WS-RECORD-VALID                   VALUE 'Y'.
               88  WS-RECORD-INVALID                 VALUE 'N'.
           05  WS-JOURNAL-FILE-FLAG         PIC X(01).
               88  WS-JOURNAL-FILE-CLOSED            VALUE 'N'.
               88  WS-JOURNAL-FILE-OPEN              VALUE 'Y'.

       01  WS-ID-WORK.
           05  WS-HIGHEST-TRANSACTION-ID    PIC 9(16).
           05  WS-NEXT-TRANSACTION-ID       PIC 9(16).

      *    RECORD UNDER INSPECTION (READ FROM JOURNAL OR FROM CALLER)
       01  WS-FILE-TRANSACTION.
           COPY TRANSACT REPLACING ==:TAG:== BY ==FIL==.

       LINKAGE SECTION.
       01  LK-DAO-CONTROL.
           COPY DAOCTL REPLACING ==:TAG:== BY ==LKD==.
       01  LK-TRANSACTION.
           COPY TRANSACT REPLACING ==:TAG:== BY ==LKT==.

       PROCEDURE DIVISION USING LK-DAO-CONTROL
                                LK-TRANSACTION.
      *================================================================*
       0000-MAIN.
           PERFORM 1000-INITIALIZE
           EVALUATE TRUE
               WHEN LKD-FN-READ
               WHEN LKD-FN-FIND-BY-KEY
                   PERFORM 2000-SCAN-JOURNAL
                   PERFORM 2500-RETURN-LOCATED-TRANSACTION
               WHEN LKD-FN-INSERT
                   PERFORM 3000-INSERT-TRANSACTION
               WHEN OTHER
                   SET LKD-ST-INVALID-CALL TO TRUE
           END-EVALUATE
           GOBACK
           .

       1000-INITIALIZE.
           SET LKD-ST-OK                  TO TRUE
           MOVE SPACES                    TO LKD-TECH-CODE
           SET WS-SCAN-IN-PROGRESS        TO TRUE
           SET WS-TRANSACTION-NOT-LOCATED TO TRUE
           SET WS-JOURNAL-FILE-CLOSED     TO TRUE
           MOVE ZERO TO WS-HIGHEST-TRANSACTION-ID
                        WS-NEXT-TRANSACTION-ID
           INITIALIZE WS-FILE-TRANSACTION WITH FILLER
           .

      *================================================================*
      * SEQUENTIAL SCAN SHARED BY READ, FINDKEY AND INSERT             *
      *================================================================*
       2000-SCAN-JOURNAL.
           PERFORM 8000-OPEN-JOURNAL-INPUT
           IF LKD-ST-OK
               PERFORM 8100-READ-JOURNAL
               PERFORM UNTIL WS-SCAN-FINISHED
                   PERFORM 2100-EXAMINE-RECORD
                   IF WS-SCAN-IN-PROGRESS
                       PERFORM 8100-READ-JOURNAL
                   END-IF
               END-PERFORM
           END-IF
           PERFORM 8900-CLOSE-JOURNAL
           .

       2100-EXAMINE-RECORD.
           EVALUATE TRUE
               WHEN LKD-FN-READ
                   IF FIL-TRANSACTION-ID = LKT-TRANSACTION-ID
                       PERFORM 2200-MARK-LOCATED
                   END-IF
               WHEN LKD-FN-FIND-BY-KEY
                   IF FIL-IDEMPOTENCY-KEY = LKT-IDEMPOTENCY-KEY
                       PERFORM 2200-MARK-LOCATED
                   END-IF
               WHEN LKD-FN-INSERT
                   PERFORM 2300-TRACK-INSERT-CONSTRAINTS
           END-EVALUATE
           .

       2200-MARK-LOCATED.
           SET WS-TRANSACTION-LOCATED TO TRUE
           SET WS-SCAN-FINISHED       TO TRUE
           .

      *    ID GENERATION IS ONLY RELIABLE IF EVERY STORED ID IS VALID.
       2300-TRACK-INSERT-CONSTRAINTS.
           EVALUATE TRUE
               WHEN FIL-TRANSACTION-ID IS NOT NUMERIC
                   SET LKD-ST-DATA-ERROR TO TRUE
                   MOVE WS-REASON-BAD-RECORD TO LKD-TECH-CODE
                   SET WS-SCAN-FINISHED TO TRUE
               WHEN FIL-IDEMPOTENCY-KEY = LKT-IDEMPOTENCY-KEY
                   PERFORM 2200-MARK-LOCATED
               WHEN FIL-TRANSACTION-ID-N > WS-HIGHEST-TRANSACTION-ID
                   MOVE FIL-TRANSACTION-ID-N
                     TO WS-HIGHEST-TRANSACTION-ID
               WHEN OTHER
                   CONTINUE
           END-EVALUATE
           .

       2500-RETURN-LOCATED-TRANSACTION.
           IF LKD-ST-OK
               IF WS-TRANSACTION-NOT-LOCATED
                   SET LKD-ST-NOT-FOUND TO TRUE
               ELSE
                   PERFORM 8300-CHECK-RECORD-INTEGRITY
                   IF WS-RECORD-VALID
                       MOVE WS-FILE-TRANSACTION TO LK-TRANSACTION
                   ELSE
                       SET LKD-ST-DATA-ERROR TO TRUE
                       MOVE WS-REASON-BAD-RECORD TO LKD-TECH-CODE
                   END-IF
               END-IF
           END-IF
           .

      *================================================================*
      * INSERT (UNIQUE IDEMPOTENCY-KEY, SEQUENTIAL TRANSACTION-ID)     *
      *================================================================*
       3000-INSERT-TRANSACTION.
           PERFORM 3100-VALIDATE-CALLER-RECORD
           IF LKD-ST-OK
               PERFORM 2000-SCAN-JOURNAL
           END-IF
           IF LKD-ST-OK AND WS-TRANSACTION-LOCATED
               SET LKD-ST-DUPLICATE TO TRUE
           END-IF
           IF LKD-ST-OK
               PERFORM 3200-ASSIGN-TRANSACTION-ID
           END-IF
           IF LKD-ST-OK
               PERFORM 3300-APPEND-TRANSACTION
           END-IF
           IF LKD-ST-OK
               MOVE WS-NEXT-TRANSACTION-ID TO LKT-TRANSACTION-ID-N
           END-IF
           .

      *    THE ID IS ASSIGNED HERE, SO IT IS EXCLUDED FROM THE CHECK.
       3100-VALIDATE-CALLER-RECORD.
           MOVE LK-TRANSACTION TO WS-FILE-TRANSACTION
           MOVE ZERO           TO FIL-TRANSACTION-ID-N
           PERFORM 8300-CHECK-RECORD-INTEGRITY
           IF WS-RECORD-INVALID
               SET LKD-ST-INVALID-CALL TO TRUE
               MOVE WS-REASON-BAD-RECORD TO LKD-TECH-CODE
           END-IF
           .

       3200-ASSIGN-TRANSACTION-ID.
           ADD 1 TO WS-HIGHEST-TRANSACTION-ID
               GIVING WS-NEXT-TRANSACTION-ID
               ON SIZE ERROR
                   SET LKD-ST-DATA-ERROR TO TRUE
                   MOVE WS-REASON-ID-EXHAUSTED TO LKD-TECH-CODE
           END-ADD
           .

       3300-APPEND-TRANSACTION.
           MOVE LK-TRANSACTION         TO WS-FILE-TRANSACTION
           MOVE WS-NEXT-TRANSACTION-ID TO FIL-TRANSACTION-ID-N
           OPEN EXTEND TRANSACTION-JOURNAL-FILE
           IF WS-JOURNAL-OK OR WS-JOURNAL-OPTIONAL-MISSING
               SET WS-JOURNAL-FILE-OPEN TO TRUE
               WRITE TRANSACTION-JOURNAL-RECORD
                   FROM WS-FILE-TRANSACTION
               IF NOT WS-JOURNAL-OK
                   SET LKD-ST-IO-ERROR TO TRUE
                   MOVE WS-JOURNAL-FILE-STATUS TO LKD-TECH-CODE
               END-IF
           ELSE
               SET LKD-ST-IO-ERROR TO TRUE
               MOVE WS-JOURNAL-FILE-STATUS TO LKD-TECH-CODE
           END-IF
           PERFORM 8900-CLOSE-JOURNAL
           .

      *================================================================*
      * FILE PRIMITIVES                                                *
      *================================================================*
       8000-OPEN-JOURNAL-INPUT.
           OPEN INPUT TRANSACTION-JOURNAL-FILE
           EVALUATE TRUE
               WHEN WS-JOURNAL-OK
               WHEN WS-JOURNAL-OPTIONAL-MISSING
                   SET WS-JOURNAL-FILE-OPEN TO TRUE
               WHEN OTHER
                   SET LKD-ST-IO-ERROR TO TRUE
                   MOVE WS-JOURNAL-FILE-STATUS TO LKD-TECH-CODE
                   SET WS-SCAN-FINISHED TO TRUE
           END-EVALUATE
           .

       8100-READ-JOURNAL.
           READ TRANSACTION-JOURNAL-FILE INTO WS-FILE-TRANSACTION
           EVALUATE TRUE
               WHEN WS-JOURNAL-OK
                   CONTINUE
               WHEN WS-JOURNAL-END-OF-FILE
                   SET WS-SCAN-FINISHED TO TRUE
               WHEN OTHER
                   SET LKD-ST-IO-ERROR TO TRUE
                   MOVE WS-JOURNAL-FILE-STATUS TO LKD-TECH-CODE
                   SET WS-SCAN-FINISHED TO TRUE
           END-EVALUATE
           .

      *    NUMERIC TESTS PRECEDE THE SIGN TEST TO AVOID DATA EXCEPTIONS.
       8300-CHECK-RECORD-INTEGRITY.
           EVALUATE TRUE
               WHEN FIL-TRANSACTION-ID IS NOT NUMERIC
               WHEN FIL-ACCOUNT-ID     IS NOT NUMERIC
               WHEN NOT FIL-TYPE-VALID
               WHEN NOT FIL-STATUS-VALID
               WHEN FIL-AMOUNT         IS NOT NUMERIC
               WHEN FIL-BALANCE-AFTER  IS NOT NUMERIC
               WHEN FIL-IDEMPOTENCY-KEY = SPACES
                   SET WS-RECORD-INVALID TO TRUE
               WHEN FIL-AMOUNT NOT > ZERO
               WHEN FIL-BALANCE-AFTER < ZERO
                   SET WS-RECORD-INVALID TO TRUE
               WHEN OTHER
                   SET WS-RECORD-VALID TO TRUE
           END-EVALUATE
           .

       8900-CLOSE-JOURNAL.
           IF WS-JOURNAL-FILE-OPEN
               CLOSE TRANSACTION-JOURNAL-FILE
               SET WS-JOURNAL-FILE-CLOSED TO TRUE
               IF NOT WS-JOURNAL-OK AND LKD-ST-OK
                   SET LKD-ST-IO-ERROR TO TRUE
                   MOVE WS-JOURNAL-FILE-STATUS TO LKD-TECH-CODE
               END-IF
           END-IF
           .
