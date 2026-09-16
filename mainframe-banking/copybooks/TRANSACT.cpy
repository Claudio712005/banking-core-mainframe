      *================================================================*
      * COPYBOOK : TRANSACT                                            *
      * PURPOSE  : FINANCIAL TRANSACTION JOURNAL RECORD.               *
      *            (NAMED TRANSACT: Z/OS MEMBER NAMES MAX 8 CHARS.)    *
      *            LAB  : LINE SEQUENTIAL FILE  DD TRXJRNL (APPEND).   *
      *            Z/OS : DB2 TABLE ACCOUNT_TRANSACTION WITH UNIQUE    *
      *                   INDEX ON IDEMPOTENCY_KEY.                    *
      * LENGTH   : 150 BYTES, ALL FIELDS DISPLAY.                      *
      * USAGE    : 01  WS-TRANSACTION.                                 *
      *                COPY TRANSACT REPLACING ==:TAG:== BY ==WST==.   *
      *----------------------------------------------------------------*
      * FIELD             POS  LEN  NOTES                              *
      * TRANSACTION-ID      1   16  16 DIGITS, ASSIGNED BY TRXDAO      *
      * ACCOUNT-ID         17   10  10 DIGITS                          *
      * TRANSACTION-TYPE   27    3  DEP=DEPOSIT WDR=WITHDRAWAL         *
      * AMOUNT             30   16  SIGN + 13 INT + 2 DEC, ALWAYS > 0  *
      * CURRENCY           46    3  ISO 4217 ALPHA CODE                *
      * TRANSACTION-STATUS 49    1  C=COMPLETED                        *
      *                             R=REVERSED (RESERVED, SEE DOCS)    *
      * TRANSACTION-TS     50   26  YYYY-MM-DD-HH.MM.SS.NNNNNN         *
      *   TRANSACTION-DATE 50   10  YYYY-MM-DD (BUSINESS DATE)         *
      *   TRANSACTION-TIME 60   16  -HH.MM.SS.NNNNNN                   *
      * IDEMPOTENCY-KEY    76   36  CLIENT SUPPLIED, GLOBALLY UNIQUE   *
      * BALANCE-AFTER     112   16  ACCOUNT BALANCE AFTER POSTING,     *
      *                             USED TO REPLAY IDEMPOTENT RESULTS  *
      * FILLER            128   23  RESERVED FOR FUTURE USE            *
      *================================================================*
           05  :TAG:-TRANSACTION-ID         PIC X(16).
           05  :TAG:-TRANSACTION-ID-N REDEFINES :TAG:-TRANSACTION-ID
                                            PIC 9(16).
           05  :TAG:-ACCOUNT-ID             PIC X(10).
           05  :TAG:-TRANSACTION-TYPE       PIC X(03).
               88  :TAG:-TYPE-DEPOSIT                VALUE 'DEP'.
               88  :TAG:-TYPE-WITHDRAWAL             VALUE 'WDR'.
               88  :TAG:-TYPE-VALID                  VALUE 'DEP'
                                                           'WDR'.
           05  :TAG:-AMOUNT                 PIC S9(13)V99
                                            SIGN LEADING SEPARATE.
           05  :TAG:-CURRENCY               PIC X(03).
           05  :TAG:-TRANSACTION-STATUS     PIC X(01).
               88  :TAG:-STATUS-COMPLETED            VALUE 'C'.
               88  :TAG:-STATUS-REVERSED             VALUE 'R'.
               88  :TAG:-STATUS-VALID                VALUE 'C'
                                                           'R'.
           05  :TAG:-TRANSACTION-TS.
               10  :TAG:-TRANSACTION-DATE   PIC X(10).
               10  :TAG:-TRANSACTION-TIME   PIC X(16).
           05  :TAG:-IDEMPOTENCY-KEY        PIC X(36).
           05  :TAG:-BALANCE-AFTER          PIC S9(13)V99
                                            SIGN LEADING SEPARATE.
           05  FILLER                       PIC X(23).
