      *================================================================*
      * COPYBOOK : RSPCTL                                              *
      * PURPOSE  : INTERFACE OF THE RESPONSE BUILDER MODULE BKRESP.    *
      *            INIT   : PREPARES RESPONSE HEADER FROM THE REQUEST  *
      *                     AND CLEARS THE BODY.                       *
      *            FINISH : STORES RESPONSE CODE + STANDARD MESSAGE,   *
      *                     CLEARS THE BODY ON FAILURE AND WRITES THE  *
      *                     TECHNICAL LOG FOR 3XXX/9XXX CODES.         *
      * USAGE    : 01  WS-RESPONSE-CONTROL.                            *
      *                COPY RSPCTL REPLACING ==:TAG:== BY ==RCT==.     *
      *================================================================*
           05  :TAG:-FUNCTION               PIC X(08).
               88  :TAG:-FN-INIT                     VALUE 'INIT    '.
               88  :TAG:-FN-FINISH                   VALUE 'FINISH  '.
           05  :TAG:-PROGRAM-ID             PIC X(08).
           05  :TAG:-RESPONSE-CODE          PIC X(04).
           05  :TAG:-TECH-CODE              PIC X(08).
