      *================================================================*
      * COPYBOOK : RSPCODE                                             *
      * PURPOSE  : SINGLE SOURCE OF TRUTH FOR RESPONSE CODES.          *
      *            MESSAGE TEXTS LIVE IN PROGRAM BKRESP.               *
      * FORMAT   : 4 DIGITS. FIRST DIGIT IS THE CATEGORY:              *
      *            0 = SUCCESS        1 = INPUT VALIDATION REJECT      *
      *            2 = BUSINESS REJECT                                 *
      *            3 = TRANSIENT, CLIENT MAY RETRY WITH SAME KEY       *
      *            9 = TECHNICAL FAILURE                               *
      * USAGE    : 01  WS-RESULT.                                      *
      *                COPY RSPCODE REPLACING ==:TAG:== BY ==WS==.     *
      *================================================================*
           05  :TAG:-RESPONSE-CODE          PIC X(04).
      *        --- CATEGORIES ------------------------------------------
               88  :TAG:-RC-CAT-SUCCESS              VALUE '0000'
                                                      THRU '0999'.
               88  :TAG:-RC-CAT-VALIDATION           VALUE '1000'
                                                      THRU '1999'.
               88  :TAG:-RC-CAT-BUSINESS             VALUE '2000'
                                                      THRU '2999'.
               88  :TAG:-RC-CAT-RETRYABLE            VALUE '3000'
                                                      THRU '3999'.
               88  :TAG:-RC-CAT-TECHNICAL            VALUE '9000'
                                                      THRU '9999'.
      *        --- 0XXX SUCCESS ----------------------------------------
               88  :TAG:-RC-SUCCESS                  VALUE '0000'.
               88  :TAG:-RC-DUPLICATE-REPLAYED       VALUE '0001'.
      *        --- 1XXX INPUT VALIDATION -------------------------------
               88  :TAG:-RC-INVALID-REQUEST          VALUE '1001'.
               88  :TAG:-RC-INVALID-ACCOUNT-ID       VALUE '1002'.
               88  :TAG:-RC-INVALID-AMOUNT           VALUE '1003'.
               88  :TAG:-RC-AMOUNT-NOT-POSITIVE      VALUE '1004'.
               88  :TAG:-RC-AMOUNT-OVER-LIMIT        VALUE '1005'.
               88  :TAG:-RC-INVALID-IDEMP-KEY        VALUE '1006'.
               88  :TAG:-RC-INVALID-TRX-ID           VALUE '1007'.
               88  :TAG:-RC-INVALID-CURRENCY         VALUE '1008'.
      *        --- 2XXX BUSINESS RULES ---------------------------------
               88  :TAG:-RC-ACCOUNT-NOT-FOUND        VALUE '2001'.
               88  :TAG:-RC-ACCOUNT-NOT-ACTIVE       VALUE '2002'.
               88  :TAG:-RC-INSUFFICIENT-FUNDS       VALUE '2003'.
               88  :TAG:-RC-BALANCE-LIMIT            VALUE '2004'.
               88  :TAG:-RC-TRX-NOT-FOUND            VALUE '2005'.
               88  :TAG:-RC-CUSTOMER-NOT-ACTIVE      VALUE '2006'.
               88  :TAG:-RC-IDEMP-KEY-CONFLICT       VALUE '2007'.
               88  :TAG:-RC-CURRENCY-MISMATCH        VALUE '2008'.
      *        --- 3XXX TRANSIENT --------------------------------------
               88  :TAG:-RC-CONCURRENT-UPDATE        VALUE '3001'.
      *        --- 9XXX TECHNICAL --------------------------------------
               88  :TAG:-RC-DATA-ACCESS-ERROR        VALUE '9001'.
               88  :TAG:-RC-DATA-INTEGRITY-ERROR     VALUE '9002'.
               88  :TAG:-RC-POSTING-INCOMPLETE       VALUE '9003'.
               88  :TAG:-RC-RETRIES-EXHAUSTED        VALUE '9004'.
               88  :TAG:-RC-UNEXPECTED-ERROR         VALUE '9999'.
