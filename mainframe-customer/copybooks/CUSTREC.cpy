      *================================================================*
      * COPYBOOK : CUSTREC                                             *
      * PURPOSE  : CUSTOMER MASTER RECORD (SYSTEM OF RECORD LAYOUT).   *
      *            LAB  : LINE SEQUENTIAL FILE  DD CUSTMAST.           *
      *            Z/OS : DB2 TABLE CUSTOMER.                          *
      * LENGTH   : 100 BYTES, ALL FIELDS DISPLAY.                      *
      * SECURITY : NAME AND DOCUMENT ARE PERSONAL DATA. THE DOCUMENT   *
      *            IS NEVER RETURNED IN FULL, ONLY MASKED.             *
      * USAGE    : 01  WS-CUSTOMER.                                    *
      *                COPY CUSTREC REPLACING ==:TAG:== BY ==WSC==.    *
      *----------------------------------------------------------------*
      * FIELD             POS  LEN  NOTES                              *
      * CUSTOMER-ID         1   10  10 DIGITS, NOT ALL ZEROS           *
      * CUSTOMER-NAME      11   40  FREE TEXT                          *
      * CUSTOMER-STATUS    51    1  A=ACTIVE B=BLOCKED I=INACTIVE      *
      * DOCUMENT           52   11  NATIONAL ID, DIGITS ONLY           *
      * REGISTERED-DATE    63   10  YYYY-MM-DD                         *
      * FILLER             73   28  RESERVED FOR FUTURE USE            *
      *================================================================*
           05  :TAG:-CUSTOMER-ID            PIC X(10).
           05  :TAG:-CUSTOMER-NAME          PIC X(40).
           05  :TAG:-CUSTOMER-STATUS        PIC X(01).
               88  :TAG:-STATUS-ACTIVE               VALUE 'A'.
               88  :TAG:-STATUS-BLOCKED              VALUE 'B'.
               88  :TAG:-STATUS-INACTIVE             VALUE 'I'.
               88  :TAG:-STATUS-VALID                VALUE 'A'
                                                           'B'
                                                           'I'.
           05  :TAG:-DOCUMENT               PIC X(11).
           05  :TAG:-REGISTERED-DATE        PIC X(10).
           05  FILLER                       PIC X(28).
