       IDENTIFICATION DIVISION.
       PROGRAM-ID. TRXINQ.
      *================================================================*
      * PROGRAM  : TRXINQ                                              *
      * TYPE     : ENTRY PROGRAM (READ-ONLY)                           *
      * PURPOSE  : TRANSACTION INQUIRY BY TRANSACTION-ID.              *
      * INPUT    : REQUEST  (OPERATION TRXINQ, BODY REQ-TRANSACTION-   *
      *            INQUIRY)                                            *
      * OUTPUT   : RESPONSE (BODY RSP-TRANSACTION-INQUIRY)             *
      * SECURITY : THE IDEMPOTENCY-KEY AND BALANCE-AFTER STORED WITH   *
      *            THE TRANSACTION ARE NOT EXPOSED.                    *
      *            OWNERSHIP (IS THE CALLER ALLOWED TO SEE THIS        *
      *            ACCOUNT?) IS AN AUTHORIZATION CONCERN OF THE        *
      *            CALLING LAYER / RACF, NOT OF THIS PROGRAM.          *
      * Z/OS CICS: SEE ACCTDEP.                                        *
      *================================================================*
       ENVIRONMENT DIVISION.

       DATA DIVISION.
       WORKING-STORAGE SECTION.
       01  WS-PROGRAM-NAMES.
           05  WS-THIS-PROGRAM              PIC X(08) VALUE 'TRXINQ'.
           05  WS-PGM-VALIDATOR             PIC X(08) VALUE 'BKVALID'.
           05  WS-PGM-RESPONSE-BUILDER      PIC X(08) VALUE 'BKRESP'.
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

       01  WS-TRANSACTION.
           COPY TRANSACT REPLACING ==:TAG:== BY ==TRX==.

       LINKAGE SECTION.
       01  LK-REQUEST.
           COPY REQUEST.
       01  LK-RESPONSE.
           COPY RESPONSE.

       PROCEDURE DIVISION USING LK-REQUEST
                                LK-RESPONSE.
      *================================================================*
       0000-MAIN.
           PERFORM 1000-INITIALIZE
           PERFORM 2000-VALIDATE-INPUT
           IF WS-RC-SUCCESS
               PERFORM 3000-LOAD-TRANSACTION
           END-IF
           PERFORM 8000-BUILD-RESPONSE
           PERFORM 9000-FINALIZE
           GOBACK
           .

       1000-INITIALIZE.
           SET WS-RC-SUCCESS TO TRUE
           MOVE SPACES TO WS-TECH-CODE
           INITIALIZE WS-VALIDATION
                      WS-DAO-CONTROL
                      WS-TRANSACTION
                      WS-RESPONSE-CONTROL
                      WITH FILLER
           SET RCT-FN-INIT TO TRUE
           PERFORM 8900-CALL-RESPONSE-BUILDER
           .

       2000-VALIDATE-INPUT.
           IF NOT REQ-LAYOUT-V01
              OR NOT REQ-OP-TRANSACTION-INQUIRY
               SET WS-RC-INVALID-REQUEST TO TRUE
           ELSE
               SET VAL-FN-TRANSACTION-ID TO TRUE
               MOVE REQ-TI-TRANSACTION-ID TO VAL-FIELD
               CALL WS-PGM-VALIDATOR USING WS-VALIDATION
                   ON EXCEPTION
                       SET WS-RC-UNEXPECTED-ERROR TO TRUE
                       MOVE WS-REASON-MODULE-MISSING TO WS-TECH-CODE
                   NOT ON EXCEPTION
                       MOVE VAL-RESULT-CODE TO WS-RESPONSE-CODE
               END-CALL
           END-IF
           .

       3000-LOAD-TRANSACTION.
           MOVE REQ-TI-TRANSACTION-ID TO TRX-TRANSACTION-ID
           SET DAO-FN-READ TO TRUE
           CALL WS-PGM-TRANSACTION-DAO USING WS-DAO-CONTROL
                                             WS-TRANSACTION
               ON EXCEPTION
                   SET DAO-ST-IO-ERROR TO TRUE
                   MOVE WS-REASON-MODULE-MISSING TO DAO-TECH-CODE
           END-CALL
           EVALUATE TRUE
               WHEN DAO-ST-OK
                   CONTINUE
               WHEN DAO-ST-NOT-FOUND
                   SET WS-RC-TRX-NOT-FOUND TO TRUE
               WHEN DAO-ST-DATA-ERROR
                   SET WS-RC-DATA-INTEGRITY-ERROR TO TRUE
                   MOVE DAO-TECH-CODE TO WS-TECH-CODE
               WHEN DAO-ST-IO-ERROR
                   SET WS-RC-DATA-ACCESS-ERROR TO TRUE
                   MOVE DAO-TECH-CODE TO WS-TECH-CODE
               WHEN OTHER
                   SET WS-RC-UNEXPECTED-ERROR TO TRUE
                   MOVE DAO-TECH-CODE TO WS-TECH-CODE
           END-EVALUATE
           .

       8000-BUILD-RESPONSE.
           IF WS-RC-SUCCESS
               MOVE TRX-TRANSACTION-ID     TO RSP-TI-TRANSACTION-ID
               MOVE TRX-ACCOUNT-ID         TO RSP-TI-ACCOUNT-ID
               MOVE TRX-TRANSACTION-TYPE   TO RSP-TI-TRANSACTION-TYPE
               MOVE TRX-AMOUNT             TO RSP-TI-AMOUNT
               MOVE TRX-CURRENCY           TO RSP-TI-CURRENCY
               MOVE TRX-TRANSACTION-STATUS
                 TO RSP-TI-TRANSACTION-STATUS
               MOVE TRX-TRANSACTION-TS     TO RSP-TI-TRANSACTION-TS
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

       9000-FINALIZE.
           SET RCT-FN-FINISH TO TRUE
           PERFORM 8900-CALL-RESPONSE-BUILDER
           .
