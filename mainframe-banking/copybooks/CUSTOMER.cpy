      *================================================================*
      * COPYBOOK : CUSTOMER                                            *
      * PURPOSE  : CUSTOMER MASTER RECORD.                             *
      *            LAB  : LINE SEQUENTIAL FILE  DD CUSTMAST.           *
      *            Z/OS : DB2 TABLE CUSTOMER.                          *
      * LENGTH   : 60 BYTES, ALL FIELDS DISPLAY.                       *
      * SECURITY : CUSTOMER-NAME IS PERSONAL DATA. IT MUST NEVER BE    *
      *            DISPLAYED, LOGGED OR RETURNED BY POSTING PROGRAMS.  *
      * USAGE    : 01  WS-CUSTOMER.                                    *
      *                COPY CUSTOMER REPLACING ==:TAG:== BY ==WSC==.   *
      *----------------------------------------------------------------*
      * FIELD             POS  LEN  NOTES                              *
      * CUSTOMER-ID         1   10  10 DIGITS, NOT ALL ZEROS           *
      * CUSTOMER-NAME      11   40  FREE TEXT                          *
      * CUSTOMER-STATUS    51    1  A=ACTIVE B=BLOCKED I=INACTIVE      *
      * FILLER             52    9  RESERVED FOR FUTURE USE            *
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
           05  FILLER                       PIC X(09).
