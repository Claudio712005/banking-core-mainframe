       IDENTIFICATION DIVISION.
       PROGRAM-ID. CUSTDRV.
      *================================================================*
      * PROGRAM  : CUSTDRV                                             *
      * TYPE     : BATCH MAIN PROGRAM (TRANSPORT ADAPTER)              *
      * PURPOSE  : READS REQUEST MESSAGES FROM A SEQUENTIAL FILE,      *
      *            DISPATCHES EACH ONE TO ITS ENTRY PROGRAM AND WRITES *
      *            ONE RESPONSE PER REQUEST. USED BY THE REGRESSION    *
      *            SUITE, SO THE BUSINESS PROGRAMS CAN BE EXERCISED    *
      *            WITHOUT HTTP OR SOAP.                               *
      *----------------------------------------------------------------*
      * FILES    : REQIN   INPUT   100-BYTE REQUEST RECORDS            *
      *            RSPOUT  OUTPUT  300-BYTE RESPONSE RECORDS           *
      * SECURITY : THE TARGET PROGRAM COMES FROM A FIXED WHITELIST;    *
      *            THE OPERATION CODE IS NEVER USED AS A PROGRAM NAME. *
      * RETURN   : 0 ALL OK, 4 SOME REQUEST REJECTED, 12 TECHNICAL     *
      *            FAILURE (PROCESSING STOPS), 16 FILE ERROR.          *
      *================================================================*
       ENVIRONMENT DIVISION.
       INPUT-OUTPUT SECTION.
       FILE-CONTROL.
           SELECT REQUEST-FILE
               ASSIGN TO REQIN
               ORGANIZATION IS LINE SEQUENTIAL
               FILE STATUS IS WS-REQUEST-FILE-STATUS.
           SELECT RESPONSE-FILE
               ASSIGN TO RSPOUT
               ORGANIZATION IS LINE SEQUENTIAL
               FILE STATUS IS WS-RESPONSE-FILE-STATUS.

       DATA DIVISION.
       FILE SECTION.
       FD  REQUEST-FILE.
       01  REQUEST-FILE-RECORD              PIC X(100).
       FD  RESPONSE-FILE.
       01  RESPONSE-FILE-RECORD             PIC X(300).

       WORKING-STORAGE SECTION.
       01  WS-PROGRAM-NAMES.
           05  WS-THIS-PROGRAM              PIC X(08) VALUE 'CUSTDRV'.
           05  WS-PGM-RESPONSE-BUILDER      PIC X(08) VALUE 'CSTRESP'.
           05  WS-PGM-CUSTOMER-INQUIRY      PIC X(08) VALUE 'CUSTINQ'.
           05  WS-PGM-CREDIT-INQUIRY        PIC X(08) VALUE 'CRDINQ'.

       01  WS-CONSTANTS.
           05  WS-REASON-MODULE-MISSING     PIC X(08) VALUE 'NOMODULE'.
           05  WS-REASON-NO-RESPONSE        PIC X(08) VALUE 'NORESP'.
           05  WS-REASON-RECORD-LENGTH      PIC X(08) VALUE 'RECLEN'.

       01  WS-RETURN-CODES.
           05  WS-RC-JOB-OK                 PIC S9(04) COMP VALUE +0.
           05  WS-RC-JOB-WARNING            PIC S9(04) COMP VALUE +4.
           05  WS-RC-JOB-SEVERE             PIC S9(04) COMP VALUE +12.
           05  WS-RC-JOB-FILE-ERROR         PIC S9(04) COMP VALUE +16.
           05  WS-JOB-RETURN-CODE           PIC S9(04) COMP.

       01  WS-FILE-STATUSES.
           05  WS-REQUEST-FILE-STATUS       PIC X(02).
               88  WS-REQUEST-OK                     VALUE '00'.
               88  WS-REQUEST-END-OF-FILE            VALUE '10'.
               88  WS-REQUEST-LENGTH-ERROR           VALUE '04'
                                                           '06'.
           05  WS-RESPONSE-FILE-STATUS      PIC X(02).
               88  WS-RESPONSE-OK                    VALUE '00'.

       01  WS-CONTROL-FLAGS.
           05  WS-PROCESSING-FLAG           PIC X(01).
               88  WS-PROCESSING-ACTIVE              VALUE 'Y'.
               88  WS-PROCESSING-ENDED               VALUE 'N'.
           05  WS-FILES-FLAG                PIC X(01).
               88  WS-FILES-OPEN                     VALUE 'Y'.
               88  WS-FILES-NOT-OPEN                 VALUE 'N'.

       01  WS-COUNTERS.
           05  WS-COUNT-READ                PIC 9(09) COMP.
           05  WS-COUNT-COMPLETED           PIC 9(09) COMP.
           05  WS-COUNT-REJECTED            PIC 9(09) COMP.
           05  WS-COUNT-TECHNICAL           PIC 9(09) COMP.

       01  WS-DISPLAY-COUNT                 PIC ZZZ,ZZZ,ZZ9.
       01  WS-TARGET-PROGRAM                PIC X(08).

       01  WS-RESULT.
           COPY CSTCODE REPLACING ==:TAG:== BY ==WS==.

       01  WS-RESPONSE-CONTROL.
           COPY CSTCTL REPLACING ==:TAG:== BY ==RCT==.

       01  WS-REQUEST.
           COPY CUSTREQ.

       01  WS-RESPONSE.
           COPY CUSTRSP.

       PROCEDURE DIVISION.
      *================================================================*
       0000-MAIN.
           PERFORM 1000-INITIALIZE
           PERFORM 2000-PROCESS-NEXT-REQUEST
               UNTIL WS-PROCESSING-ENDED
           PERFORM 9000-FINALIZE
           GOBACK
           .

       1000-INITIALIZE.
           INITIALIZE WS-COUNTERS
                      WS-RESPONSE-CONTROL
           MOVE WS-RC-JOB-OK TO WS-JOB-RETURN-CODE
           SET WS-PROCESSING-ACTIVE TO TRUE
           SET WS-FILES-NOT-OPEN TO TRUE
           OPEN INPUT  REQUEST-FILE
           OPEN OUTPUT RESPONSE-FILE
           IF WS-REQUEST-OK AND WS-RESPONSE-OK
               SET WS-FILES-OPEN TO TRUE
           ELSE
               DISPLAY WS-THIS-PROGRAM ' OPEN FAILED REQIN='
                       WS-REQUEST-FILE-STATUS ' RSPOUT='
                       WS-RESPONSE-FILE-STATUS
               MOVE WS-RC-JOB-FILE-ERROR TO WS-JOB-RETURN-CODE
               SET WS-PROCESSING-ENDED TO TRUE
           END-IF
           .

       2000-PROCESS-NEXT-REQUEST.
           READ REQUEST-FILE INTO WS-REQUEST
           EVALUATE TRUE
               WHEN WS-REQUEST-OK
                   ADD 1 TO WS-COUNT-READ
                   PERFORM 2100-DISPATCH-REQUEST
                   PERFORM 2300-CLASSIFY-RESULT
                   PERFORM 2400-WRITE-RESPONSE
               WHEN WS-REQUEST-LENGTH-ERROR
                   ADD 1 TO WS-COUNT-READ
                   PERFORM 2200-REJECT-MALFORMED-REQUEST
                   PERFORM 2300-CLASSIFY-RESULT
                   PERFORM 2400-WRITE-RESPONSE
               WHEN WS-REQUEST-END-OF-FILE
                   SET WS-PROCESSING-ENDED TO TRUE
               WHEN OTHER
                   DISPLAY WS-THIS-PROGRAM ' READ FAILED REQIN='
                           WS-REQUEST-FILE-STATUS
                   MOVE WS-RC-JOB-FILE-ERROR TO WS-JOB-RETURN-CODE
                   SET WS-PROCESSING-ENDED TO TRUE
           END-EVALUATE
           .

       2100-DISPATCH-REQUEST.
           MOVE SPACES TO WS-RESPONSE
           EVALUATE TRUE
               WHEN CRQ-OP-CUSTOMER-INQUIRY
                   MOVE WS-PGM-CUSTOMER-INQUIRY TO WS-TARGET-PROGRAM
               WHEN CRQ-OP-CREDIT-INQUIRY
                   MOVE WS-PGM-CREDIT-INQUIRY   TO WS-TARGET-PROGRAM
               WHEN OTHER
                   MOVE SPACES                  TO WS-TARGET-PROGRAM
           END-EVALUATE
           IF WS-TARGET-PROGRAM = SPACES
               SET WS-RC-INVALID-REQUEST TO TRUE
               PERFORM 2900-BUILD-DRIVER-RESPONSE
           ELSE
               CALL WS-TARGET-PROGRAM USING WS-REQUEST
                                            WS-RESPONSE
                   ON EXCEPTION
                       SET WS-RC-UNEXPECTED-ERROR TO TRUE
                       MOVE WS-REASON-MODULE-MISSING
                         TO RCT-TECH-CODE
                       PERFORM 2900-BUILD-DRIVER-RESPONSE
               END-CALL
           END-IF
           .

       2200-REJECT-MALFORMED-REQUEST.
           MOVE SPACES TO WS-RESPONSE
           SET WS-RC-INVALID-REQUEST TO TRUE
           MOVE WS-REASON-RECORD-LENGTH TO RCT-TECH-CODE
           PERFORM 2900-BUILD-DRIVER-RESPONSE
           .

       2300-CLASSIFY-RESULT.
           MOVE CRS-RESPONSE-CODE TO WS-RESPONSE-CODE
           EVALUATE TRUE
               WHEN WS-RC-CAT-SUCCESS
                   ADD 1 TO WS-COUNT-COMPLETED
               WHEN WS-RC-CAT-VALIDATION
               WHEN WS-RC-CAT-BUSINESS
                   ADD 1 TO WS-COUNT-REJECTED
                   PERFORM 2310-RAISE-TO-WARNING
               WHEN WS-RC-CAT-TECHNICAL
                   PERFORM 2320-STOP-ON-TECHNICAL-FAILURE
               WHEN OTHER
                   SET WS-RC-UNEXPECTED-ERROR TO TRUE
                   MOVE WS-REASON-NO-RESPONSE TO RCT-TECH-CODE
                   PERFORM 2900-BUILD-DRIVER-RESPONSE
                   PERFORM 2320-STOP-ON-TECHNICAL-FAILURE
           END-EVALUATE
           .

       2310-RAISE-TO-WARNING.
           IF WS-JOB-RETURN-CODE < WS-RC-JOB-WARNING
               MOVE WS-RC-JOB-WARNING TO WS-JOB-RETURN-CODE
           END-IF
           .

       2320-STOP-ON-TECHNICAL-FAILURE.
           ADD 1 TO WS-COUNT-TECHNICAL
           MOVE WS-RC-JOB-SEVERE TO WS-JOB-RETURN-CODE
           SET WS-PROCESSING-ENDED TO TRUE
           .

       2400-WRITE-RESPONSE.
           WRITE RESPONSE-FILE-RECORD FROM WS-RESPONSE
           IF NOT WS-RESPONSE-OK
               DISPLAY WS-THIS-PROGRAM ' WRITE FAILED RSPOUT='
                       WS-RESPONSE-FILE-STATUS
               MOVE WS-RC-JOB-FILE-ERROR TO WS-JOB-RETURN-CODE
               SET WS-PROCESSING-ENDED TO TRUE
           END-IF
           .

       2900-BUILD-DRIVER-RESPONSE.
           MOVE WS-THIS-PROGRAM  TO RCT-PROGRAM-ID
           MOVE WS-RESPONSE-CODE TO RCT-RESPONSE-CODE
           SET RCT-FN-INIT TO TRUE
           PERFORM 2910-CALL-RESPONSE-BUILDER
           SET RCT-FN-FINISH TO TRUE
           PERFORM 2910-CALL-RESPONSE-BUILDER
           MOVE SPACES TO RCT-TECH-CODE
           .

       2910-CALL-RESPONSE-BUILDER.
           CALL WS-PGM-RESPONSE-BUILDER USING WS-RESPONSE-CONTROL
                                              WS-REQUEST
                                              WS-RESPONSE
               ON EXCEPTION
                   DISPLAY WS-THIS-PROGRAM ' MODULE NOT FOUND: '
                           WS-PGM-RESPONSE-BUILDER
                   MOVE WS-RC-JOB-SEVERE TO WS-JOB-RETURN-CODE
                   SET WS-PROCESSING-ENDED TO TRUE
           END-CALL
           .

       9000-FINALIZE.
           IF WS-FILES-OPEN
               CLOSE REQUEST-FILE
                     RESPONSE-FILE
           END-IF
           DISPLAY WS-THIS-PROGRAM ' ---- PROCESSING SUMMARY ----'
           MOVE WS-COUNT-READ TO WS-DISPLAY-COUNT
           DISPLAY WS-THIS-PROGRAM ' REQUESTS READ .......: '
                   WS-DISPLAY-COUNT
           MOVE WS-COUNT-COMPLETED TO WS-DISPLAY-COUNT
           DISPLAY WS-THIS-PROGRAM ' COMPLETED ...........: '
                   WS-DISPLAY-COUNT
           MOVE WS-COUNT-REJECTED TO WS-DISPLAY-COUNT
           DISPLAY WS-THIS-PROGRAM ' REJECTED ............: '
                   WS-DISPLAY-COUNT
           MOVE WS-COUNT-TECHNICAL TO WS-DISPLAY-COUNT
           DISPLAY WS-THIS-PROGRAM ' TECHNICAL FAILURES ..: '
                   WS-DISPLAY-COUNT
           DISPLAY WS-THIS-PROGRAM ' RETURN CODE .........: '
                   WS-JOB-RETURN-CODE
           MOVE WS-JOB-RETURN-CODE TO RETURN-CODE
           .
