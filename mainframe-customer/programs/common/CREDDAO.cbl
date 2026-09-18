       IDENTIFICATION DIVISION.
       PROGRAM-ID. CREDDAO.
      *================================================================*
      * PROGRAM  : CREDDAO                                             *
      * TYPE     : DATA ACCESS MODULE - *** LAB IMPLEMENTATION ***     *
      * PURPOSE  : READ THE CREDIT LIMIT OF A CUSTOMER.                *
      * INTERFACE: CALL 'CREDDAO' USING CSTDAO-AREA CREDIT-RECORD      *
      *   READ   : IN  CUSTOMER-ID        OUT FULL RECORD              *
      *----------------------------------------------------------------*
      * LAB STORAGE : DD CREDMAST, LINE SEQUENTIAL (ENV DD_CREDMAST).  *
      * Z/OS        : EXEC SQL SELECT ... FROM CUSTOMER_CREDIT         *
      *                 WHERE CUSTOMER_ID = :ID                        *
      *================================================================*
       ENVIRONMENT DIVISION.
       INPUT-OUTPUT SECTION.
       FILE-CONTROL.
           SELECT CREDIT-MASTER-FILE
               ASSIGN TO CREDMAST
               ORGANIZATION IS LINE SEQUENTIAL
               FILE STATUS IS WS-MASTER-FILE-STATUS.

       DATA DIVISION.
       FILE SECTION.
       FD  CREDIT-MASTER-FILE.
       01  CREDIT-MASTER-RECORD             PIC X(60).

       WORKING-STORAGE SECTION.
       01  WS-CONSTANTS.
           05  WS-REASON-BAD-RECORD         PIC X(08) VALUE 'BADREC'.

       01  WS-FILE-STATUSES.
           05  WS-MASTER-FILE-STATUS        PIC X(02).
               88  WS-MASTER-OK                      VALUE '00'.
               88  WS-MASTER-END-OF-FILE             VALUE '10'.

       01  WS-CONTROL-FLAGS.
           05  WS-SCAN-FLAG                 PIC X(01).
               88  WS-SCAN-IN-PROGRESS               VALUE 'N'.
               88  WS-SCAN-FINISHED                  VALUE 'Y'.
           05  WS-FOUND-FLAG                PIC X(01).
               88  WS-CREDIT-NOT-LOCATED             VALUE 'N'.
               88  WS-CREDIT-LOCATED                 VALUE 'Y'.
           05  WS-MASTER-FILE-FLAG          PIC X(01).
               88  WS-MASTER-FILE-CLOSED             VALUE 'N'.
               88  WS-MASTER-FILE-OPEN               VALUE 'Y'.

       01  WS-FILE-CREDIT.
           COPY CREDREC REPLACING ==:TAG:== BY ==FIL==.

       LINKAGE SECTION.
       01  LK-DAO-CONTROL.
           COPY CSTDAO REPLACING ==:TAG:== BY ==LKD==.
       01  LK-CREDIT.
           COPY CREDREC REPLACING ==:TAG:== BY ==LKR==.

       PROCEDURE DIVISION USING LK-DAO-CONTROL
                                LK-CREDIT.
      *================================================================*
       0000-MAIN.
           PERFORM 1000-INITIALIZE
           IF LKD-FN-READ
               PERFORM 2000-READ-CREDIT
           ELSE
               SET LKD-ST-INVALID-CALL TO TRUE
           END-IF
           GOBACK
           .

       1000-INITIALIZE.
           SET LKD-ST-OK             TO TRUE
           MOVE SPACES               TO LKD-TECH-CODE
           SET WS-SCAN-IN-PROGRESS   TO TRUE
           SET WS-CREDIT-NOT-LOCATED TO TRUE
           SET WS-MASTER-FILE-CLOSED TO TRUE
           INITIALIZE WS-FILE-CREDIT WITH FILLER
           .

       2000-READ-CREDIT.
           PERFORM 8000-OPEN-MASTER-INPUT
           IF LKD-ST-OK
               PERFORM 8100-READ-MASTER
               PERFORM UNTIL WS-SCAN-FINISHED
                   IF FIL-CUSTOMER-ID = LKR-CUSTOMER-ID
                       SET WS-CREDIT-LOCATED TO TRUE
                       SET WS-SCAN-FINISHED  TO TRUE
                   ELSE
                       PERFORM 8100-READ-MASTER
                   END-IF
               END-PERFORM
           END-IF
           PERFORM 8900-CLOSE-MASTER
           IF LKD-ST-OK
               PERFORM 2100-RETURN-LOCATED-CREDIT
           END-IF
           .

      *    FAIL-SAFE INTEGRITY CHECK (EQUIVALENT TO DB2 CONSTRAINTS).
      *    NUMERIC TESTS PRECEDE ANY COMPARISON OF THE AMOUNTS.
       2100-RETURN-LOCATED-CREDIT.
           EVALUATE TRUE
               WHEN WS-CREDIT-NOT-LOCATED
                   SET LKD-ST-NOT-FOUND TO TRUE
               WHEN FIL-CUSTOMER-ID    IS NOT NUMERIC
               WHEN FIL-APPROVED-LIMIT IS NOT NUMERIC
               WHEN FIL-USED-LIMIT     IS NOT NUMERIC
                   SET LKD-ST-DATA-ERROR TO TRUE
                   MOVE WS-REASON-BAD-RECORD TO LKD-TECH-CODE
               WHEN FIL-APPROVED-LIMIT < ZERO
               WHEN FIL-USED-LIMIT < ZERO
               WHEN FIL-USED-LIMIT > FIL-APPROVED-LIMIT
                   SET LKD-ST-DATA-ERROR TO TRUE
                   MOVE WS-REASON-BAD-RECORD TO LKD-TECH-CODE
               WHEN OTHER
                   MOVE WS-FILE-CREDIT TO LK-CREDIT
           END-EVALUATE
           .

      *================================================================*
      * FILE PRIMITIVES                                                *
      *================================================================*
       8000-OPEN-MASTER-INPUT.
           OPEN INPUT CREDIT-MASTER-FILE
           IF WS-MASTER-OK
               SET WS-MASTER-FILE-OPEN TO TRUE
           ELSE
               SET LKD-ST-IO-ERROR TO TRUE
               MOVE WS-MASTER-FILE-STATUS TO LKD-TECH-CODE
               SET WS-SCAN-FINISHED TO TRUE
           END-IF
           .

       8100-READ-MASTER.
           READ CREDIT-MASTER-FILE INTO WS-FILE-CREDIT
           EVALUATE TRUE
               WHEN WS-MASTER-OK
                   CONTINUE
               WHEN WS-MASTER-END-OF-FILE
                   SET WS-SCAN-FINISHED TO TRUE
               WHEN OTHER
                   SET LKD-ST-IO-ERROR TO TRUE
                   MOVE WS-MASTER-FILE-STATUS TO LKD-TECH-CODE
                   SET WS-SCAN-FINISHED TO TRUE
           END-EVALUATE
           .

       8900-CLOSE-MASTER.
           IF WS-MASTER-FILE-OPEN
               CLOSE CREDIT-MASTER-FILE
               SET WS-MASTER-FILE-CLOSED TO TRUE
               IF NOT WS-MASTER-OK AND LKD-ST-OK
                   SET LKD-ST-IO-ERROR TO TRUE
                   MOVE WS-MASTER-FILE-STATUS TO LKD-TECH-CODE
               END-IF
           END-IF
           .
