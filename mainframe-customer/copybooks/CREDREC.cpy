      *================================================================*
      * COPYBOOK : CREDREC                                             *
      * PURPOSE  : CREDIT LIMIT RECORD OF A CUSTOMER.                  *
      *            LAB  : LINE SEQUENTIAL FILE  DD CREDMAST.           *
      *            Z/OS : DB2 TABLE CUSTOMER_CREDIT.                   *
      * LENGTH   : 60 BYTES, ALL FIELDS DISPLAY.                       *
      * USAGE    : 01  WS-CREDIT.                                      *
      *                COPY CREDREC REPLACING ==:TAG:== BY ==WSR==.    *
      *----------------------------------------------------------------*
      * FIELD             POS  LEN  NOTES                              *
      * CUSTOMER-ID         1   10  10 DIGITS                          *
      * CURRENCY           11    3  ISO 4217 ALPHA CODE                *
      * APPROVED-LIMIT     14   16  SIGN + 13 INT + 2 DEC (IMPLIED)    *
      * USED-LIMIT         30   16  NEVER GREATER THAN APPROVED        *
      * FILLER             46   15  RESERVED FOR FUTURE USE            *
      *================================================================*
           05  :TAG:-CUSTOMER-ID            PIC X(10).
           05  :TAG:-CURRENCY               PIC X(03).
           05  :TAG:-APPROVED-LIMIT         PIC S9(13)V99
                                            SIGN LEADING SEPARATE.
           05  :TAG:-USED-LIMIT             PIC S9(13)V99
                                            SIGN LEADING SEPARATE.
           05  FILLER                       PIC X(15).
