       IDENTIFICATION DIVISION.
       PROGRAM-ID. BKRESP.
      *================================================================*
      * PROGRAM  : BKRESP                                              *
      * TYPE     : CALLABLE SUBPROGRAM (NO FILE I/O)                   *
      * PURPOSE  : BUILDS THE STANDARD RESPONSE HEADER.                *
      *            - OWNS THE RESPONSE-CODE -> MESSAGE TABLE.          *
      *            - GUARANTEES THAT ONLY DOCUMENTED CODES ARE SENT.   *
      *            - WRITES ONE TECHNICAL LOG LINE FOR 3XXX/9XXX.      *
      * INTERFACE: CALL 'BKRESP' USING RSPCTL-AREA REQUEST RESPONSE    *
      * SECURITY : LOG LINES CONTAIN ONLY PROGRAM, CODES AND THE       *
      *            CORRELATION-ID. NO ACCOUNT, AMOUNT OR CUSTOMER DATA.*
      * Z/OS     : UNDER CICS, REPLACE THE DISPLAY IN                  *
      *            9000-WRITE-TECHNICAL-LOG BY WRITEQ TD (OR THE       *
      *            INSTALLATION LOGGING SERVICE). DISPLAY IS NOT       *
      *            APPROPRIATE FOR CICS APPLICATION LOGGING.           *
      *================================================================*
       ENVIRONMENT DIVISION.

       DATA DIVISION.
       WORKING-STORAGE SECTION.
       01  WS-CONSTANTS.
           05  WS-CURRENT-LAYOUT-VERSION    PIC X(02) VALUE '01'.
           05  WS-UNEXPECTED-ERROR-CODE     PIC X(04) VALUE '9999'.
           05  WS-LOG-EVENT-NAME            PIC X(16)
                                            VALUE 'TECHNICAL EVENT '.

      *----------------------------------------------------------------*
      * STANDARD MESSAGES. ONE ENTRY PER CODE IN COPYBOOK RSPCODE.     *
      * TEXT IS UPPERCASE WITHOUT ACCENTS TO SURVIVE ANY CODE PAGE.    *
      *----------------------------------------------------------------*
       01  WS-MESSAGE-TABLE-DATA.
           05  FILLER PIC X(04) VALUE '0000'.
           05  FILLER PIC X(60) VALUE
               'OPERATION COMPLETED SUCCESSFULLY'.
           05  FILLER PIC X(04) VALUE '0001'.
           05  FILLER PIC X(60) VALUE
               'DUPLICATE REQUEST - ORIGINAL RESULT RETURNED'.
           05  FILLER PIC X(04) VALUE '1001'.
           05  FILLER PIC X(60) VALUE
               'INVALID REQUEST LAYOUT OR OPERATION'.
           05  FILLER PIC X(04) VALUE '1002'.
           05  FILLER PIC X(60) VALUE
               'INVALID ACCOUNT IDENTIFIER'.
           05  FILLER PIC X(04) VALUE '1003'.
           05  FILLER PIC X(60) VALUE
               'INVALID AMOUNT FORMAT'.
           05  FILLER PIC X(04) VALUE '1004'.
           05  FILLER PIC X(60) VALUE
               'AMOUNT MUST BE GREATER THAN ZERO'.
           05  FILLER PIC X(04) VALUE '1005'.
           05  FILLER PIC X(60) VALUE
               'AMOUNT EXCEEDS TRANSACTION LIMIT'.
           05  FILLER PIC X(04) VALUE '1006'.
           05  FILLER PIC X(60) VALUE
               'INVALID IDEMPOTENCY KEY'.
           05  FILLER PIC X(04) VALUE '1007'.
           05  FILLER PIC X(60) VALUE
               'INVALID TRANSACTION IDENTIFIER'.
           05  FILLER PIC X(04) VALUE '1008'.
           05  FILLER PIC X(60) VALUE
               'INVALID CURRENCY CODE'.
           05  FILLER PIC X(04) VALUE '2001'.
           05  FILLER PIC X(60) VALUE
               'ACCOUNT NOT FOUND'.
           05  FILLER PIC X(04) VALUE '2002'.
           05  FILLER PIC X(60) VALUE
               'ACCOUNT IS NOT ACTIVE'.
           05  FILLER PIC X(04) VALUE '2003'.
           05  FILLER PIC X(60) VALUE
               'INSUFFICIENT FUNDS'.
           05  FILLER PIC X(04) VALUE '2004'.
           05  FILLER PIC X(60) VALUE
               'OPERATION WOULD EXCEED BALANCE LIMIT'.
           05  FILLER PIC X(04) VALUE '2005'.
           05  FILLER PIC X(60) VALUE
               'TRANSACTION NOT FOUND'.
           05  FILLER PIC X(04) VALUE '2006'.
           05  FILLER PIC X(60) VALUE
               'CUSTOMER IS NOT ACTIVE'.
           05  FILLER PIC X(04) VALUE '2007'.
           05  FILLER PIC X(60) VALUE
               'IDEMPOTENCY KEY ALREADY USED FOR A DIFFERENT OPERATION'.
           05  FILLER PIC X(04) VALUE '2008'.
           05  FILLER PIC X(60) VALUE
               'CURRENCY DOES NOT MATCH ACCOUNT CURRENCY'.
           05  FILLER PIC X(04) VALUE '3001'.
           05  FILLER PIC X(60) VALUE
               'CONCURRENT UPDATE DETECTED - RETRY WITH SAME KEY'.
           05  FILLER PIC X(04) VALUE '9001'.
           05  FILLER PIC X(60) VALUE
               'DATA ACCESS FAILURE - OPERATION NOT COMPLETED'.
           05  FILLER PIC X(04) VALUE '9002'.
           05  FILLER PIC X(60) VALUE
               'DATA INTEGRITY FAILURE - OPERATION NOT COMPLETED'.
           05  FILLER PIC X(04) VALUE '9003'.
           05  FILLER PIC X(60) VALUE
               'POSTING STATE UNCERTAIN - DO NOT RETRY - CALL SUPPORT'.
           05  FILLER PIC X(04) VALUE '9004'.
           05  FILLER PIC X(60) VALUE
               'RETRIES EXHAUSTED - OPERATION NOT COMPLETED'.
           05  FILLER PIC X(04) VALUE '9999'.
           05  FILLER PIC X(60) VALUE
               'UNEXPECTED ERROR - OPERATION NOT COMPLETED'.

       01  WS-MESSAGE-TABLE REDEFINES WS-MESSAGE-TABLE-DATA.
           05  WS-MESSAGE-ENTRY OCCURS 24 TIMES
                                INDEXED BY WS-MSG-IDX.
               10  WS-MSG-CODE              PIC X(04).
               10  WS-MSG-TEXT              PIC X(60).

       01  WS-RESULT.
           COPY RSPCODE REPLACING ==:TAG:== BY ==WS==.

       LINKAGE SECTION.
       01  LK-RESPONSE-CONTROL.
           COPY RSPCTL REPLACING ==:TAG:== BY ==LKR==.
       01  LK-REQUEST.
           COPY REQUEST.
       01  LK-RESPONSE.
           COPY RESPONSE.

       PROCEDURE DIVISION USING LK-RESPONSE-CONTROL
                                LK-REQUEST
                                LK-RESPONSE.
      *================================================================*
       0000-MAIN.
           EVALUATE TRUE
               WHEN LKR-FN-INIT
                   PERFORM 1000-INITIALIZE-RESPONSE
               WHEN LKR-FN-FINISH
                   PERFORM 2000-FINISH-RESPONSE
               WHEN OTHER
                   MOVE WS-UNEXPECTED-ERROR-CODE TO LKR-RESPONSE-CODE
                   PERFORM 2000-FINISH-RESPONSE
           END-EVALUATE
           GOBACK
           .

      *----------------------------------------------------------------*
      * HEADER FIELDS ARE ECHOED BYTE-FOR-BYTE; THEY ARE OPAQUE HERE.  *
      *----------------------------------------------------------------*
       1000-INITIALIZE-RESPONSE.
           MOVE SPACES                    TO LK-RESPONSE
           MOVE WS-CURRENT-LAYOUT-VERSION TO RSP-LAYOUT-VERSION
           MOVE REQ-OPERATION-CODE        TO RSP-OPERATION-CODE
           MOVE REQ-CORRELATION-ID        TO RSP-CORRELATION-ID
           .

       2000-FINISH-RESPONSE.
           PERFORM 2100-RESOLVE-MESSAGE
           MOVE WS-RESPONSE-CODE          TO RSP-RESPONSE-CODE
           MOVE WS-MSG-TEXT(WS-MSG-IDX)   TO RSP-RESPONSE-MESSAGE
           MOVE WS-RESPONSE-CODE          TO LKR-RESPONSE-CODE
           IF NOT WS-RC-CAT-SUCCESS
               MOVE SPACES TO RSP-BODY
           END-IF
           IF WS-RC-CAT-RETRYABLE OR WS-RC-CAT-TECHNICAL
               PERFORM 9000-WRITE-TECHNICAL-LOG
           END-IF
           .

      *----------------------------------------------------------------*
      * FAIL-SAFE: AN UNDOCUMENTED CODE IS NEVER SENT TO THE CLIENT.   *
      *----------------------------------------------------------------*
       2100-RESOLVE-MESSAGE.
           MOVE LKR-RESPONSE-CODE TO WS-RESPONSE-CODE
           SET WS-MSG-IDX TO 1
           SEARCH WS-MESSAGE-ENTRY
               AT END
                   SET WS-RC-UNEXPECTED-ERROR TO TRUE
                   PERFORM 2200-FIND-UNEXPECTED-ERROR
               WHEN WS-MSG-CODE(WS-MSG-IDX) = WS-RESPONSE-CODE
                   CONTINUE
           END-SEARCH
           .

       2200-FIND-UNEXPECTED-ERROR.
           SET WS-MSG-IDX TO 1
           SEARCH WS-MESSAGE-ENTRY
               WHEN WS-MSG-CODE(WS-MSG-IDX) = WS-RESPONSE-CODE
                   CONTINUE
           END-SEARCH
           .

       9000-WRITE-TECHNICAL-LOG.
           DISPLAY LKR-PROGRAM-ID ' '
                   WS-LOG-EVENT-NAME
                   'RC=' WS-RESPONSE-CODE
                   ' TECH=' LKR-TECH-CODE
                   ' CORR=' RSP-CORRELATION-ID
           .
