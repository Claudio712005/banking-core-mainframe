      *================================================================*
      * COPYBOOK : ACCOUNT                                             *
      * PURPOSE  : ACCOUNT MASTER RECORD (SYSTEM OF RECORD LAYOUT).    *
      *            LAB  : LINE SEQUENTIAL FILE  DD ACCTMAST.           *
      *            Z/OS : DB2 TABLE ACCOUNT (SEE DOCS/ARCHITECTURE.MD).*
      * LENGTH   : 100 BYTES, ALL FIELDS DISPLAY (CHARACTER DATA).     *
      * USAGE    : 01  WS-ACCOUNT.                                     *
      *                COPY ACCOUNT REPLACING ==:TAG:== BY ==WSA==.    *
      *----------------------------------------------------------------*
      * FIELD             POS  LEN  NOTES                              *
      * ACCOUNT-ID          1   10  10 DIGITS, NOT ALL ZEROS           *
      * CUSTOMER-ID        11   10  10 DIGITS, FK TO CUSTOMER          *
      * ACCOUNT-TYPE       21    3  CHK / SAV                          *
      * ACCOUNT-STATUS     24    1  A=ACTIVE B=BLOCKED C=CLOSED        *
      * BALANCE            25   16  SIGN + 13 INT + 2 DEC (IMPLIED)    *
      * CURRENCY           41    3  ISO 4217 ALPHA CODE                *
      * VERSION-NUMBER     44    9  OPTIMISTIC LOCK COUNTER            *
      * LAST-UPDATE-TS     53   26  YYYY-MM-DD-HH.MM.SS.NNNNNN         *
      * CUSTOMER-STATUS    79    1  A=ACTIVE B=BLOCKED I=INACTIVE.     *
      *                             KEPT ON THE ACCOUNT: THE CUSTOMER  *
      *                             MASTER BELONGS TO MAINFRAME-       *
      *                             CUSTOMER (SOAP), NOT TO THIS CORE. *
      * FILLER             80   21  RESERVED FOR FUTURE USE            *
      *================================================================*
           05  :TAG:-ACCOUNT-ID             PIC X(10).
           05  :TAG:-CUSTOMER-ID            PIC X(10).
           05  :TAG:-ACCOUNT-TYPE           PIC X(03).
               88  :TAG:-TYPE-CHECKING               VALUE 'CHK'.
               88  :TAG:-TYPE-SAVINGS                VALUE 'SAV'.
               88  :TAG:-TYPE-VALID                  VALUE 'CHK'
                                                           'SAV'.
           05  :TAG:-ACCOUNT-STATUS         PIC X(01).
               88  :TAG:-STATUS-ACTIVE               VALUE 'A'.
               88  :TAG:-STATUS-BLOCKED              VALUE 'B'.
               88  :TAG:-STATUS-CLOSED               VALUE 'C'.
               88  :TAG:-STATUS-VALID                VALUE 'A'
                                                           'B'
                                                           'C'.
           05  :TAG:-BALANCE                PIC S9(13)V99
                                            SIGN LEADING SEPARATE.
           05  :TAG:-CURRENCY               PIC X(03).
           05  :TAG:-VERSION-NUMBER         PIC 9(09).
           05  :TAG:-LAST-UPDATE-TS         PIC X(26).
           05  :TAG:-CUSTOMER-STATUS        PIC X(01).
               88  :TAG:-CUSTOMER-ACTIVE             VALUE 'A'.
               88  :TAG:-CUSTOMER-STATUS-VALID       VALUE 'A'
                                                           'B'
                                                           'I'.
           05  FILLER                       PIC X(21).
