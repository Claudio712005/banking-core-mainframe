       IDENTIFICATION DIVISION.
       PROGRAM-ID. CUSTDAO.
      *================================================================*
      * PROGRAM  : CUSTDAO                                             *
      * TYPE     : DATA ACCESS MODULE - *** LAB IMPLEMENTATION ***     *
      * PURPOSE  : READ CUSTOMER MASTER RECORDS (READ-ONLY).           *
      * INTERFACE: CALL 'CUSTDAO' USING DAOCTL-AREA CUSTOMER-RECORD    *
      *   READ   : IN  CUSTOMER-ID         OUT FULL RECORD             *
      *----------------------------------------------------------------*
      * LAB STORAGE : DD CUSTMAST, LINE SEQUENTIAL (ENV DD_CUSTMAST).  *
      * Z/OS        : EXEC SQL SELECT ... FROM CUSTOMER                *
      *                 WHERE CUSTOMER_ID = :ID                        *
      *               (SELECT ONLY THE COLUMNS THE CALLER NEEDS).      *
      *================================================================*
       ENVIRONMENT DIVISION.
       INPUT-OUTPUT SECTION.
       FILE-CONTROL.
           SELECT CUSTOMER-MASTER-FILE
               ASSIGN TO CUSTMAST
               ORGANIZATION IS LINE SEQUENTIAL
               FILE STATUS IS WS-MASTER-FILE-STATUS.

       DATA DIVISION.
       FILE SECTION.
       FD  CUSTOMER-MASTER-FILE.
       01  CUSTOMER-MASTER-RECORD           PIC X(60).

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
               88  WS-CUSTOMER-NOT-LOCATED           VALUE 'N'.
               88  WS-CUSTOMER-LOCATED               VALUE 'Y'.
           05  WS-MASTER-FILE-FLAG          PIC X(01).
               88  WS-MASTER-FILE-CLOSED             VALUE 'N'.
               88  WS-MASTER-FILE-OPEN               VALUE 'Y'.

       01  WS-FILE-CUSTOMER.
           COPY CUSTOMER REPLACING ==:TAG:== BY ==FIL==.

       LINKAGE SECTION.
       01  LK-DAO-CONTROL.
           COPY DAOCTL REPLACING ==:TAG:== BY ==LKD==.
       01  LK-CUSTOMER.
           COPY CUSTOMER REPLACING ==:TAG:== BY ==LKC==.

       PROCEDURE DIVISION USING LK-DAO-CONTROL
                                LK-CUSTOMER.
      *================================================================*
       0000-MAIN.
           PERFORM 1000-INITIALIZE
           IF LKD-FN-READ
               PERFORM 2000-READ-CUSTOMER
           ELSE
               SET LKD-ST-INVALID-CALL TO TRUE
           END-IF
           GOBACK
           .

       1000-INITIALIZE.
           SET LKD-ST-OK               TO TRUE
           MOVE SPACES                 TO LKD-TECH-CODE
           SET WS-SCAN-IN-PROGRESS     TO TRUE
           SET WS-CUSTOMER-NOT-LOCATED TO TRUE
           SET WS-MASTER-FILE-CLOSED   TO TRUE
           INITIALIZE WS-FILE-CUSTOMER WITH FILLER
           .

       2000-READ-CUSTOMER.
           PERFORM 8000-OPEN-MASTER-INPUT
           IF LKD-ST-OK
               PERFORM 8100-READ-MASTER
               PERFORM UNTIL WS-SCAN-FINISHED
                   IF FIL-CUSTOMER-ID = LKC-CUSTOMER-ID
                       SET WS-CUSTOMER-LOCATED TO TRUE
                       SET WS-SCAN-FINISHED    TO TRUE
                   ELSE
                       PERFORM 8100-READ-MASTER
                   END-IF
               END-PERFORM
           END-IF
           PERFORM 8900-CLOSE-MASTER
           IF LKD-ST-OK
               PERFORM 2100-RETURN-LOCATED-CUSTOMER
           END-IF
           .

       2100-RETURN-LOCATED-CUSTOMER.
           EVALUATE TRUE
               WHEN WS-CUSTOMER-NOT-LOCATED
                   SET LKD-ST-NOT-FOUND TO TRUE
               WHEN FIL-CUSTOMER-ID IS NOT NUMERIC
               WHEN NOT FIL-STATUS-VALID
                   SET LKD-ST-DATA-ERROR TO TRUE
                   MOVE WS-REASON-BAD-RECORD TO LKD-TECH-CODE
               WHEN OTHER
                   MOVE WS-FILE-CUSTOMER TO LK-CUSTOMER
           END-EVALUATE
           .

      *================================================================*
      * FILE PRIMITIVES                                                *
      *================================================================*
       8000-OPEN-MASTER-INPUT.
           OPEN INPUT CUSTOMER-MASTER-FILE
           IF WS-MASTER-OK
               SET WS-MASTER-FILE-OPEN TO TRUE
           ELSE
               SET LKD-ST-IO-ERROR TO TRUE
               MOVE WS-MASTER-FILE-STATUS TO LKD-TECH-CODE
               SET WS-SCAN-FINISHED TO TRUE
           END-IF
           .

       8100-READ-MASTER.
           READ CUSTOMER-MASTER-FILE INTO WS-FILE-CUSTOMER
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
               CLOSE CUSTOMER-MASTER-FILE
               SET WS-MASTER-FILE-CLOSED TO TRUE
               IF NOT WS-MASTER-OK AND LKD-ST-OK
                   SET LKD-ST-IO-ERROR TO TRUE
                   MOVE WS-MASTER-FILE-STATUS TO LKD-TECH-CODE
               END-IF
           END-IF
           .
