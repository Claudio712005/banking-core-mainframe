       IDENTIFICATION DIVISION.
       PROGRAM-ID. ACCTWDR.
      *================================================================*
      * PROGRAM  : ACCTWDR                                             *
      * TYPE     : ENTRY PROGRAM (ONE PER BUSINESS OPERATION)          *
      * PURPOSE  : WITHDRAWAL FROM AN ACCOUNT.                         *
      * INPUT    : REQUEST  (OPERATION ACCTWDR, BODY REQ-POSTING)      *
      * OUTPUT   : RESPONSE (BODY RSP-POSTING)                         *
      * RULES    : ENFORCED BY ACCTPOST                                *
      *            - ACCOUNT EXISTS AND IS ACTIVE                      *
      *            - CUSTOMER IS ACTIVE                                *
      *            - AMOUNT > 0 AND WITHIN THE TRANSACTION LIMIT       *
      *            - AMOUNT <= BALANCE (NO OVERDRAFT)                  *
      *            - ONE IDEMPOTENCY-KEY = AT MOST ONE POSTING         *
      *            - ACCOUNT UPDATE + JOURNAL INSERT ARE ONE UNIT      *
      * DESIGN   : SEE ACCTDEP.                                        *
      *================================================================*
       ENVIRONMENT DIVISION.

       DATA DIVISION.
       WORKING-STORAGE SECTION.
       01  WS-PGM-POSTING-ENGINE            PIC X(08) VALUE 'ACCTPOST'.

       01  WS-POSTING-CONTROL.
           COPY PSTCTL REPLACING ==:TAG:== BY ==PST==.

       LINKAGE SECTION.
       01  LK-REQUEST.
           COPY REQUEST.
       01  LK-RESPONSE.
           COPY RESPONSE.

       PROCEDURE DIVISION USING LK-REQUEST
                                LK-RESPONSE.
      *================================================================*
       0000-MAIN.
           SET PST-WITHDRAWAL TO TRUE
           CALL WS-PGM-POSTING-ENGINE USING LK-REQUEST
                                            LK-RESPONSE
                                            WS-POSTING-CONTROL
               ON EXCEPTION
                   MOVE SPACES TO LK-RESPONSE
           END-CALL
           GOBACK
           .
