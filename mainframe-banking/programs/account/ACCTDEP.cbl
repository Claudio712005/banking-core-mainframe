       IDENTIFICATION DIVISION.
       PROGRAM-ID. ACCTDEP.
      *================================================================*
      * PROGRAM  : ACCTDEP                                             *
      * TYPE     : ENTRY PROGRAM (ONE PER BUSINESS OPERATION)          *
      * PURPOSE  : DEPOSIT INTO AN ACCOUNT.                            *
      * INPUT    : REQUEST  (OPERATION ACCTDEP, BODY REQ-POSTING)      *
      * OUTPUT   : RESPONSE (BODY RSP-POSTING)                         *
      *----------------------------------------------------------------*
      * DESIGN   : THE POSTING LOGIC IS SHARED WITH ACCTWDR AND LIVES  *
      *            IN ACCTPOST. THIS PROGRAM EXISTS AS A SEPARATE      *
      *            DEPLOYABLE ENTRY POINT SO THAT, UNDER CICS, DEPOSIT *
      *            AND WITHDRAWAL CAN HAVE DISTINCT TRANSACTION IDS,   *
      *            SECURITY PROFILES (RACF) AND MONITORING.            *
      * Z/OS CICS: LINKAGE BECOMES DFHCOMMAREA (OR A CHANNEL WITH      *
      *            REQUEST/RESPONSE CONTAINERS); GOBACK BECOMES        *
      *            EXEC CICS RETURN.                                   *
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
           SET PST-DEPOSIT TO TRUE
           CALL WS-PGM-POSTING-ENGINE USING LK-REQUEST
                                            LK-RESPONSE
                                            WS-POSTING-CONTROL
               ON EXCEPTION
                   MOVE SPACES TO LK-RESPONSE
           END-CALL
           GOBACK
           .
