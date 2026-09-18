       IDENTIFICATION DIVISION.
       PROGRAM-ID. CSTVAL.
      *================================================================*
      * PROGRAM  : CSTVAL                                              *
      * TYPE     : CALLABLE SUBPROGRAM (NO I/O, NO STATE)              *
      * PURPOSE  : SYNTACTIC VALIDATION OF THE CUSTOMER IDENTIFIER.    *
      * INTERFACE: CALL 'CSTVAL' USING CUSTOMER-ID  PIC X(10)          *
      *                               RESULT-CODE  PIC X(04)           *
      * RETURNS  : '0000' WHEN VALID, '1002' OTHERWISE.                *
      *================================================================*
       ENVIRONMENT DIVISION.

       DATA DIVISION.
       WORKING-STORAGE SECTION.
       01  WS-RESULT.
           COPY CSTCODE REPLACING ==:TAG:== BY ==WS==.

       LINKAGE SECTION.
       01  LK-CUSTOMER-ID                   PIC X(10).
       01  LK-RESULT-CODE                   PIC X(04).

       PROCEDURE DIVISION USING LK-CUSTOMER-ID
                                LK-RESULT-CODE.
       0000-MAIN.
           SET WS-RC-SUCCESS TO TRUE
           IF LK-CUSTOMER-ID IS NOT NUMERIC
              OR LK-CUSTOMER-ID = ALL '0'
               SET WS-RC-INVALID-CUSTOMER-ID TO TRUE
           END-IF
           MOVE WS-RESPONSE-CODE TO LK-RESULT-CODE
           GOBACK
           .
