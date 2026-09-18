      *================================================================*
      * COPYBOOK : CSTDAO                                              *
      * PURPOSE  : CONTROL BLOCK FOR THE DATA ACCESS MODULES           *
      *            (CUSTDAO, CREDDAO). READ-ONLY DOMAIN.               *
      * USAGE    : 01  WS-DAO-CONTROL.                                 *
      *                COPY CSTDAO REPLACING ==:TAG:== BY ==DAO==.     *
      * TECH-CODE: DIAGNOSTIC ONLY (FILE STATUS OR REASON), NEVER      *
      *            RETURNED TO THE CLIENT.                             *
      *================================================================*
           05  :TAG:-FUNCTION               PIC X(08).
               88  :TAG:-FN-READ                     VALUE 'READ    '.
           05  :TAG:-STATUS                 PIC X(02).
               88  :TAG:-ST-OK                       VALUE '00'.
               88  :TAG:-ST-NOT-FOUND                VALUE '10'.
               88  :TAG:-ST-INVALID-CALL             VALUE '80'.
               88  :TAG:-ST-DATA-ERROR               VALUE '90'.
               88  :TAG:-ST-IO-ERROR                 VALUE '99'.
           05  :TAG:-TECH-CODE              PIC X(08).
