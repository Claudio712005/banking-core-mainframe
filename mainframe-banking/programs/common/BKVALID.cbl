       IDENTIFICATION DIVISION.
       PROGRAM-ID. BKVALID.
      *================================================================*
      * PROGRAM  : BKVALID                                             *
      * TYPE     : CALLABLE SUBPROGRAM (NO I/O, NO STATE)              *
      * PURPOSE  : SYNTACTIC VALIDATION OF UNTRUSTED INPUT FIELDS.     *
      *            BUSINESS RULES (ACCOUNT EXISTS, BALANCE, ETC.) ARE  *
      *            NOT CHECKED HERE.                                   *
      * INTERFACE: CALL 'BKVALID' USING VALCTL-AREA                    *
      * RETURNS  : VALCTL RESULT-CODE = '0000' OR A 1XXX CODE.         *
      *            AN UNKNOWN FUNCTION RETURNS 9999 (PROGRAMMING ERROR)*
      * PORTABLE : CHARACTER CLASSES ARE DECLARED AS EXPLICIT RANGES   *
      *            ('A' THRU 'I' 'J' THRU 'R' 'S' THRU 'Z') BECAUSE    *
      *            'A' THRU 'Z' ALSO MATCHES NON-LETTERS IN EBCDIC.    *
      *================================================================*
       ENVIRONMENT DIVISION.
       CONFIGURATION SECTION.
       SPECIAL-NAMES.
           CLASS BK-UPPERCASE-LETTER IS 'A' THRU 'I'
                                        'J' THRU 'R'
                                        'S' THRU 'Z'
           CLASS BK-IDEMPOTENCY-KEY-CHAR IS 'A' THRU 'I'
                                            'J' THRU 'R'
                                            'S' THRU 'Z'
                                            'a' THRU 'i'
                                            'j' THRU 'r'
                                            's' THRU 'z'
                                            '0' THRU '9'
                                            '-'.

       DATA DIVISION.
       WORKING-STORAGE SECTION.
      *----------------------------------------------------------------*
      * BUSINESS PARAMETERS.                                           *
      * Z/OS: READ FROM A PARAMETER TABLE INSTEAD OF BEING COMPILED IN.*
      *----------------------------------------------------------------*
       01  WS-VALIDATION-LIMITS.
           05  WS-MAX-TRANSACTION-AMOUNT    PIC S9(13)V99 COMP-3
                                            VALUE +1000000.00.
           05  WS-IDEMP-KEY-MIN-LENGTH      PIC S9(04) COMP
                                            VALUE +16.

       01  WS-WORK-AREAS.
           05  WS-AMOUNT                    PIC S9(13)V99 COMP-3.
           05  WS-KEY-TRAILING-SPACES       PIC S9(04) COMP.
           05  WS-KEY-LENGTH                PIC S9(04) COMP.

       01  WS-RESULT.
           COPY RSPCODE REPLACING ==:TAG:== BY ==WS==.

       LINKAGE SECTION.
       01  LK-VALIDATION.
           COPY VALCTL REPLACING ==:TAG:== BY ==LKV==.

       PROCEDURE DIVISION USING LK-VALIDATION.
      *================================================================*
       0000-MAIN.
           SET WS-RC-SUCCESS TO TRUE
           EVALUATE TRUE
               WHEN LKV-FN-ACCOUNT-ID
                   PERFORM 1000-VALIDATE-ACCOUNT-ID
               WHEN LKV-FN-TRANSACTION-ID
                   PERFORM 2000-VALIDATE-TRANSACTION-ID
               WHEN LKV-FN-AMOUNT
                   PERFORM 3000-VALIDATE-AMOUNT
               WHEN LKV-FN-IDEMPOTENCY-KEY
                   PERFORM 4000-VALIDATE-IDEMPOTENCY-KEY
               WHEN LKV-FN-CURRENCY
                   PERFORM 5000-VALIDATE-CURRENCY
               WHEN OTHER
                   SET WS-RC-UNEXPECTED-ERROR TO TRUE
           END-EVALUATE
           MOVE WS-RESPONSE-CODE TO LKV-RESULT-CODE
           GOBACK
           .

      *----------------------------------------------------------------*
      * ACCOUNT-ID: EXACTLY 10 DIGITS, NOT ALL ZEROS.                  *
      *----------------------------------------------------------------*
       1000-VALIDATE-ACCOUNT-ID.
           IF LKV-ACCOUNT-ID IS NOT NUMERIC
              OR LKV-ACCOUNT-ID = ALL '0'
               SET WS-RC-INVALID-ACCOUNT-ID TO TRUE
           END-IF
           .

      *----------------------------------------------------------------*
      * TRANSACTION-ID: EXACTLY 16 DIGITS, NOT ALL ZEROS.              *
      *----------------------------------------------------------------*
       2000-VALIDATE-TRANSACTION-ID.
           IF LKV-TRANSACTION-ID IS NOT NUMERIC
              OR LKV-TRANSACTION-ID = ALL '0'
               SET WS-RC-INVALID-TRX-ID TO TRUE
           END-IF
           .

      *----------------------------------------------------------------*
      * AMOUNT: EXPLICIT SIGN ('+' OR '-') FOLLOWED BY 15 DIGITS,      *
      * 2 IMPLIED DECIMALS. MUST BE > 0 AND <= TRANSACTION LIMIT.      *
      * THE NUMERIC TEST RUNS BEFORE ANY ARITHMETIC TO AVOID DATA      *
      * EXCEPTIONS (S0C7 ON Z/OS) CAUSED BY UNTRUSTED CONTENT.         *
      *----------------------------------------------------------------*
       3000-VALIDATE-AMOUNT.
           IF LKV-AMOUNT IS NOT NUMERIC
               SET WS-RC-INVALID-AMOUNT TO TRUE
           ELSE
               MOVE LKV-AMOUNT TO WS-AMOUNT
               EVALUATE TRUE
                   WHEN WS-AMOUNT NOT > ZERO
                       SET WS-RC-AMOUNT-NOT-POSITIVE TO TRUE
                   WHEN WS-AMOUNT > WS-MAX-TRANSACTION-AMOUNT
                       SET WS-RC-AMOUNT-OVER-LIMIT TO TRUE
                   WHEN OTHER
                       CONTINUE
               END-EVALUATE
           END-IF
           .

      *----------------------------------------------------------------*
      * IDEMPOTENCY-KEY: LEFT-JUSTIFIED, TRAILING SPACES ONLY,         *
      * MINIMUM LENGTH, CHARACTERS [A-Z a-z 0-9 -] (UUID COMPATIBLE).  *
      *----------------------------------------------------------------*
       4000-VALIDATE-IDEMPOTENCY-KEY.
           MOVE ZERO TO WS-KEY-TRAILING-SPACES
           INSPECT FUNCTION REVERSE(LKV-IDEMPOTENCY-KEY)
               TALLYING WS-KEY-TRAILING-SPACES FOR LEADING SPACES
           COMPUTE WS-KEY-LENGTH =
                   LENGTH OF LKV-IDEMPOTENCY-KEY
                 - WS-KEY-TRAILING-SPACES
           END-COMPUTE
           EVALUATE TRUE
               WHEN WS-KEY-LENGTH < WS-IDEMP-KEY-MIN-LENGTH
                   SET WS-RC-INVALID-IDEMP-KEY TO TRUE
               WHEN LKV-IDEMPOTENCY-KEY(1:WS-KEY-LENGTH)
                       IS NOT BK-IDEMPOTENCY-KEY-CHAR
                   SET WS-RC-INVALID-IDEMP-KEY TO TRUE
               WHEN OTHER
                   CONTINUE
           END-EVALUATE
           .

      *----------------------------------------------------------------*
      * CURRENCY: 3 UPPERCASE LETTERS (ISO 4217 ALPHABETIC FORMAT).    *
      * WHETHER THE CURRENCY MATCHES THE ACCOUNT IS A BUSINESS RULE.   *
      *----------------------------------------------------------------*
       5000-VALIDATE-CURRENCY.
           IF LKV-CURRENCY IS NOT BK-UPPERCASE-LETTER
               SET WS-RC-INVALID-CURRENCY TO TRUE
           END-IF
           .
