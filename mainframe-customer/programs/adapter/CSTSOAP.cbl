       IDENTIFICATION DIVISION.
       PROGRAM-ID. CSTSOAP.
      *================================================================*
      * PROGRAM  : CSTSOAP                                             *
      * TYPE     : CGI MAIN PROGRAM (SOAP 1.1 OVER HTTP)               *
      * TARGET   : LAB - GNUCOBOL 3.2 BEHIND APACHE HTTPD (MOD_CGI).   *
      *            THE Z/OS COUNTERPART WOULD BE CICS WEB SUPPORT OR   *
      *            Z/OS CONNECT PUBLISHING THE SAME WSDL.              *
      * PURPOSE  : TRANSPORT ADAPTER OF THE CUSTOMER CORE. TRANSLATES  *
      *            THE SOAP ENVELOPE INTO THE 100-BYTE REQUEST LAYOUT, *
      *            CALLS THE ENTRY PROGRAM AND RENDERS THE 300-BYTE    *
      *            RESPONSE BACK AS XML.                               *
      *----------------------------------------------------------------*
      * ENVIRONMENT (SET BY THE WEB SERVER)                            *
      *   REQUEST_METHOD   MUST BE POST                                *
      *   CONTENT_LENGTH   BODY SIZE, REJECTED ABOVE CST_MAX_BODY      *
      *   HTTP_SOAPACTION  OPERATION, FROM A FIXED WHITELIST           *
      *   HTTP_X_CORRELATION_ID  OPTIONAL, ECHOED IN THE LOG           *
      *   DD_SOAPIN / DD_SOAPOUT  STDIN / STDOUT                       *
      *----------------------------------------------------------------*
      * SECURITY                                                       *
      *   - THE BODY IS NEVER PARSED AS XML: ONLY THE VALUE BETWEEN    *
      *     THE customerId TAGS IS EXTRACTED, SO EXTERNAL ENTITIES AND *
      *     DOCTYPE DECLARATIONS CARRY NO MEANING (NO XXE BY DESIGN).  *
      *   - EVERY VALUE WRITTEN BACK IS FILTERED TO A SAFE CHARACTER   *
      *     SET, SO NOTHING FROM THE DATA CAN BREAK THE XML.           *
      *   - FAULTS CARRY THE DOCUMENTED CODE AND MESSAGE ONLY; NO      *
      *     FILE STATUS, PATH OR PERSONAL DATA.                        *
      *================================================================*
       ENVIRONMENT DIVISION.
       CONFIGURATION SECTION.
       SPECIAL-NAMES.
           CLASS CST-XML-SAFE-CHAR IS 'A' THRU 'I'
                                      'J' THRU 'R'
                                      'S' THRU 'Z'
                                      'a' THRU 'i'
                                      'j' THRU 'r'
                                      's' THRU 'z'
                                      '0' THRU '9'
                                      '-' '.' '*' ' '.
       INPUT-OUTPUT SECTION.
       FILE-CONTROL.
           SELECT SOAP-INPUT-FILE
               ASSIGN TO SOAPIN
               ORGANIZATION IS LINE SEQUENTIAL
               FILE STATUS IS WS-INPUT-FILE-STATUS.
           SELECT SOAP-OUTPUT-FILE
               ASSIGN TO SOAPOUT
               ORGANIZATION IS LINE SEQUENTIAL
               FILE STATUS IS WS-OUTPUT-FILE-STATUS.

       DATA DIVISION.
       FILE SECTION.
       FD  SOAP-INPUT-FILE.
       01  SOAP-INPUT-RECORD                PIC X(4096).
       FD  SOAP-OUTPUT-FILE.
       01  SOAP-OUTPUT-RECORD               PIC X(512).

       WORKING-STORAGE SECTION.
       01  WS-PROGRAM-NAMES.
           05  WS-THIS-PROGRAM              PIC X(08) VALUE 'CSTSOAP'.
           05  WS-PGM-CUSTOMER-INQUIRY      PIC X(08) VALUE 'CUSTINQ'.
           05  WS-PGM-CREDIT-INQUIRY        PIC X(08) VALUE 'CRDINQ'.

       01  WS-CONSTANTS.
           05  WS-MAX-BODY-BYTES            PIC S9(09) BINARY
                                            VALUE +8192.
           05  WS-NAMESPACE                 PIC X(44)
               VALUE 'http://bankcore.example/customer/v1'.
           05  WS-ACTION-GET-CUSTOMER       PIC X(16)
                                            VALUE 'GetCustomer'.
           05  WS-ACTION-GET-CREDIT-LIMIT   PIC X(16)
                                            VALUE 'GetCreditLimit'.
           05  WS-REASON-MODULE-MISSING     PIC X(08) VALUE 'NOMODULE'.
           05  WS-REASON-METHOD             PIC X(08) VALUE 'METHOD'.
           05  WS-REASON-BODY-SIZE          PIC X(08) VALUE 'BODYSIZE'.
           05  WS-REASON-ACTION             PIC X(08) VALUE 'ACTION'.
           05  WS-REASON-PAYLOAD            PIC X(08) VALUE 'PAYLOAD'.

       01  WS-ENVIRONMENT.
           05  WS-REQUEST-METHOD            PIC X(16).
           05  WS-CONTENT-LENGTH-TEXT       PIC X(16).
           05  WS-CONTENT-LENGTH            PIC S9(09) BINARY.
           05  WS-SOAP-ACTION               PIC X(64).
           05  WS-CORRELATION-ID            PIC X(36).

       01  WS-BODY                          PIC X(8192).
       01  WS-BODY-LENGTH                   PIC S9(09) BINARY.
       01  WS-SEGMENT-BEFORE                PIC X(8192).
       01  WS-SEGMENT-AFTER                 PIC X(8192).
       01  WS-CUSTOMER-ID-TEXT              PIC X(64).

       01  WS-FILE-STATUSES.
           05  WS-INPUT-FILE-STATUS         PIC X(02).
               88  WS-INPUT-OK                       VALUE '00'.
               88  WS-INPUT-END-OF-FILE              VALUE '10'.
           05  WS-OUTPUT-FILE-STATUS        PIC X(02).
               88  WS-OUTPUT-OK                      VALUE '00'.

       01  WS-CONTROL-FLAGS.
           05  WS-READ-FLAG                 PIC X(01).
               88  WS-READING                        VALUE 'Y'.
               88  WS-READ-FINISHED                  VALUE 'N'.
           05  WS-OUTPUT-FLAG               PIC X(01).
               88  WS-OUTPUT-OPEN                    VALUE 'Y'.
               88  WS-OUTPUT-CLOSED                  VALUE 'N'.

       01  WS-RESULT.
           COPY CSTCODE REPLACING ==:TAG:== BY ==WS==.

       01  WS-TARGET-PROGRAM                PIC X(08).
       01  WS-WORK-AREAS.
           05  WS-INDEX                     PIC S9(09) BINARY.
           05  WS-LENGTH                    PIC S9(09) BINARY.
           05  WS-AMOUNT                    PIC S9(13)V99 COMP-3.
           05  WS-AMOUNT-EDITED             PIC ZZZZZZZZZZZZ9.99.
           05  WS-AMOUNT-TEXT               PIC X(20).
           05  WS-SAFE-VALUE                PIC X(64).
           05  WS-LINE                      PIC X(512).

       01  WS-REQUEST.
           COPY CUSTREQ.
       01  WS-RESPONSE.
           COPY CUSTRSP.

       PROCEDURE DIVISION.
      *================================================================*
       0000-MAIN.
           PERFORM 1000-INITIALIZE
           IF WS-RC-SUCCESS
               PERFORM 2000-READ-BODY
           END-IF
           IF WS-RC-SUCCESS
               PERFORM 3000-RESOLVE-OPERATION
           END-IF
           IF WS-RC-SUCCESS
               PERFORM 4000-EXTRACT-CUSTOMER-ID
           END-IF
           IF WS-RC-SUCCESS
               PERFORM 5000-CALL-CORE
           END-IF
           PERFORM 8000-WRITE-RESPONSE
           PERFORM 9000-FINALIZE
           STOP RUN
           .

      *================================================================*
      * 1000 - ENVIRONMENT AND TRANSPORT LEVEL CHECKS                  *
      *================================================================*
       1000-INITIALIZE.
           SET WS-RC-SUCCESS TO TRUE
           SET WS-OUTPUT-CLOSED TO TRUE
           MOVE SPACES TO WS-BODY
                          WS-REQUEST
                          WS-RESPONSE
                          WS-CUSTOMER-ID-TEXT
           MOVE ZERO TO WS-BODY-LENGTH
           ACCEPT WS-REQUEST-METHOD FROM ENVIRONMENT 'REQUEST_METHOD'
           ACCEPT WS-CONTENT-LENGTH-TEXT FROM ENVIRONMENT
                  'CONTENT_LENGTH'
           ACCEPT WS-SOAP-ACTION FROM ENVIRONMENT 'HTTP_SOAPACTION'
           ACCEPT WS-CORRELATION-ID FROM ENVIRONMENT
                  'HTTP_X_CORRELATION_ID'
           PERFORM 1100-CHECK-METHOD
           IF WS-RC-SUCCESS
               PERFORM 1200-CHECK-CONTENT-LENGTH
           END-IF
           .

       1100-CHECK-METHOD.
           IF WS-REQUEST-METHOD NOT = 'POST'
               SET WS-RC-INVALID-REQUEST TO TRUE
               MOVE WS-REASON-METHOD TO WS-SAFE-VALUE
           END-IF
           .

       1200-CHECK-CONTENT-LENGTH.
           MOVE ZERO TO WS-CONTENT-LENGTH
           IF WS-CONTENT-LENGTH-TEXT NOT = SPACES
              AND FUNCTION TEST-NUMVAL(WS-CONTENT-LENGTH-TEXT) = ZERO
               COMPUTE WS-CONTENT-LENGTH =
                       FUNCTION NUMVAL(WS-CONTENT-LENGTH-TEXT)
               END-COMPUTE
           END-IF
           IF WS-CONTENT-LENGTH > WS-MAX-BODY-BYTES
              OR WS-CONTENT-LENGTH NOT > ZERO
               SET WS-RC-INVALID-REQUEST TO TRUE
               MOVE WS-REASON-BODY-SIZE TO WS-SAFE-VALUE
           END-IF
           .

      *================================================================*
      * 2000 - BODY (READ AS TEXT, NEVER PARSED AS XML)                *
      * THE INPUT IS A PIPE AND IS NOT CLOSED ON PURPOSE: CLOSING IT   *
      * MAKES THE RUNTIME LOG AN UNLOCK WARNING ON EVERY REQUEST.      *
      *================================================================*
       2000-READ-BODY.
           OPEN INPUT SOAP-INPUT-FILE
           IF NOT WS-INPUT-OK
               SET WS-RC-INVALID-REQUEST TO TRUE
               MOVE WS-REASON-PAYLOAD TO WS-SAFE-VALUE
           ELSE
               SET WS-READING TO TRUE
               PERFORM UNTIL WS-READ-FINISHED
                   READ SOAP-INPUT-FILE
                       AT END
                           SET WS-READ-FINISHED TO TRUE
                       NOT AT END
                           PERFORM 2100-APPEND-LINE
                   END-READ
               END-PERFORM
           END-IF
           IF WS-RC-SUCCESS AND WS-BODY-LENGTH NOT > ZERO
               SET WS-RC-INVALID-REQUEST TO TRUE
               MOVE WS-REASON-PAYLOAD TO WS-SAFE-VALUE
           END-IF
           .

       2100-APPEND-LINE.
           MOVE ZERO TO WS-LENGTH
           INSPECT FUNCTION REVERSE(SOAP-INPUT-RECORD)
               TALLYING WS-LENGTH FOR LEADING SPACES
           COMPUTE WS-LENGTH =
                   LENGTH OF SOAP-INPUT-RECORD - WS-LENGTH
           END-COMPUTE
           IF WS-LENGTH > ZERO
              AND WS-BODY-LENGTH + WS-LENGTH <= WS-MAX-BODY-BYTES
               MOVE SOAP-INPUT-RECORD(1:WS-LENGTH)
                 TO WS-BODY(WS-BODY-LENGTH + 1:WS-LENGTH)
               ADD WS-LENGTH TO WS-BODY-LENGTH
           END-IF
           .

      *================================================================*
      * 3000 - OPERATION FROM THE SOAPACTION HEADER (WHITELIST)        *
      *================================================================*
       3000-RESOLVE-OPERATION.
           INSPECT WS-SOAP-ACTION REPLACING ALL '"' BY ' '
           MOVE FUNCTION TRIM(WS-SOAP-ACTION) TO WS-SOAP-ACTION
           MOVE '01' TO CRQ-LAYOUT-VERSION
           MOVE SPACES TO CRQ-CORRELATION-ID
           PERFORM 3100-SET-CORRELATION-ID
           EVALUATE WS-SOAP-ACTION
               WHEN WS-ACTION-GET-CUSTOMER
                   MOVE 'CUSTINQ ' TO CRQ-OPERATION-CODE
                   MOVE WS-PGM-CUSTOMER-INQUIRY TO WS-TARGET-PROGRAM
               WHEN WS-ACTION-GET-CREDIT-LIMIT
                   MOVE 'CRDINQ  ' TO CRQ-OPERATION-CODE
                   MOVE WS-PGM-CREDIT-INQUIRY TO WS-TARGET-PROGRAM
               WHEN OTHER
                   SET WS-RC-INVALID-REQUEST TO TRUE
                   MOVE WS-REASON-ACTION TO WS-SAFE-VALUE
           END-EVALUATE
           .

      *    AN UNSAFE CORRELATION ID IS DISCARDED, NEVER ECHOED.
       3100-SET-CORRELATION-ID.
           IF WS-CORRELATION-ID NOT = SPACES
              AND WS-CORRELATION-ID IS CST-XML-SAFE-CHAR
               MOVE WS-CORRELATION-ID TO CRQ-CORRELATION-ID
           END-IF
           .

      *================================================================*
      * 4000 - CUSTOMER ID: THE ONLY VALUE TAKEN FROM THE BODY         *
      * SPLITTING ON 'customerId>' ALSO ACCEPTS NAMESPACE PREFIXES     *
      * SUCH AS <cus:customerId>. THE VALUE IS VALIDATED BY THE CORE.  *
      *================================================================*
       4000-EXTRACT-CUSTOMER-ID.
           MOVE SPACES TO WS-SEGMENT-BEFORE
                          WS-SEGMENT-AFTER
           UNSTRING WS-BODY DELIMITED BY 'customerId>'
               INTO WS-SEGMENT-BEFORE
                    WS-SEGMENT-AFTER
           END-UNSTRING
           IF WS-SEGMENT-AFTER = SPACES
               SET WS-RC-INVALID-REQUEST TO TRUE
               MOVE WS-REASON-PAYLOAD TO WS-SAFE-VALUE
           ELSE
               UNSTRING WS-SEGMENT-AFTER DELIMITED BY '<'
                   INTO WS-CUSTOMER-ID-TEXT
               END-UNSTRING
               MOVE FUNCTION TRIM(WS-CUSTOMER-ID-TEXT)
                 TO WS-CUSTOMER-ID-TEXT
               MOVE WS-CUSTOMER-ID-TEXT(1:10) TO CRQ-CUSTOMER-ID
           END-IF
           .

      *================================================================*
      * 5000 - CORE CALL                                               *
      *================================================================*
       5000-CALL-CORE.
           MOVE SPACES TO WS-RESPONSE
           CALL WS-TARGET-PROGRAM USING WS-REQUEST
                                        WS-RESPONSE
               ON EXCEPTION
                   SET WS-RC-UNEXPECTED-ERROR TO TRUE
                   MOVE WS-REASON-MODULE-MISSING TO WS-SAFE-VALUE
           END-CALL
           IF WS-RC-SUCCESS
               MOVE CRS-RESPONSE-CODE TO WS-RESPONSE-CODE
           END-IF
           .

      *================================================================*
      * 8000 - XML RENDERING                                           *
      *================================================================*
       8000-WRITE-RESPONSE.
           OPEN OUTPUT SOAP-OUTPUT-FILE
           IF NOT WS-OUTPUT-OK
               STOP RUN
           END-IF
           SET WS-OUTPUT-OPEN TO TRUE
           PERFORM 8100-WRITE-HTTP-HEADER
           PERFORM 8200-WRITE-ENVELOPE-START
           IF WS-RC-CAT-SUCCESS
               PERFORM 8300-WRITE-PAYLOAD
           ELSE
               PERFORM 8400-WRITE-FAULT
           END-IF
           PERFORM 8500-WRITE-ENVELOPE-END
           .

      *    A FAULT ALWAYS TRAVELS WITH HTTP 500, AS REQUIRED BY SOAP 1.1
       8100-WRITE-HTTP-HEADER.
           IF NOT WS-RC-CAT-SUCCESS
               MOVE 'Status: 500 Internal Server Error' TO WS-LINE
               PERFORM 8900-WRITE-LINE
           END-IF
           MOVE 'Content-Type: text/xml; charset=utf-8' TO WS-LINE
           PERFORM 8900-WRITE-LINE
           MOVE SPACES TO WS-LINE
           PERFORM 8900-WRITE-LINE
           .

       8200-WRITE-ENVELOPE-START.
           MOVE '<?xml version="1.0" encoding="UTF-8"?>' TO WS-LINE
           PERFORM 8900-WRITE-LINE
           STRING '<soapenv:Envelope xmlns:soapenv='
                  '"http://schemas.xmlsoap.org/soap/envelope/">'
                  DELIMITED BY SIZE INTO WS-LINE
           END-STRING
           PERFORM 8900-WRITE-LINE
           MOVE '<soapenv:Body>' TO WS-LINE
           PERFORM 8900-WRITE-LINE
           .

       8300-WRITE-PAYLOAD.
           IF CRQ-OP-CUSTOMER-INQUIRY
               PERFORM 8310-WRITE-CUSTOMER-PAYLOAD
           ELSE
               PERFORM 8320-WRITE-CREDIT-PAYLOAD
           END-IF
           .

       8310-WRITE-CUSTOMER-PAYLOAD.
           STRING '<GetCustomerResponse xmlns="'
                  FUNCTION TRIM(WS-NAMESPACE) '">'
                  DELIMITED BY SIZE INTO WS-LINE
           END-STRING
           PERFORM 8900-WRITE-LINE
           MOVE CRS-CI-CUSTOMER-ID TO WS-SAFE-VALUE
           PERFORM 8800-SANITIZE-VALUE
           STRING '  <customerId>' FUNCTION TRIM(WS-SAFE-VALUE)
                  '</customerId>' DELIMITED BY SIZE INTO WS-LINE
           END-STRING
           PERFORM 8900-WRITE-LINE
           MOVE CRS-CI-CUSTOMER-NAME TO WS-SAFE-VALUE
           PERFORM 8800-SANITIZE-VALUE
           STRING '  <name>' FUNCTION TRIM(WS-SAFE-VALUE)
                  '</name>' DELIMITED BY SIZE INTO WS-LINE
           END-STRING
           PERFORM 8900-WRITE-LINE
           MOVE CRS-CI-CUSTOMER-STATUS TO WS-SAFE-VALUE
           PERFORM 8800-SANITIZE-VALUE
           STRING '  <status>' FUNCTION TRIM(WS-SAFE-VALUE)
                  '</status>' DELIMITED BY SIZE INTO WS-LINE
           END-STRING
           PERFORM 8900-WRITE-LINE
           MOVE CRS-CI-DOCUMENT-MASKED TO WS-SAFE-VALUE
           PERFORM 8800-SANITIZE-VALUE
           STRING '  <documentMasked>' FUNCTION TRIM(WS-SAFE-VALUE)
                  '</documentMasked>' DELIMITED BY SIZE INTO WS-LINE
           END-STRING
           PERFORM 8900-WRITE-LINE
           MOVE CRS-CI-REGISTERED-DATE TO WS-SAFE-VALUE
           PERFORM 8800-SANITIZE-VALUE
           STRING '  <registeredDate>' FUNCTION TRIM(WS-SAFE-VALUE)
                  '</registeredDate>' DELIMITED BY SIZE INTO WS-LINE
           END-STRING
           PERFORM 8900-WRITE-LINE
           MOVE '</GetCustomerResponse>' TO WS-LINE
           PERFORM 8900-WRITE-LINE
           .

       8320-WRITE-CREDIT-PAYLOAD.
           STRING '<GetCreditLimitResponse xmlns="'
                  FUNCTION TRIM(WS-NAMESPACE) '">'
                  DELIMITED BY SIZE INTO WS-LINE
           END-STRING
           PERFORM 8900-WRITE-LINE
           MOVE CRS-CR-CUSTOMER-ID TO WS-SAFE-VALUE
           PERFORM 8800-SANITIZE-VALUE
           STRING '  <customerId>' FUNCTION TRIM(WS-SAFE-VALUE)
                  '</customerId>' DELIMITED BY SIZE INTO WS-LINE
           END-STRING
           PERFORM 8900-WRITE-LINE
           MOVE CRS-CR-CURRENCY TO WS-SAFE-VALUE
           PERFORM 8800-SANITIZE-VALUE
           STRING '  <currency>' FUNCTION TRIM(WS-SAFE-VALUE)
                  '</currency>' DELIMITED BY SIZE INTO WS-LINE
           END-STRING
           PERFORM 8900-WRITE-LINE
           MOVE CRS-CR-APPROVED-LIMIT TO WS-AMOUNT
           PERFORM 8810-FORMAT-AMOUNT
           STRING '  <approvedLimit>' FUNCTION TRIM(WS-AMOUNT-TEXT)
                  '</approvedLimit>' DELIMITED BY SIZE INTO WS-LINE
           END-STRING
           PERFORM 8900-WRITE-LINE
           MOVE CRS-CR-USED-LIMIT TO WS-AMOUNT
           PERFORM 8810-FORMAT-AMOUNT
           STRING '  <usedLimit>' FUNCTION TRIM(WS-AMOUNT-TEXT)
                  '</usedLimit>' DELIMITED BY SIZE INTO WS-LINE
           END-STRING
           PERFORM 8900-WRITE-LINE
           MOVE CRS-CR-AVAILABLE-LIMIT TO WS-AMOUNT
           PERFORM 8810-FORMAT-AMOUNT
           STRING '  <availableLimit>' FUNCTION TRIM(WS-AMOUNT-TEXT)
                  '</availableLimit>' DELIMITED BY SIZE INTO WS-LINE
           END-STRING
           PERFORM 8900-WRITE-LINE
           MOVE '</GetCreditLimitResponse>' TO WS-LINE
           PERFORM 8900-WRITE-LINE
           .

      *    1XXX AND 2XXX ARE THE CALLER'S FAULT, 9XXX ARE OURS.
       8400-WRITE-FAULT.
           MOVE '<soapenv:Fault>' TO WS-LINE
           PERFORM 8900-WRITE-LINE
           IF WS-RC-CAT-TECHNICAL
               MOVE '  <faultcode>soapenv:Server</faultcode>'
                 TO WS-LINE
           ELSE
               MOVE '  <faultcode>soapenv:Client</faultcode>'
                 TO WS-LINE
           END-IF
           PERFORM 8900-WRITE-LINE
           MOVE CRS-RESPONSE-MESSAGE TO WS-SAFE-VALUE
           PERFORM 8800-SANITIZE-VALUE
           IF WS-SAFE-VALUE = SPACES
               MOVE 'REQUEST REJECTED' TO WS-SAFE-VALUE
           END-IF
           STRING '  <faultstring>' FUNCTION TRIM(WS-SAFE-VALUE)
                  '</faultstring>' DELIMITED BY SIZE INTO WS-LINE
           END-STRING
           PERFORM 8900-WRITE-LINE
           MOVE '  <detail>' TO WS-LINE
           PERFORM 8900-WRITE-LINE
           STRING '    <error xmlns="' FUNCTION TRIM(WS-NAMESPACE) '">'
                  DELIMITED BY SIZE INTO WS-LINE
           END-STRING
           PERFORM 8900-WRITE-LINE
           STRING '      <code>' WS-RESPONSE-CODE '</code>'
                  DELIMITED BY SIZE INTO WS-LINE
           END-STRING
           PERFORM 8900-WRITE-LINE
           MOVE '    </error>' TO WS-LINE
           PERFORM 8900-WRITE-LINE
           MOVE '  </detail>' TO WS-LINE
           PERFORM 8900-WRITE-LINE
           MOVE '</soapenv:Fault>' TO WS-LINE
           PERFORM 8900-WRITE-LINE
           .

       8500-WRITE-ENVELOPE-END.
           MOVE '</soapenv:Body>' TO WS-LINE
           PERFORM 8900-WRITE-LINE
           MOVE '</soapenv:Envelope>' TO WS-LINE
           PERFORM 8900-WRITE-LINE
           .

      *    ANY CHARACTER OUTSIDE THE SAFE SET BECOMES A SPACE, SO DATA
      *    CAN NEVER INJECT MARKUP INTO THE RESPONSE.
       8800-SANITIZE-VALUE.
           PERFORM VARYING WS-INDEX FROM 1 BY 1
                   UNTIL WS-INDEX > LENGTH OF WS-SAFE-VALUE
               IF WS-SAFE-VALUE(WS-INDEX:1) IS NOT CST-XML-SAFE-CHAR
                   MOVE SPACE TO WS-SAFE-VALUE(WS-INDEX:1)
               END-IF
           END-PERFORM
           .

       8810-FORMAT-AMOUNT.
           MOVE WS-AMOUNT TO WS-AMOUNT-EDITED
           MOVE FUNCTION TRIM(WS-AMOUNT-EDITED) TO WS-AMOUNT-TEXT
           .

       8900-WRITE-LINE.
           MOVE WS-LINE TO SOAP-OUTPUT-RECORD
           WRITE SOAP-OUTPUT-RECORD
           MOVE SPACES TO WS-LINE
           .

      *================================================================*
       9000-FINALIZE.
           IF WS-OUTPUT-OPEN
               CLOSE SOAP-OUTPUT-FILE
               SET WS-OUTPUT-CLOSED TO TRUE
           END-IF
           .
