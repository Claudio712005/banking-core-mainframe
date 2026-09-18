       IDENTIFICATION DIVISION.
       PROGRAM-ID. CUSTINQ.
      *================================================================*
      * PROGRAM  : CUSTINQ                                             *
      * TYPE     : ENTRY PROGRAM (READ-ONLY)                           *
      * PURPOSE  : CUSTOMER INQUIRY.                                   *
      * INPUT    : REQUEST  (OPERATION CUSTINQ, CUSTOMER-ID)           *
      * OUTPUT   : RESPONSE (BODY CRS-CUSTOMER-INQUIRY)                *
      * RULES    : ANY EXISTING CUSTOMER IS RETURNED, WHATEVER ITS     *
      *            STATUS; THE CALLER DECIDES WHAT TO DO WITH IT.      *
      * SECURITY : THE NATIONAL ID IS RETURNED MASKED, NEVER IN FULL.  *
      *================================================================*
       ENVIRONMENT DIVISION.

       DATA DIVISION.
       WORKING-STORAGE SECTION.
       01  WS-PROGRAM-NAMES.
           05  WS-THIS-PROGRAM              PIC X(08) VALUE 'CUSTINQ'.
           05  WS-PGM-VALIDATOR             PIC X(08) VALUE 'CSTVAL'.
           05  WS-PGM-RESPONSE-BUILDER      PIC X(08) VALUE 'CSTRESP'.
           05  WS-PGM-CUSTOMER-DAO          PIC X(08) VALUE 'CUSTDAO'.

       01  WS-CONSTANTS.
           05  WS-REASON-MODULE-MISSING     PIC X(08) VALUE 'NOMODULE'.
           05  WS-DOCUMENT-MASK             PIC X(12)
                                            VALUE '***.***.***-'.

       01  WS-RESULT.
           COPY CSTCODE REPLACING ==:TAG:== BY ==WS==.

       01  WS-TECH-CODE                     PIC X(08).
       01  WS-VALIDATION-CODE               PIC X(04).
       01  WS-MASKED-DOCUMENT               PIC X(14).

       01  WS-RESPONSE-CONTROL.
           COPY CSTCTL REPLACING ==:TAG:== BY ==RCT==.

       01  WS-DAO-CONTROL.
           COPY CSTDAO REPLACING ==:TAG:== BY ==DAO==.

       01  WS-CUSTOMER.
           COPY CUSTREC REPLACING ==:TAG:== BY ==CUS==.

       LINKAGE SECTION.
       01  LK-REQUEST.
           COPY CUSTREQ.
       01  LK-RESPONSE.
           COPY CUSTRSP.

       PROCEDURE DIVISION USING LK-REQUEST
                                LK-RESPONSE.
      *================================================================*
       0000-MAIN.
           PERFORM 1000-INITIALIZE
           PERFORM 2000-VALIDATE-INPUT
           IF WS-RC-SUCCESS
               PERFORM 3000-LOAD-CUSTOMER
           END-IF
           PERFORM 8000-BUILD-RESPONSE
           PERFORM 9000-FINALIZE
           GOBACK
           .

       1000-INITIALIZE.
           SET WS-RC-SUCCESS TO TRUE
           MOVE SPACES TO WS-TECH-CODE
           INITIALIZE WS-DAO-CONTROL
                      WS-CUSTOMER
                      WS-RESPONSE-CONTROL
                      WITH FILLER
           SET RCT-FN-INIT TO TRUE
           PERFORM 8900-CALL-RESPONSE-BUILDER
           .

       2000-VALIDATE-INPUT.
           IF NOT CRQ-LAYOUT-V01
              OR NOT CRQ-OP-CUSTOMER-INQUIRY
               SET WS-RC-INVALID-REQUEST TO TRUE
           ELSE
               CALL WS-PGM-VALIDATOR USING CRQ-CUSTOMER-ID
                                           WS-VALIDATION-CODE
                   ON EXCEPTION
                       SET WS-RC-UNEXPECTED-ERROR TO TRUE
                       MOVE WS-REASON-MODULE-MISSING TO WS-TECH-CODE
                   NOT ON EXCEPTION
                       MOVE WS-VALIDATION-CODE TO WS-RESPONSE-CODE
               END-CALL
           END-IF
           .

       3000-LOAD-CUSTOMER.
           MOVE CRQ-CUSTOMER-ID TO CUS-CUSTOMER-ID
           SET DAO-FN-READ TO TRUE
           CALL WS-PGM-CUSTOMER-DAO USING WS-DAO-CONTROL
                                          WS-CUSTOMER
               ON EXCEPTION
                   SET DAO-ST-IO-ERROR TO TRUE
                   MOVE WS-REASON-MODULE-MISSING TO DAO-TECH-CODE
           END-CALL
           EVALUATE TRUE
               WHEN DAO-ST-OK
                   CONTINUE
               WHEN DAO-ST-NOT-FOUND
                   SET WS-RC-CUSTOMER-NOT-FOUND TO TRUE
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
               PERFORM 8100-MASK-DOCUMENT
               MOVE CUS-CUSTOMER-ID      TO CRS-CI-CUSTOMER-ID
               MOVE CUS-CUSTOMER-NAME    TO CRS-CI-CUSTOMER-NAME
               MOVE CUS-CUSTOMER-STATUS  TO CRS-CI-CUSTOMER-STATUS
               MOVE WS-MASKED-DOCUMENT   TO CRS-CI-DOCUMENT-MASKED
               MOVE CUS-REGISTERED-DATE  TO CRS-CI-REGISTERED-DATE
           END-IF
           .

      *    ONLY THE LAST TWO DIGITS OF THE NATIONAL ID ARE EXPOSED.
       8100-MASK-DOCUMENT.
           STRING WS-DOCUMENT-MASK
                  CUS-DOCUMENT(10:2)
                  DELIMITED BY SIZE
                  INTO WS-MASKED-DOCUMENT
           END-STRING
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
