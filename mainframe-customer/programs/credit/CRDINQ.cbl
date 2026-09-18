       IDENTIFICATION DIVISION.
       PROGRAM-ID. CRDINQ.
      *================================================================*
      * PROGRAM  : CRDINQ                                              *
      * TYPE     : ENTRY PROGRAM (READ-ONLY)                           *
      * PURPOSE  : CREDIT LIMIT INQUIRY.                               *
      * INPUT    : REQUEST  (OPERATION CRDINQ, CUSTOMER-ID)            *
      * OUTPUT   : RESPONSE (BODY CRS-CREDIT-INQUIRY)                  *
      * RULES    : - CUSTOMER MUST EXIST (2001)                        *
      *            - CUSTOMER MUST BE ACTIVE (2002): A BLOCKED OR      *
      *              INACTIVE CUSTOMER HAS NO USABLE CREDIT            *
      *            - CUSTOMER MUST HAVE A CREDIT LINE (2003)           *
      *            AVAILABLE = APPROVED - USED, COMPUTED HERE AND      *
      *            NEVER STORED, SO IT CANNOT GO STALE.                *
      *================================================================*
       ENVIRONMENT DIVISION.

       DATA DIVISION.
       WORKING-STORAGE SECTION.
       01  WS-PROGRAM-NAMES.
           05  WS-THIS-PROGRAM              PIC X(08) VALUE 'CRDINQ'.
           05  WS-PGM-VALIDATOR             PIC X(08) VALUE 'CSTVAL'.
           05  WS-PGM-RESPONSE-BUILDER      PIC X(08) VALUE 'CSTRESP'.
           05  WS-PGM-CUSTOMER-DAO          PIC X(08) VALUE 'CUSTDAO'.
           05  WS-PGM-CREDIT-DAO            PIC X(08) VALUE 'CREDDAO'.

       01  WS-CONSTANTS.
           05  WS-REASON-MODULE-MISSING     PIC X(08) VALUE 'NOMODULE'.

       01  WS-RESULT.
           COPY CSTCODE REPLACING ==:TAG:== BY ==WS==.

       01  WS-TECH-CODE                     PIC X(08).
       01  WS-VALIDATION-CODE               PIC X(04).

       01  WS-MONETARY-WORK.
           05  WS-APPROVED-LIMIT            PIC S9(13)V99 COMP-3.
           05  WS-USED-LIMIT                PIC S9(13)V99 COMP-3.
           05  WS-AVAILABLE-LIMIT           PIC S9(13)V99 COMP-3.

       01  WS-RESPONSE-CONTROL.
           COPY CSTCTL REPLACING ==:TAG:== BY ==RCT==.

       01  WS-DAO-CONTROL.
           COPY CSTDAO REPLACING ==:TAG:== BY ==DAO==.

       01  WS-CUSTOMER.
           COPY CUSTREC REPLACING ==:TAG:== BY ==CUS==.

       01  WS-CREDIT.
           COPY CREDREC REPLACING ==:TAG:== BY ==CRD==.

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
               PERFORM 3000-VERIFY-CUSTOMER
           END-IF
           IF WS-RC-SUCCESS
               PERFORM 4000-LOAD-CREDIT
           END-IF
           IF WS-RC-SUCCESS
               PERFORM 5000-COMPUTE-AVAILABLE
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
                      WS-CREDIT
                      WS-MONETARY-WORK
                      WS-RESPONSE-CONTROL
                      WITH FILLER
           SET RCT-FN-INIT TO TRUE
           PERFORM 8900-CALL-RESPONSE-BUILDER
           .

       2000-VALIDATE-INPUT.
           IF NOT CRQ-LAYOUT-V01
              OR NOT CRQ-OP-CREDIT-INQUIRY
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

       3000-VERIFY-CUSTOMER.
           MOVE CRQ-CUSTOMER-ID TO CUS-CUSTOMER-ID
           INITIALIZE WS-DAO-CONTROL
           SET DAO-FN-READ TO TRUE
           CALL WS-PGM-CUSTOMER-DAO USING WS-DAO-CONTROL
                                          WS-CUSTOMER
               ON EXCEPTION
                   SET DAO-ST-IO-ERROR TO TRUE
                   MOVE WS-REASON-MODULE-MISSING TO DAO-TECH-CODE
           END-CALL
           EVALUATE TRUE
               WHEN DAO-ST-OK
                   IF NOT CUS-STATUS-ACTIVE
                       SET WS-RC-CUSTOMER-NOT-ACTIVE TO TRUE
                   END-IF
               WHEN DAO-ST-NOT-FOUND
                   SET WS-RC-CUSTOMER-NOT-FOUND TO TRUE
               WHEN OTHER
                   PERFORM 7900-HANDLE-DAO-FAILURE
           END-EVALUATE
           .

       4000-LOAD-CREDIT.
           MOVE CRQ-CUSTOMER-ID TO CRD-CUSTOMER-ID
           INITIALIZE WS-DAO-CONTROL
           SET DAO-FN-READ TO TRUE
           CALL WS-PGM-CREDIT-DAO USING WS-DAO-CONTROL
                                        WS-CREDIT
               ON EXCEPTION
                   SET DAO-ST-IO-ERROR TO TRUE
                   MOVE WS-REASON-MODULE-MISSING TO DAO-TECH-CODE
           END-CALL
           EVALUATE TRUE
               WHEN DAO-ST-OK
                   CONTINUE
               WHEN DAO-ST-NOT-FOUND
                   SET WS-RC-NO-CREDIT-LINE TO TRUE
               WHEN OTHER
                   PERFORM 7900-HANDLE-DAO-FAILURE
           END-EVALUATE
           .

       5000-COMPUTE-AVAILABLE.
           MOVE CRD-APPROVED-LIMIT TO WS-APPROVED-LIMIT
           MOVE CRD-USED-LIMIT     TO WS-USED-LIMIT
           SUBTRACT WS-USED-LIMIT FROM WS-APPROVED-LIMIT
               GIVING WS-AVAILABLE-LIMIT
           END-SUBTRACT
           IF WS-AVAILABLE-LIMIT < ZERO
               SET WS-RC-DATA-INTEGRITY-ERROR TO TRUE
           END-IF
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

       8000-BUILD-RESPONSE.
           IF WS-RC-SUCCESS
               MOVE CRD-CUSTOMER-ID    TO CRS-CR-CUSTOMER-ID
               MOVE CRD-CURRENCY       TO CRS-CR-CURRENCY
               MOVE WS-APPROVED-LIMIT  TO CRS-CR-APPROVED-LIMIT
               MOVE WS-USED-LIMIT      TO CRS-CR-USED-LIMIT
               MOVE WS-AVAILABLE-LIMIT TO CRS-CR-AVAILABLE-LIMIT
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
