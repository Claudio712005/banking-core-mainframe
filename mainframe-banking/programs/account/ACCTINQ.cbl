       IDENTIFICATION DIVISION.
       PROGRAM-ID. ACCTINQ.
      *================================================================*
      * PROGRAM  : ACCTINQ                                             *
      * TYPE     : ENTRY PROGRAM (READ-ONLY)                           *
      * PURPOSE  : ACCOUNT INQUIRY.                                    *
      * INPUT    : REQUEST  (OPERATION ACCTINQ, BODY REQ-ACCOUNT-      *
      *            INQUIRY)                                            *
      * OUTPUT   : RESPONSE (BODY RSP-ACCOUNT-INQUIRY)                 *
      * RULES    : ANY EXISTING ACCOUNT IS RETURNED, WHATEVER ITS      *
      *            STATUS; THE CLIENT DECIDES HOW TO PRESENT IT.       *
      *            THE INTERNAL VERSION-NUMBER IS NOT EXPOSED.         *
      * Z/OS CICS: SEE ACCTDEP.                                        *
      *================================================================*
       ENVIRONMENT DIVISION.

       DATA DIVISION.
       WORKING-STORAGE SECTION.
       01  WS-PROGRAM-NAMES.
           05  WS-THIS-PROGRAM              PIC X(08) VALUE 'ACCTINQ'.
           05  WS-PGM-VALIDATOR             PIC X(08) VALUE 'BKVALID'.
           05  WS-PGM-RESPONSE-BUILDER      PIC X(08) VALUE 'BKRESP'.
           05  WS-PGM-ACCOUNT-DAO           PIC X(08) VALUE 'ACCTDAO'.

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

       01  WS-ACCOUNT.
           COPY ACCOUNT REPLACING ==:TAG:== BY ==ACC==.

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
               PERFORM 3000-LOAD-ACCOUNT
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
                      WS-ACCOUNT
                      WS-RESPONSE-CONTROL
                      WITH FILLER
           SET RCT-FN-INIT TO TRUE
           PERFORM 8900-CALL-RESPONSE-BUILDER
           .

       2000-VALIDATE-INPUT.
           IF NOT REQ-LAYOUT-V01
              OR NOT REQ-OP-ACCOUNT-INQUIRY
               SET WS-RC-INVALID-REQUEST TO TRUE
           ELSE
               SET VAL-FN-ACCOUNT-ID TO TRUE
               MOVE REQ-AI-ACCOUNT-ID TO VAL-FIELD
               CALL WS-PGM-VALIDATOR USING WS-VALIDATION
                   ON EXCEPTION
                       SET WS-RC-UNEXPECTED-ERROR TO TRUE
                       MOVE WS-REASON-MODULE-MISSING TO WS-TECH-CODE
                   NOT ON EXCEPTION
                       MOVE VAL-RESULT-CODE TO WS-RESPONSE-CODE
               END-CALL
           END-IF
           .

       3000-LOAD-ACCOUNT.
           MOVE REQ-AI-ACCOUNT-ID TO ACC-ACCOUNT-ID
           SET DAO-FN-READ TO TRUE
           CALL WS-PGM-ACCOUNT-DAO USING WS-DAO-CONTROL
                                         WS-ACCOUNT
               ON EXCEPTION
                   SET DAO-ST-IO-ERROR TO TRUE
                   MOVE WS-REASON-MODULE-MISSING TO DAO-TECH-CODE
           END-CALL
           EVALUATE TRUE
               WHEN DAO-ST-OK
                   CONTINUE
               WHEN DAO-ST-NOT-FOUND
                   SET WS-RC-ACCOUNT-NOT-FOUND TO TRUE
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
               MOVE ACC-ACCOUNT-ID     TO RSP-AI-ACCOUNT-ID
               MOVE ACC-CUSTOMER-ID    TO RSP-AI-CUSTOMER-ID
               MOVE ACC-ACCOUNT-TYPE   TO RSP-AI-ACCOUNT-TYPE
               MOVE ACC-ACCOUNT-STATUS TO RSP-AI-ACCOUNT-STATUS
               MOVE ACC-BALANCE        TO RSP-AI-BALANCE
               MOVE ACC-CURRENCY       TO RSP-AI-CURRENCY
               MOVE ACC-LAST-UPDATE-TS TO RSP-AI-LAST-UPDATE-TS
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
