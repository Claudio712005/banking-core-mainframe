      *================================================================*
      * COPYBOOK : RESPONSE                                            *
      * PURPOSE  : OUTBOUND MESSAGE CONTRACT (COBOL -> MQ -> JAVA).    *
      * LENGTH   : 300 BYTES, CHARACTER DATA ONLY.                     *
      * VERSION  : LAYOUT 01.                                          *
      * RULES    : THE BODY IS MEANINGFUL ONLY WHEN RESPONSE-CODE IS   *
      *            0000 OR 0001. FOR ANY OTHER CODE THE BODY IS SPACES.*
      *            RESPONSE-CODE VALUES ARE DEFINED IN COPYBOOK        *
      *            RSPCODE. MESSAGES NEVER CONTAIN CUSTOMER DATA.      *
      * USAGE    : 01  LK-RESPONSE.                                    *
      *                COPY RESPONSE.                                  *
      *----------------------------------------------------------------*
      * HEADER               POS  LEN  NOTES                           *
      * LAYOUT-VERSION         1    2  '01'                            *
      * OPERATION-CODE         3    8  ECHO OF REQUEST                 *
      * CORRELATION-ID        11   36  ECHO OF REQUEST                 *
      * RESPONSE-CODE         47    4  NNNN, SEE RSPCODE               *
      * RESPONSE-MESSAGE      51   60  UPPERCASE ASCII/EBCDIC SAFE TEXT*
      * FILLER               111   10  RESERVED                        *
      * BODY                 121  180  SEE REDEFINES BELOW             *
      *================================================================*
           05  RSP-HEADER.
               10  RSP-LAYOUT-VERSION       PIC X(02).
                   88  RSP-LAYOUT-V01                VALUE '01'.
               10  RSP-OPERATION-CODE       PIC X(08).
               10  RSP-CORRELATION-ID       PIC X(36).
               10  RSP-RESPONSE-CODE        PIC X(04).
               10  RSP-RESPONSE-MESSAGE     PIC X(60).
               10  FILLER                   PIC X(10).
           05  RSP-BODY                     PIC X(180).
      *----------------------------------------------------------------*
      * BODY FOR ACCTINQ                     POS  LEN                  *
      *   ACCOUNT-ID                         121   10                  *
      *   CUSTOMER-ID                        131   10                  *
      *   ACCOUNT-TYPE                       141    3                  *
      *   ACCOUNT-STATUS                     144    1                  *
      *   BALANCE (SIGN + 15 DIGITS, V99)    145   16                  *
      *   CURRENCY                           161    3                  *
      *   LAST-UPDATE-TS                     164   26                  *
      *----------------------------------------------------------------*
           05  RSP-ACCOUNT-INQUIRY REDEFINES RSP-BODY.
               10  RSP-AI-ACCOUNT-ID        PIC X(10).
               10  RSP-AI-CUSTOMER-ID       PIC X(10).
               10  RSP-AI-ACCOUNT-TYPE      PIC X(03).
               10  RSP-AI-ACCOUNT-STATUS    PIC X(01).
               10  RSP-AI-BALANCE           PIC S9(13)V99
                                            SIGN LEADING SEPARATE.
               10  RSP-AI-CURRENCY          PIC X(03).
               10  RSP-AI-LAST-UPDATE-TS    PIC X(26).
               10  FILLER                   PIC X(111).
      *----------------------------------------------------------------*
      * BODY FOR ACCTDEP / ACCTWDR           POS  LEN                  *
      *   TRANSACTION-ID                     121   16                  *
      *   ACCOUNT-ID                         137   10                  *
      *   TRANSACTION-TYPE                   147    3                  *
      *   AMOUNT                             150   16                  *
      *   NEW-BALANCE                        166   16                  *
      *   CURRENCY                           182    3                  *
      *   TRANSACTION-TS                     185   26                  *
      *----------------------------------------------------------------*
           05  RSP-POSTING REDEFINES RSP-BODY.
               10  RSP-PO-TRANSACTION-ID    PIC X(16).
               10  RSP-PO-ACCOUNT-ID        PIC X(10).
               10  RSP-PO-TRANSACTION-TYPE  PIC X(03).
               10  RSP-PO-AMOUNT            PIC S9(13)V99
                                            SIGN LEADING SEPARATE.
               10  RSP-PO-NEW-BALANCE       PIC S9(13)V99
                                            SIGN LEADING SEPARATE.
               10  RSP-PO-CURRENCY          PIC X(03).
               10  RSP-PO-TRANSACTION-TS    PIC X(26).
               10  FILLER                   PIC X(90).
      *----------------------------------------------------------------*
      * BODY FOR TRXINQ                      POS  LEN                  *
      *   TRANSACTION-ID                     121   16                  *
      *   ACCOUNT-ID                         137   10                  *
      *   TRANSACTION-TYPE                   147    3                  *
      *   AMOUNT                             150   16                  *
      *   CURRENCY                           166    3                  *
      *   TRANSACTION-STATUS                 169    1                  *
      *   TRANSACTION-TS                     170   26                  *
      *----------------------------------------------------------------*
           05  RSP-TRANSACTION-INQUIRY REDEFINES RSP-BODY.
               10  RSP-TI-TRANSACTION-ID    PIC X(16).
               10  RSP-TI-ACCOUNT-ID        PIC X(10).
               10  RSP-TI-TRANSACTION-TYPE  PIC X(03).
               10  RSP-TI-AMOUNT            PIC S9(13)V99
                                            SIGN LEADING SEPARATE.
               10  RSP-TI-CURRENCY          PIC X(03).
               10  RSP-TI-TRANSACTION-STATUS
                                            PIC X(01).
               10  RSP-TI-TRANSACTION-TS    PIC X(26).
               10  FILLER                   PIC X(105).
