      *================================================================*
      * COPYBOOK : CSTCODE                                             *
      * PURPOSE  : SINGLE SOURCE OF TRUTH FOR RESPONSE CODES.          *
      *            MESSAGE TEXTS LIVE IN PROGRAM CSTRESP.              *
      * FORMAT   : 4 DIGITS. FIRST DIGIT IS THE CATEGORY:              *
      *            0 = SUCCESS   1 = INPUT VALIDATION                  *
      *            2 = BUSINESS  9 = TECHNICAL FAILURE                 *
      * USAGE    : 01  WS-RESULT.                                      *
      *                COPY CSTCODE REPLACING ==:TAG:== BY ==WS==.     *
      *================================================================*
           05  :TAG:-RESPONSE-CODE          PIC X(04).
               88  :TAG:-RC-CAT-SUCCESS              VALUE '0000'
                                                      THRU '0999'.
               88  :TAG:-RC-CAT-VALIDATION           VALUE '1000'
                                                      THRU '1999'.
               88  :TAG:-RC-CAT-BUSINESS             VALUE '2000'
                                                      THRU '2999'.
               88  :TAG:-RC-CAT-TECHNICAL            VALUE '9000'
                                                      THRU '9999'.
               88  :TAG:-RC-SUCCESS                  VALUE '0000'.
               88  :TAG:-RC-INVALID-REQUEST          VALUE '1001'.
               88  :TAG:-RC-INVALID-CUSTOMER-ID      VALUE '1002'.
               88  :TAG:-RC-CUSTOMER-NOT-FOUND       VALUE '2001'.
               88  :TAG:-RC-CUSTOMER-NOT-ACTIVE      VALUE '2002'.
               88  :TAG:-RC-NO-CREDIT-LINE           VALUE '2003'.
               88  :TAG:-RC-DATA-ACCESS-ERROR        VALUE '9001'.
               88  :TAG:-RC-DATA-INTEGRITY-ERROR     VALUE '9002'.
               88  :TAG:-RC-UNEXPECTED-ERROR         VALUE '9999'.
