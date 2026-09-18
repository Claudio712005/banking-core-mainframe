      *================================================================*
      * COPYBOOK : CSTCTL                                              *
      * PURPOSE  : INTERFACE OF THE RESPONSE BUILDER MODULE CSTRESP.   *
      *            INIT   : PREPARES THE RESPONSE HEADER FROM THE      *
      *                     REQUEST AND CLEARS THE BODY.               *
      *            FINISH : STORES CODE + STANDARD MESSAGE, CLEARS THE *
      *                     BODY ON FAILURE AND LOGS 9XXX EVENTS.      *
      * USAGE    : 01  WS-RESPONSE-CONTROL.                            *
      *                COPY CSTCTL REPLACING ==:TAG:== BY ==RCT==.     *
      *================================================================*
           05  :TAG:-FUNCTION               PIC X(08).
               88  :TAG:-FN-INIT                     VALUE 'INIT    '.
               88  :TAG:-FN-FINISH                   VALUE 'FINISH  '.
           05  :TAG:-PROGRAM-ID             PIC X(08).
           05  :TAG:-RESPONSE-CODE          PIC X(04).
           05  :TAG:-TECH-CODE              PIC X(08).
