      *================================================================*
      * COPYBOOK : CUSTRSP                                             *
      * PURPOSE  : OUTBOUND MESSAGE CONTRACT OF THE CUSTOMER CORE.     *
      * LENGTH   : 300 BYTES, CHARACTER DATA ONLY.                     *
      * RULES    : THE BODY IS MEANINGFUL ONLY WHEN RESPONSE-CODE IS   *
      *            0000; OTHERWISE IT IS SPACES. CODES ARE DEFINED IN  *
      *            COPYBOOK CSTCODE. MESSAGES CARRY NO PERSONAL DATA.  *
      * USAGE    : 01  LK-RESPONSE.                                    *
      *                COPY CUSTRSP.                                   *
      *----------------------------------------------------------------*
      * HEADER             POS  LEN  NOTES                             *
      * LAYOUT-VERSION       1    2  '01'                              *
      * OPERATION-CODE       3    8  ECHO OF THE REQUEST               *
      * CORRELATION-ID      11   36  ECHO OF THE REQUEST               *
      * RESPONSE-CODE       47    4  NNNN, SEE CSTCODE                 *
      * RESPONSE-MESSAGE    51   60  UPPERCASE, CODE PAGE SAFE         *
      * FILLER             111   10  RESERVED                          *
      * BODY               121  180  SEE REDEFINES BELOW               *
      *================================================================*
           05  CRS-HEADER.
               10  CRS-LAYOUT-VERSION       PIC X(02).
               10  CRS-OPERATION-CODE       PIC X(08).
               10  CRS-CORRELATION-ID       PIC X(36).
               10  CRS-RESPONSE-CODE        PIC X(04).
               10  CRS-RESPONSE-MESSAGE     PIC X(60).
               10  FILLER                   PIC X(10).
           05  CRS-BODY                     PIC X(180).
      *----------------------------------------------------------------*
      * BODY FOR CUSTINQ                     POS  LEN                  *
      *   CUSTOMER-ID                        121   10                  *
      *   CUSTOMER-NAME                      131   40                  *
      *   CUSTOMER-STATUS                    171    1  A / B / I       *
      *   DOCUMENT-MASKED                    172   14  ***.***.***-NN  *
      *   REGISTERED-DATE                    186   10  YYYY-MM-DD      *
      *----------------------------------------------------------------*
           05  CRS-CUSTOMER-INQUIRY REDEFINES CRS-BODY.
               10  CRS-CI-CUSTOMER-ID       PIC X(10).
               10  CRS-CI-CUSTOMER-NAME     PIC X(40).
               10  CRS-CI-CUSTOMER-STATUS   PIC X(01).
               10  CRS-CI-DOCUMENT-MASKED   PIC X(14).
               10  CRS-CI-REGISTERED-DATE   PIC X(10).
               10  FILLER                   PIC X(105).
      *----------------------------------------------------------------*
      * BODY FOR CRDINQ                      POS  LEN                  *
      *   CUSTOMER-ID                        121   10                  *
      *   CURRENCY                           131    3                  *
      *   APPROVED-LIMIT                     134   16                  *
      *   USED-LIMIT                         150   16                  *
      *   AVAILABLE-LIMIT                    166   16                  *
      *----------------------------------------------------------------*
           05  CRS-CREDIT-INQUIRY REDEFINES CRS-BODY.
               10  CRS-CR-CUSTOMER-ID       PIC X(10).
               10  CRS-CR-CURRENCY          PIC X(03).
               10  CRS-CR-APPROVED-LIMIT    PIC S9(13)V99
                                            SIGN LEADING SEPARATE.
               10  CRS-CR-USED-LIMIT        PIC S9(13)V99
                                            SIGN LEADING SEPARATE.
               10  CRS-CR-AVAILABLE-LIMIT   PIC S9(13)V99
                                            SIGN LEADING SEPARATE.
               10  FILLER                   PIC X(135).
