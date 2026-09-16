      *================================================================*
      * COPYBOOK : VALCTL                                              *
      * PURPOSE  : INTERFACE OF THE INPUT VALIDATION MODULE BKVALID.   *
      *            THE CALLER SETS ONE FUNCTION, MOVES THE RAW FIELD   *
      *            TO :TAG:-FIELD AND RECEIVES A RESPONSE CODE         *
      *            (RSPCODE VALUES; '0000' MEANS VALID).               *
      * USAGE    : 01  WS-VALIDATION.                                  *
      *                COPY VALCTL REPLACING ==:TAG:== BY ==VAL==.     *
      *================================================================*
           05  :TAG:-FUNCTION               PIC X(08).
               88  :TAG:-FN-ACCOUNT-ID               VALUE 'ACCTID  '.
               88  :TAG:-FN-TRANSACTION-ID           VALUE 'TRXID   '.
               88  :TAG:-FN-AMOUNT                   VALUE 'AMOUNT  '.
               88  :TAG:-FN-IDEMPOTENCY-KEY          VALUE 'IDEMKEY '.
               88  :TAG:-FN-CURRENCY                 VALUE 'CURRENCY'.
           05  :TAG:-FIELD                  PIC X(40).
           05  :TAG:-ACCOUNT-ID-VIEW REDEFINES :TAG:-FIELD.
               10  :TAG:-ACCOUNT-ID         PIC X(10).
               10  FILLER                   PIC X(30).
           05  :TAG:-TRANSACTION-ID-VIEW REDEFINES :TAG:-FIELD.
               10  :TAG:-TRANSACTION-ID     PIC X(16).
               10  FILLER                   PIC X(24).
           05  :TAG:-AMOUNT-VIEW REDEFINES :TAG:-FIELD.
               10  :TAG:-AMOUNT             PIC S9(13)V99
                                            SIGN LEADING SEPARATE.
               10  FILLER                   PIC X(24).
           05  :TAG:-IDEMPOTENCY-KEY-VIEW REDEFINES :TAG:-FIELD.
               10  :TAG:-IDEMPOTENCY-KEY    PIC X(36).
               10  FILLER                   PIC X(04).
           05  :TAG:-CURRENCY-VIEW REDEFINES :TAG:-FIELD.
               10  :TAG:-CURRENCY           PIC X(03).
               10  FILLER                   PIC X(37).
           05  :TAG:-RESULT-CODE            PIC X(04).
