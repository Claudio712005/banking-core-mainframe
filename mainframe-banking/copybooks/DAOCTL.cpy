      *================================================================*
      * COPYBOOK : DAOCTL                                              *
      * PURPOSE  : CONTROL BLOCK FOR DATA ACCESS MODULES               *
      *            (ACCTDAO, CUSTDAO, TRXDAO).                         *
      *            THE CALLER NEVER KNOWS WHETHER DATA LIVES IN A      *
      *            FILE (LAB) OR IN DB2 (Z/OS). ONLY THIS BLOCK AND    *
      *            THE ENTITY RECORD CROSS THE BOUNDARY.               *
      * USAGE    : 01  WS-DAO-CONTROL.                                 *
      *                COPY DAOCTL REPLACING ==:TAG:== BY ==DAO==.     *
      *----------------------------------------------------------------*
      * FUNCTION   SUPPORTED BY       MEANING                          *
      * READ       ACCTDAO CUSTDAO    READ BY PRIMARY KEY              *
      *            TRXDAO                                              *
      * UPDATE     ACCTDAO            REWRITE, CHECKING VERSION-NUMBER *
      * INSERT     TRXDAO             ASSIGN ID, ENFORCE UNIQUE KEY    *
      * FINDKEY    TRXDAO             READ BY IDEMPOTENCY-KEY          *
      *----------------------------------------------------------------*
      * TECH-CODE : DIAGNOSTIC ONLY (LAB: FILE STATUS OR REASON,       *
      *             Z/OS: SQLCODE). NEVER RETURNED TO THE CLIENT.      *
      *================================================================*
           05  :TAG:-FUNCTION               PIC X(08).
               88  :TAG:-FN-READ                     VALUE 'READ    '.
               88  :TAG:-FN-UPDATE                   VALUE 'UPDATE  '.
               88  :TAG:-FN-INSERT                   VALUE 'INSERT  '.
               88  :TAG:-FN-FIND-BY-KEY              VALUE 'FINDKEY '.
           05  :TAG:-STATUS                 PIC X(02).
               88  :TAG:-ST-OK                       VALUE '00'.
               88  :TAG:-ST-NOT-FOUND                VALUE '10'.
               88  :TAG:-ST-DUPLICATE                VALUE '20'.
               88  :TAG:-ST-VERSION-CONFLICT         VALUE '30'.
               88  :TAG:-ST-INVALID-CALL             VALUE '80'.
               88  :TAG:-ST-DATA-ERROR               VALUE '90'.
               88  :TAG:-ST-IO-ERROR                 VALUE '99'.
           05  :TAG:-TECH-CODE              PIC X(08).
