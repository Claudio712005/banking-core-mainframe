      *================================================================*
      * COPYBOOK : CUSTREQ                                             *
      * PURPOSE  : INBOUND MESSAGE CONTRACT OF THE CUSTOMER CORE.      *
      *            THE SOAP ADAPTER (CSTSOAP) AND THE BATCH DRIVER     *
      *            (CUSTDRV) BUILD THIS LAYOUT; THE BUSINESS PROGRAMS  *
      *            NEVER SEE XML OR HTTP.                              *
      * LENGTH   : 100 BYTES, CHARACTER DATA ONLY.                     *
      * VERSION  : LAYOUT 01. NEW FIELDS ONLY CONSUME FILLER.          *
      * USAGE    : 01  LK-REQUEST.                                     *
      *                COPY CUSTREQ.                                   *
      *----------------------------------------------------------------*
      * FIELD             POS  LEN  REQ  NOTES                         *
      * LAYOUT-VERSION      1    2   Y   '01'                          *
      * OPERATION-CODE      3    8   Y   CUSTINQ / CRDINQ              *
      * CORRELATION-ID     11   36   N   OPAQUE, ECHOED BACK           *
      * FILLER             47    4       RESERVED                      *
      * CUSTOMER-ID        51   10   Y   10 DIGITS, NOT ALL ZEROS      *
      * FILLER             61   40       RESERVED                      *
      *================================================================*
           05  CRQ-HEADER.
               10  CRQ-LAYOUT-VERSION       PIC X(02).
                   88  CRQ-LAYOUT-V01                VALUE '01'.
               10  CRQ-OPERATION-CODE       PIC X(08).
                   88  CRQ-OP-CUSTOMER-INQUIRY       VALUE 'CUSTINQ '.
                   88  CRQ-OP-CREDIT-INQUIRY         VALUE 'CRDINQ  '.
               10  CRQ-CORRELATION-ID       PIC X(36).
               10  FILLER                   PIC X(04).
           05  CRQ-BODY.
               10  CRQ-CUSTOMER-ID          PIC X(10).
               10  FILLER                   PIC X(40).
