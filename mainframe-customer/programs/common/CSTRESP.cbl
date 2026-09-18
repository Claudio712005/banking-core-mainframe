       IDENTIFICATION DIVISION.
       PROGRAM-ID. CSTRESP.
      *================================================================*
      * PROGRAM  : CSTRESP                                             *
      * TYPE     : CALLABLE SUBPROGRAM (NO FILE I/O)                   *
      * PURPOSE  : BUILDS THE STANDARD RESPONSE HEADER.                *
      *            - OWNS THE RESPONSE-CODE -> MESSAGE TABLE.          *
      *            - GUARANTEES THAT ONLY DOCUMENTED CODES ARE SENT.   *
      *            - WRITES ONE TECHNICAL LOG LINE FOR 9XXX CODES.     *
      * INTERFACE: CALL 'CSTRESP' USING CSTCTL-AREA REQUEST RESPONSE   *
      * SECURITY : LOG LINES CARRY PROGRAM, CODES AND THE CORRELATION  *
      *            ID ONLY, AND THE ID IS REPLACED WHEN IT CONTAINS    *
      *            CHARACTERS THAT ARE UNSAFE FOR A LOG.               *
      *================================================================*
       ENVIRONMENT DIVISION.
       CONFIGURATION SECTION.
       SPECIAL-NAMES.
           CLASS CST-LOG-SAFE-CHAR IS 'A' THRU 'I'
                                      'J' THRU 'R'
                                      'S' THRU 'Z'
                                      'a' THRU 'i'
                                      'j' THRU 'r'
                                      's' THRU 'z'
                                      '0' THRU '9'
                                      '-' ' '.

       DATA DIVISION.
       WORKING-STORAGE SECTION.
       01  WS-CONSTANTS.
           05  WS-CURRENT-LAYOUT-VERSION    PIC X(02) VALUE '01'.
           05  WS-UNEXPECTED-ERROR-CODE     PIC X(04) VALUE '9999'.
           05  WS-LOG-EVENT-NAME            PIC X(16)
                                            VALUE 'TECHNICAL EVENT '.
           05  WS-UNSAFE-VALUE              PIC X(08) VALUE 'INVALID'.

       01  WS-LOG-CORRELATION               PIC X(36).

       01  WS-MESSAGE-TABLE-DATA.
           05  FILLER PIC X(04) VALUE '0000'.
           05  FILLER PIC X(60) VALUE
               'OPERATION COMPLETED SUCCESSFULLY'.
           05  FILLER PIC X(04) VALUE '1001'.
           05  FILLER PIC X(60) VALUE
               'INVALID REQUEST LAYOUT OR OPERATION'.
           05  FILLER PIC X(04) VALUE '1002'.
           05  FILLER PIC X(60) VALUE
               'INVALID CUSTOMER IDENTIFIER'.
           05  FILLER PIC X(04) VALUE '2001'.
           05  FILLER PIC X(60) VALUE
               'CUSTOMER NOT FOUND'.
           05  FILLER PIC X(04) VALUE '2002'.
           05  FILLER PIC X(60) VALUE
               'CUSTOMER IS NOT ACTIVE'.
           05  FILLER PIC X(04) VALUE '2003'.
           05  FILLER PIC X(60) VALUE
               'CUSTOMER HAS NO CREDIT LINE'.
           05  FILLER PIC X(04) VALUE '9001'.
           05  FILLER PIC X(60) VALUE
               'DATA ACCESS FAILURE - REQUEST NOT COMPLETED'.
           05  FILLER PIC X(04) VALUE '9002'.
           05  FILLER PIC X(60) VALUE
               'DATA INTEGRITY FAILURE - REQUEST NOT COMPLETED'.
           05  FILLER PIC X(04) VALUE '9999'.
           05  FILLER PIC X(60) VALUE
               'UNEXPECTED ERROR - REQUEST NOT COMPLETED'.

       01  WS-MESSAGE-TABLE REDEFINES WS-MESSAGE-TABLE-DATA.
           05  WS-MESSAGE-ENTRY OCCURS 9 TIMES
                                INDEXED BY WS-MSG-IDX.
               10  WS-MSG-CODE              PIC X(04).
               10  WS-MSG-TEXT              PIC X(60).

       01  WS-RESULT.
           COPY CSTCODE REPLACING ==:TAG:== BY ==WS==.

       LINKAGE SECTION.
       01  LK-RESPONSE-CONTROL.
           COPY CSTCTL REPLACING ==:TAG:== BY ==LKR==.
       01  LK-REQUEST.
           COPY CUSTREQ.
       01  LK-RESPONSE.
           COPY CUSTRSP.

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

       1000-INITIALIZE-RESPONSE.
           MOVE SPACES                    TO LK-RESPONSE
           MOVE WS-CURRENT-LAYOUT-VERSION TO CRS-LAYOUT-VERSION
           MOVE CRQ-OPERATION-CODE        TO CRS-OPERATION-CODE
           MOVE CRQ-CORRELATION-ID        TO CRS-CORRELATION-ID
           .

       2000-FINISH-RESPONSE.
           PERFORM 2100-RESOLVE-MESSAGE
           MOVE WS-RESPONSE-CODE        TO CRS-RESPONSE-CODE
           MOVE WS-MSG-TEXT(WS-MSG-IDX) TO CRS-RESPONSE-MESSAGE
           MOVE WS-RESPONSE-CODE        TO LKR-RESPONSE-CODE
           IF NOT WS-RC-CAT-SUCCESS
               MOVE SPACES TO CRS-BODY
           END-IF
           IF WS-RC-CAT-TECHNICAL
               PERFORM 9000-WRITE-TECHNICAL-LOG
           END-IF
           .

      *    FAIL-SAFE: AN UNDOCUMENTED CODE IS NEVER SENT TO THE CLIENT.
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
           IF CRS-CORRELATION-ID IS CST-LOG-SAFE-CHAR
               MOVE CRS-CORRELATION-ID TO WS-LOG-CORRELATION
           ELSE
               MOVE WS-UNSAFE-VALUE    TO WS-LOG-CORRELATION
           END-IF
           DISPLAY LKR-PROGRAM-ID ' '
                   WS-LOG-EVENT-NAME
                   'RC=' WS-RESPONSE-CODE
                   ' TECH=' LKR-TECH-CODE
                   ' CORR=' WS-LOG-CORRELATION
           .
