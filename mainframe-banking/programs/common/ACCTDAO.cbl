       IDENTIFICATION DIVISION.
       PROGRAM-ID. ACCTDAO.
      *================================================================*
      * PROGRAM  : ACCTDAO                                             *
      * TYPE     : DATA ACCESS MODULE - *** LAB IMPLEMENTATION ***     *
      * PURPOSE  : READ / UPDATE ACCOUNT MASTER RECORDS.               *
      * INTERFACE: CALL 'ACCTDAO' USING DAOCTL-AREA ACCOUNT-RECORD     *
      *   READ   : IN  ACCOUNT-ID          OUT FULL RECORD             *
      *   UPDATE : IN  FULL RECORD AS READ (VERSION-NUMBER UNCHANGED)  *
      *                WITH NEW BALANCE / LAST-UPDATE-TS               *
      *            OUT RECORD WITH INCREMENTED VERSION-NUMBER          *
      *----------------------------------------------------------------*
      * LAB STORAGE (GNUCOBOL):                                        *
      *   DD ACCTMAST  LINE SEQUENTIAL MASTER FILE (ENV DD_ACCTMAST)   *
      *   DD ACCTWORK  NEW-MASTER WORK FILE        (ENV DD_ACCTWORK)   *
      *   UPDATE COPIES OLD MASTER -> NEW MASTER AND THEN RENAMES THE  *
      *   NEW MASTER OVER THE OLD ONE (ATOMIC RENAME ON POSIX WHEN     *
      *   BOTH PATHS ARE ON THE SAME FILE SYSTEM).                     *
      *   OPTIMISTIC LOCKING: UPDATE FAILS WITH VERSION-CONFLICT WHEN  *
      *   THE STORED VERSION-NUMBER DIFFERS FROM THE CALLER'S.         *
      *   THIS IS NOT A LOCK MANAGER: RUN THE LAB SERIALLY.            *
      *----------------------------------------------------------------*
      * Z/OS REPLACEMENT (SAME INTERFACE, SEE DOCS/ARCHITECTURE.MD):   *
      *   READ   : EXEC SQL SELECT ... FROM ACCOUNT                    *
      *              WHERE ACCOUNT_ID = :ID                            *
      *   UPDATE : EXEC SQL UPDATE ACCOUNT SET BALANCE = :B,           *
      *              VERSION_NUMBER = VERSION_NUMBER + 1, ...          *
      *              WHERE ACCOUNT_ID = :ID AND VERSION_NUMBER = :V    *
      *            SQLCODE +100 -> VERSION-CONFLICT.                   *
      *   COMMIT/ROLLBACK IS NOT DONE HERE: THE UNIT OF WORK BELONGS   *
      *   TO THE TRANSACTION (CICS SYNCPOINT).                         *
      *================================================================*
       ENVIRONMENT DIVISION.
       INPUT-OUTPUT SECTION.
       FILE-CONTROL.
           SELECT ACCOUNT-MASTER-FILE
               ASSIGN TO ACCTMAST
               ORGANIZATION IS LINE SEQUENTIAL
               FILE STATUS IS WS-MASTER-FILE-STATUS.
           SELECT ACCOUNT-WORK-FILE
               ASSIGN TO ACCTWORK
               ORGANIZATION IS LINE SEQUENTIAL
               FILE STATUS IS WS-WORK-FILE-STATUS.

       DATA DIVISION.
       FILE SECTION.
       FD  ACCOUNT-MASTER-FILE.
       01  ACCOUNT-MASTER-RECORD            PIC X(100).
       FD  ACCOUNT-WORK-FILE.
       01  ACCOUNT-WORK-RECORD              PIC X(100).

       WORKING-STORAGE SECTION.
       01  WS-CONSTANTS.
           05  WS-MASTER-PATH-ENV-NAME      PIC X(11)
                                            VALUE 'DD_ACCTMAST'.
           05  WS-WORK-PATH-ENV-NAME        PIC X(11)
                                            VALUE 'DD_ACCTWORK'.
           05  WS-REASON-NO-PATH            PIC X(08) VALUE 'NOPATH'.
           05  WS-REASON-RENAME             PIC X(08) VALUE 'RENAME'.
           05  WS-REASON-BAD-RECORD         PIC X(08) VALUE 'BADREC'.
           05  WS-REASON-DUPLICATE-ID       PIC X(08) VALUE 'DUPKEY'.
           05  WS-REASON-VERSION-OVERFLOW   PIC X(08) VALUE 'VEROVFL'.

       01  WS-FILE-STATUSES.
           05  WS-MASTER-FILE-STATUS        PIC X(02).
               88  WS-MASTER-OK                      VALUE '00'.
               88  WS-MASTER-END-OF-FILE             VALUE '10'.
           05  WS-WORK-FILE-STATUS          PIC X(02).
               88  WS-WORK-OK                        VALUE '00'.

       01  WS-CONTROL-FLAGS.
           05  WS-SCAN-FLAG                 PIC X(01).
               88  WS-SCAN-IN-PROGRESS               VALUE 'N'.
               88  WS-SCAN-FINISHED                  VALUE 'Y'.
           05  WS-FOUND-FLAG                PIC X(01).
               88  WS-ACCOUNT-NOT-LOCATED            VALUE 'N'.
               88  WS-ACCOUNT-LOCATED                VALUE 'Y'.
           05  WS-RECORD-CHECK-FLAG         PIC X(01).
               88  WS-RECORD-VALID                   VALUE 'Y'.
               88  WS-RECORD-INVALID                 VALUE 'N'.
           05  WS-MASTER-FILE-FLAG          PIC X(01).
               88  WS-MASTER-FILE-CLOSED             VALUE 'N'.
               88  WS-MASTER-FILE-OPEN               VALUE 'Y'.
           05  WS-WORK-FILE-FLAG            PIC X(01).
               88  WS-WORK-FILE-CLOSED               VALUE 'N'.
               88  WS-WORK-FILE-OPEN                 VALUE 'Y'.

       01  WS-FILE-PATHS.
           05  WS-MASTER-PATH               PIC X(256).
           05  WS-WORK-PATH                 PIC X(256).

       01  WS-RENAME-RESULT                 PIC S9(09) COMP-5.

      *    RECORD UNDER INSPECTION (READ FROM MASTER OR FROM CALLER)
       01  WS-FILE-ACCOUNT.
           COPY ACCOUNT REPLACING ==:TAG:== BY ==FIL==.

      *    NEW IMAGE WRITTEN BY UPDATE; RETURNED ONLY AFTER COMMIT
       01  WS-UPDATED-ACCOUNT.
           COPY ACCOUNT REPLACING ==:TAG:== BY ==UPD==.

       LINKAGE SECTION.
       01  LK-DAO-CONTROL.
           COPY DAOCTL REPLACING ==:TAG:== BY ==LKD==.
       01  LK-ACCOUNT.
           COPY ACCOUNT REPLACING ==:TAG:== BY ==LKA==.

       PROCEDURE DIVISION USING LK-DAO-CONTROL
                                LK-ACCOUNT.
      *================================================================*
       0000-MAIN.
           PERFORM 1000-INITIALIZE
           EVALUATE TRUE
               WHEN LKD-FN-READ
                   PERFORM 2000-READ-ACCOUNT
               WHEN LKD-FN-UPDATE
                   PERFORM 3000-UPDATE-ACCOUNT
               WHEN OTHER
                   SET LKD-ST-INVALID-CALL TO TRUE
           END-EVALUATE
           GOBACK
           .

       1000-INITIALIZE.
           SET LKD-ST-OK              TO TRUE
           MOVE SPACES                TO LKD-TECH-CODE
           SET WS-SCAN-IN-PROGRESS    TO TRUE
           SET WS-ACCOUNT-NOT-LOCATED TO TRUE
           SET WS-MASTER-FILE-CLOSED  TO TRUE
           SET WS-WORK-FILE-CLOSED    TO TRUE
           INITIALIZE WS-FILE-ACCOUNT
                      WS-UPDATED-ACCOUNT
                      WITH FILLER
           .

      *================================================================*
      * READ BY ACCOUNT-ID                                             *
      *================================================================*
       2000-READ-ACCOUNT.
           PERFORM 8000-OPEN-MASTER-INPUT
           IF LKD-ST-OK
               PERFORM 8100-READ-MASTER
               PERFORM UNTIL WS-SCAN-FINISHED
                   IF FIL-ACCOUNT-ID = LKA-ACCOUNT-ID
                       SET WS-ACCOUNT-LOCATED TO TRUE
                       SET WS-SCAN-FINISHED   TO TRUE
                   ELSE
                       PERFORM 8100-READ-MASTER
                   END-IF
               END-PERFORM
           END-IF
           PERFORM 8900-CLOSE-MASTER
           IF LKD-ST-OK
               PERFORM 2100-RETURN-LOCATED-ACCOUNT
           END-IF
           .

       2100-RETURN-LOCATED-ACCOUNT.
           IF WS-ACCOUNT-NOT-LOCATED
               SET LKD-ST-NOT-FOUND TO TRUE
           ELSE
               PERFORM 8300-CHECK-RECORD-INTEGRITY
               IF WS-RECORD-VALID
                   MOVE WS-FILE-ACCOUNT TO LK-ACCOUNT
               ELSE
                   SET LKD-ST-DATA-ERROR TO TRUE
                   MOVE WS-REASON-BAD-RECORD TO LKD-TECH-CODE
               END-IF
           END-IF
           .

      *================================================================*
      * UPDATE (OLD MASTER -> NEW MASTER, THEN ATOMIC RENAME)          *
      *================================================================*
       3000-UPDATE-ACCOUNT.
           PERFORM 3100-VALIDATE-CALLER-RECORD
           IF LKD-ST-OK
               PERFORM 3200-RESOLVE-FILE-PATHS
           END-IF
           IF LKD-ST-OK
               PERFORM 3300-BUILD-NEW-MASTER
           END-IF
           IF LKD-ST-OK
               PERFORM 3500-COMMIT-NEW-MASTER
           END-IF
           IF LKD-ST-OK
               MOVE WS-UPDATED-ACCOUNT TO LK-ACCOUNT
           END-IF
           .

      *    THE DAO NEVER WRITES A RECORD IT WOULD REJECT ON READ.
       3100-VALIDATE-CALLER-RECORD.
           MOVE LK-ACCOUNT TO WS-FILE-ACCOUNT
           PERFORM 8300-CHECK-RECORD-INTEGRITY
           IF WS-RECORD-INVALID
               SET LKD-ST-INVALID-CALL TO TRUE
               MOVE WS-REASON-BAD-RECORD TO LKD-TECH-CODE
           ELSE
               MOVE LK-ACCOUNT TO WS-UPDATED-ACCOUNT
               ADD 1 TO UPD-VERSION-NUMBER
                   ON SIZE ERROR
                       SET LKD-ST-DATA-ERROR TO TRUE
                       MOVE WS-REASON-VERSION-OVERFLOW
                         TO LKD-TECH-CODE
               END-ADD
           END-IF
           .

       3200-RESOLVE-FILE-PATHS.
           MOVE SPACES TO WS-MASTER-PATH
                          WS-WORK-PATH
           ACCEPT WS-MASTER-PATH FROM ENVIRONMENT
                  WS-MASTER-PATH-ENV-NAME
           ACCEPT WS-WORK-PATH FROM ENVIRONMENT
                  WS-WORK-PATH-ENV-NAME
           IF WS-MASTER-PATH = SPACES
              OR WS-WORK-PATH = SPACES
               SET LKD-ST-IO-ERROR TO TRUE
               MOVE WS-REASON-NO-PATH TO LKD-TECH-CODE
           END-IF
           .

       3300-BUILD-NEW-MASTER.
           PERFORM 8000-OPEN-MASTER-INPUT
           IF LKD-ST-OK
               PERFORM 8200-OPEN-WORK-OUTPUT
           END-IF
           IF LKD-ST-OK
               PERFORM 8100-READ-MASTER
               PERFORM UNTIL WS-SCAN-FINISHED
                   PERFORM 3400-COPY-OR-REPLACE-RECORD
                   IF WS-SCAN-IN-PROGRESS
                       PERFORM 8100-READ-MASTER
                   END-IF
               END-PERFORM
           END-IF
           PERFORM 8900-CLOSE-MASTER
           PERFORM 8950-CLOSE-WORK
           IF LKD-ST-OK AND WS-ACCOUNT-NOT-LOCATED
               SET LKD-ST-NOT-FOUND TO TRUE
           END-IF
           .

       3400-COPY-OR-REPLACE-RECORD.
           IF FIL-ACCOUNT-ID NOT = LKA-ACCOUNT-ID
               MOVE ACCOUNT-MASTER-RECORD TO ACCOUNT-WORK-RECORD
               PERFORM 8250-WRITE-WORK
           ELSE
               PERFORM 8300-CHECK-RECORD-INTEGRITY
               EVALUATE TRUE
                   WHEN WS-ACCOUNT-LOCATED
                       SET LKD-ST-DATA-ERROR TO TRUE
                       MOVE WS-REASON-DUPLICATE-ID TO LKD-TECH-CODE
                       SET WS-SCAN-FINISHED TO TRUE
                   WHEN WS-RECORD-INVALID
                       SET LKD-ST-DATA-ERROR TO TRUE
                       MOVE WS-REASON-BAD-RECORD TO LKD-TECH-CODE
                       SET WS-SCAN-FINISHED TO TRUE
                   WHEN FIL-VERSION-NUMBER NOT = LKA-VERSION-NUMBER
                       SET LKD-ST-VERSION-CONFLICT TO TRUE
                       SET WS-SCAN-FINISHED TO TRUE
                   WHEN OTHER
                       SET WS-ACCOUNT-LOCATED TO TRUE
                       MOVE WS-UPDATED-ACCOUNT TO ACCOUNT-WORK-RECORD
                       PERFORM 8250-WRITE-WORK
               END-EVALUATE
           END-IF
           .

      *    ON ANY FAILURE ABOVE THE OLD MASTER IS LEFT UNTOUCHED.
       3500-COMMIT-NEW-MASTER.
           CALL 'CBL_RENAME_FILE' USING WS-WORK-PATH
                                        WS-MASTER-PATH
               RETURNING WS-RENAME-RESULT
           END-CALL
           IF WS-RENAME-RESULT NOT = ZERO
               SET LKD-ST-IO-ERROR TO TRUE
               MOVE WS-REASON-RENAME TO LKD-TECH-CODE
           END-IF
           .

      *================================================================*
      * FILE PRIMITIVES                                                *
      *================================================================*
       8000-OPEN-MASTER-INPUT.
           OPEN INPUT ACCOUNT-MASTER-FILE
           IF WS-MASTER-OK
               SET WS-MASTER-FILE-OPEN TO TRUE
           ELSE
               SET LKD-ST-IO-ERROR TO TRUE
               MOVE WS-MASTER-FILE-STATUS TO LKD-TECH-CODE
               SET WS-SCAN-FINISHED TO TRUE
           END-IF
           .

      *    LOADS THE NEXT RECORD INTO WS-FILE-ACCOUNT OR ENDS THE SCAN.
       8100-READ-MASTER.
           READ ACCOUNT-MASTER-FILE INTO WS-FILE-ACCOUNT
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

       8200-OPEN-WORK-OUTPUT.
           OPEN OUTPUT ACCOUNT-WORK-FILE
           IF WS-WORK-OK
               SET WS-WORK-FILE-OPEN TO TRUE
           ELSE
               SET LKD-ST-IO-ERROR TO TRUE
               MOVE WS-WORK-FILE-STATUS TO LKD-TECH-CODE
               SET WS-SCAN-FINISHED TO TRUE
           END-IF
           .

       8250-WRITE-WORK.
           WRITE ACCOUNT-WORK-RECORD
           IF NOT WS-WORK-OK
               SET LKD-ST-IO-ERROR TO TRUE
               MOVE WS-WORK-FILE-STATUS TO LKD-TECH-CODE
               SET WS-SCAN-FINISHED TO TRUE
           END-IF
           .

      *----------------------------------------------------------------*
      * FAIL-SAFE INTEGRITY CHECK (EQUIVALENT TO DB2 CHECK CONSTRAINTS)*
      * NUMERIC TESTS PRECEDE THE SIGN TEST TO AVOID DATA EXCEPTIONS.  *
      *----------------------------------------------------------------*
       8300-CHECK-RECORD-INTEGRITY.
           EVALUATE TRUE
               WHEN FIL-ACCOUNT-ID     IS NOT NUMERIC
               WHEN FIL-CUSTOMER-ID    IS NOT NUMERIC
               WHEN NOT FIL-TYPE-VALID
               WHEN NOT FIL-STATUS-VALID
               WHEN FIL-BALANCE        IS NOT NUMERIC
               WHEN FIL-VERSION-NUMBER IS NOT NUMERIC
               WHEN NOT FIL-CUSTOMER-STATUS-VALID
                   SET WS-RECORD-INVALID TO TRUE
               WHEN FIL-BALANCE < ZERO
                   SET WS-RECORD-INVALID TO TRUE
               WHEN OTHER
                   SET WS-RECORD-VALID TO TRUE
           END-EVALUATE
           .

      *    CLOSE ERRORS AFTER A SUCCESSFUL SCAN ARE STILL FAILURES.
       8900-CLOSE-MASTER.
           IF WS-MASTER-FILE-OPEN
               CLOSE ACCOUNT-MASTER-FILE
               SET WS-MASTER-FILE-CLOSED TO TRUE
               IF NOT WS-MASTER-OK AND LKD-ST-OK
                   SET LKD-ST-IO-ERROR TO TRUE
                   MOVE WS-MASTER-FILE-STATUS TO LKD-TECH-CODE
               END-IF
           END-IF
           .

       8950-CLOSE-WORK.
           IF WS-WORK-FILE-OPEN
               CLOSE ACCOUNT-WORK-FILE
               SET WS-WORK-FILE-CLOSED TO TRUE
               IF NOT WS-WORK-OK AND LKD-ST-OK
                   SET LKD-ST-IO-ERROR TO TRUE
                   MOVE WS-WORK-FILE-STATUS TO LKD-TECH-CODE
               END-IF
           END-IF
           .
