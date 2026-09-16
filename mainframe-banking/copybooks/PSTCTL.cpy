      *================================================================*
      * COPYBOOK : PSTCTL                                              *
      * PURPOSE  : POSTING TYPE PASSED FROM THE ENTRY PROGRAMS         *
      *            (ACCTDEP, ACCTWDR) TO THE POSTING ENGINE ACCTPOST.  *
      *            VALUES MATCH TRANSACTION-TYPE IN COPYBOOK TRANSACT. *
      * USAGE    : 01  WS-POSTING-CONTROL.                             *
      *                COPY PSTCTL REPLACING ==:TAG:== BY ==PST==.     *
      *================================================================*
           05  :TAG:-POSTING-TYPE           PIC X(03).
               88  :TAG:-DEPOSIT                     VALUE 'DEP'.
               88  :TAG:-WITHDRAWAL                  VALUE 'WDR'.
