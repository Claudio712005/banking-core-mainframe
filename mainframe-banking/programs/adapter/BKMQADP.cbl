       IDENTIFICATION DIVISION.
       PROGRAM-ID. BKMQADP.
      *================================================================*
      * PROGRAM  : BKMQADP                                             *
      * TYPE     : CICS TRANSACTION PROGRAM (IBM MQ TRANSPORT ADAPTER) *
      * TARGET   : *** Z/OS ONLY *** - REQUIRES THE CICS TRANSLATOR /  *
      *            COPROCESSOR AND THE IBM MQ COBOL COPYBOOKS          *
      *            (SCSQCOBC). NOT BUILT BY SCRIPTS/BUILD.SH.          *
      *            THE IBM MQ COPYBOOK MEMBER NAMES (CMQV, CMQMDV,     *
      *            CMQODV, CMQGMOV, CMQPMOV, CMQTML) MUST BE CHECKED   *
      *            AGAINST THE INSTALLED MQ VERSION.                   *
      * PURPOSE  : ONLINE EQUIVALENT OF BKBATDRV. STARTED BY THE CICS  *
      *            TRIGGER MONITOR (CKTI) WHEN A REQUEST QUEUE BECOMES *
      *            NON-EMPTY. CONSUMES EVERY MESSAGE, CALLS THE ENTRY  *
      *            PROGRAM AND SENDS THE REPLY, ONE UNIT OF WORK PER   *
      *            MESSAGE.                                            *
      *----------------------------------------------------------------*
      * ONE QUEUE PER OPERATION                                        *
      *   EACH REQUEST QUEUE HAS ITS OWN PROCESS DEFINITION:           *
      *     APPLICID = TRANSID (BKAI/BKDP/BKWD/BKTI)                   *
      *     USERDATA = OPERATION SERVED ('ACCTINQ ' ETC.)              *
      *   THE SAME PROGRAM RUNS UNDER FOUR TRANSIDS, SO EACH OPERATION *
      *   HAS ITS OWN RACF PROFILES (QUEUE + TRANSACTION). A MESSAGE   *
      *   WHOSE OPERATION-CODE DIFFERS FROM USERDATA IS REJECTED.      *
      *----------------------------------------------------------------*
      * MESSAGE DISPOSITION (ONE CICS UNIT OF WORK PER MESSAGE)        *
      *   BACKOUT COUNT >= BOTHRESH  -> BACKOUT QUEUE + REPLY 9004,    *
      *                                 COMMIT                         *
      *   NOT A REQUEST / NO REPLYTOQ -> BACKOUT QUEUE, COMMIT         *
      *   FORMAT, LENGTH OR OPERATION -> REPLY 1001, COMMIT            *
      *   INVALID                                                      *
      *   RESPONSE 0XXX / 1XXX / 2XXX -> REPLY, COMMIT                 *
      *   RESPONSE 3XXX / 9XXX / NONE -> ROLLBACK, NO REPLY. THE       *
      *                                 MESSAGE IS REDELIVERED UNTIL   *
      *                                 BOTHRESH IS REACHED.           *
      *   THE REPLY IS PUT UNDER SYNCPOINT: IT IS SENT ONLY IF THE     *
      *   DB2 CHANGES ARE COMMITTED, AND NOT AT ALL OTHERWISE.         *
      *----------------------------------------------------------------*
      * ENTRY PROGRAMS ARE INVOKED WITH CALL (NOT EXEC CICS LINK):     *
      * THEY KEEP THE TWO-PARAMETER INTERFACE (REQUEST, RESPONSE),     *
      * RUN IN THE SAME TASK AND UNIT OF WORK, AND DO NOT ISSUE        *
      * EXEC CICS COMMANDS.                                            *
      *----------------------------------------------------------------*
      * LOGGING  : TD QUEUE BKLG (PLACEHOLDER). DEFINE IT AS           *
      *            EXTRAPARTITION OR NON-RECOVERABLE, OTHERWISE LOG    *
      *            RECORDS ARE LOST WITH EVERY ROLLBACK. NO PAYLOAD,   *
      *            ACCOUNT OR CUSTOMER DATA IS EVER LOGGED.            *
      * SEE      : DOCS/MQ-INTEGRATION.MD                              *
      *================================================================*
       ENVIRONMENT DIVISION.

       DATA DIVISION.
       WORKING-STORAGE SECTION.
       01  WS-PROGRAM-NAMES.
           05  WS-THIS-PROGRAM              PIC X(08) VALUE 'BKMQADP'.
           05  WS-PGM-RESPONSE-BUILDER      PIC X(08) VALUE 'BKRESP'.
           05  WS-PGM-ACCOUNT-INQUIRY       PIC X(08) VALUE 'ACCTINQ'.
           05  WS-PGM-DEPOSIT               PIC X(08) VALUE 'ACCTDEP'.
           05  WS-PGM-WITHDRAWAL            PIC X(08) VALUE 'ACCTWDR'.
           05  WS-PGM-TRANSACTION-INQUIRY   PIC X(08) VALUE 'TRXINQ'.

       01  WS-CONSTANTS.
           05  WS-REQUEST-BUFFER-LENGTH     PIC S9(09) BINARY
                                            VALUE +200.
           05  WS-RESPONSE-BUFFER-LENGTH    PIC S9(09) BINARY
                                            VALUE +300.
      *    MILLISECONDS TO WAIT FOR MORE MESSAGES BEFORE ENDING
           05  WS-GET-WAIT-INTERVAL         PIC S9(09) BINARY
                                            VALUE +1000.
           05  WS-LOG-TDQ                   PIC X(04) VALUE 'BKLG'.
           05  WS-REASON-BACKOUT            PIC X(08) VALUE 'BACKOUT'.
           05  WS-REASON-NO-REPLY-TO        PIC X(08) VALUE 'NOREPLY'.
           05  WS-REASON-FORMAT             PIC X(08) VALUE 'FORMAT'.
           05  WS-REASON-LENGTH             PIC X(08) VALUE 'LENGTH'.
           05  WS-REASON-WRONG-OPERATION    PIC X(08) VALUE 'WRONGOP'.
           05  WS-REASON-MODULE-MISSING     PIC X(08) VALUE 'NOMODULE'.

       01  WS-LOG-EVENTS.
           05  WS-EVENT-NO-TRIGGER          PIC X(16)
                                            VALUE 'NO TRIGGER DATA'.
           05  WS-EVENT-BAD-USERDATA        PIC X(16)
                                            VALUE 'BAD USERDATA'.
           05  WS-EVENT-OPEN-FAILED         PIC X(16)
                                            VALUE 'MQOPEN FAILED'.
           05  WS-EVENT-INQUIRE-FAILED      PIC X(16)
                                            VALUE 'MQINQ FAILED'.
           05  WS-EVENT-NO-BACKOUT-POLICY   PIC X(16)
                                            VALUE 'NO BACKOUT QUEUE'.
           05  WS-EVENT-GET-FAILED          PIC X(16)
                                            VALUE 'MQGET FAILED'.
           05  WS-EVENT-REJECTED            PIC X(16)
                                            VALUE 'MSG REJECTED'.
           05  WS-EVENT-DIVERTED            PIC X(16)
                                            VALUE 'MSG DIVERTED'.
           05  WS-EVENT-DIVERT-FAILED       PIC X(16)
                                            VALUE 'DIVERT FAILED'.
           05  WS-EVENT-REPLY-FAILED        PIC X(16)
                                            VALUE 'REPLY FAILED'.
           05  WS-EVENT-SYNCPOINT-FAILED    PIC X(16)
                                            VALUE 'SYNCPOINT FAILED'.
           05  WS-EVENT-CLOSE-FAILED        PIC X(16)
                                            VALUE 'MQCLOSE FAILED'.

       01  WS-CONTROL-FLAGS.
           05  WS-PROCESSING-FLAG           PIC X(01).
               88  WS-CONTINUE-PROCESSING            VALUE 'Y'.
               88  WS-STOP-PROCESSING                VALUE 'N'.
           05  WS-QUEUE-FLAG                PIC X(01).
               88  WS-QUEUE-OPEN                     VALUE 'Y'.
               88  WS-QUEUE-CLOSED                   VALUE 'N'.
           05  WS-GET-FLAG                  PIC X(01).
               88  WS-MESSAGE-RECEIVED               VALUE 'Y'.
               88  WS-NO-MESSAGE                     VALUE 'N'.
           05  WS-ACTION-FLAG               PIC X(01).
               88  WS-ACTION-PROCESS                 VALUE 'P'.
               88  WS-ACTION-REJECT                  VALUE 'R'.
               88  WS-ACTION-DIVERT                  VALUE 'D'.
           05  WS-UOW-FLAG                  PIC X(01).
               88  WS-UOW-COMMIT                     VALUE 'C'.
               88  WS-UOW-ROLLBACK                   VALUE 'R'.
           05  WS-REPLY-FLAG                PIC X(01).
               88  WS-REPLY-SENT                     VALUE 'Y'.
               88  WS-REPLY-NOT-SENT                 VALUE 'N'.

       01  WS-MQ-CALL-AREAS.
           05  WS-HCONN                     PIC S9(09) BINARY.
           05  WS-HOBJ                      PIC S9(09) BINARY.
           05  WS-OPEN-OPTIONS              PIC S9(09) BINARY.
           05  WS-CLOSE-OPTIONS             PIC S9(09) BINARY.
           05  WS-COMPCODE                  PIC S9(09) BINARY.
           05  WS-REASON                    PIC S9(09) BINARY.
           05  WS-DATA-LENGTH               PIC S9(09) BINARY.
           05  WS-DIVERT-LENGTH             PIC S9(09) BINARY.
           05  WS-REPORT-QUOTIENT           PIC S9(09) BINARY.

      *    MQINQ: BACKOUT THRESHOLD AND BACKOUT QUEUE OF THE INPUT QUEUE
       01  WS-BACKOUT-INQUIRY.
           05  WS-SELECTOR-COUNT            PIC S9(09) BINARY
                                            VALUE +2.
           05  WS-SELECTORS.
               10  WS-SELECTOR              PIC S9(09) BINARY
                                            OCCURS 2 TIMES.
           05  WS-INT-ATTR-COUNT            PIC S9(09) BINARY
                                            VALUE +1.
           05  WS-BACKOUT-THRESHOLD         PIC S9(09) BINARY.
           05  WS-CHAR-ATTR-LENGTH          PIC S9(09) BINARY
                                            VALUE +48.
           05  WS-BACKOUT-QUEUE-NAME        PIC X(48).

       01  WS-CICS-AREAS.
           05  WS-CICS-RESP                 PIC S9(08) BINARY.
           05  WS-LOG-RESP                  PIC S9(08) BINARY.
           05  WS-TRIGGER-LENGTH            PIC S9(04) BINARY.
           05  WS-LOG-LENGTH                PIC S9(04) BINARY.

       01  WS-SERVED-OPERATION              PIC X(08).
       01  WS-TARGET-PROGRAM                PIC X(08).
       01  WS-TECH-CODE                     PIC X(08).

       01  WS-LOG-RECORD.
           05  WS-LOG-PROGRAM               PIC X(08).
           05  FILLER                       PIC X(01) VALUE SPACE.
           05  WS-LOG-TRANSACTION           PIC X(04).
           05  FILLER                       PIC X(01) VALUE SPACE.
           05  WS-LOG-EVENT                 PIC X(16).
           05  FILLER                       PIC X(08) VALUE ' REASON='.
           05  WS-LOG-REASON                PIC 9(09).
           05  FILLER                       PIC X(06) VALUE ' TECH='.
           05  WS-LOG-TECH                  PIC X(08).
           05  FILLER                       PIC X(06) VALUE ' CORR='.
           05  WS-LOG-CORRELATION           PIC X(36).

      *    IBM MQ DEFINITIONS (SCSQCOBC)
       01  MQM-CONSTANTS.
           COPY CMQV.
       01  WS-TRIGGER-MESSAGE.
           COPY CMQTML.
       01  WS-QUEUE-OD.
           COPY CMQODV.
      *    PRISTINE COPIES USED TO RESET THE STRUCTURES BEFORE EACH CALL
       01  WS-DEFAULT-OD.
           COPY CMQODV.
       01  WS-DEFAULT-MD.
           COPY CMQMDV.
       01  WS-TARGET-OD.
           COPY CMQODV.
       01  WS-REQUEST-MD.
           COPY CMQMDV.
       01  WS-REPLY-MD.
           COPY CMQMDV.
       01  WS-GET-OPTIONS.
           COPY CMQGMOV.
       01  WS-PUT-OPTIONS.
           COPY CMQPMOV.

      *    BANKCORE CONTRACT
       01  WS-REQUEST.
           COPY REQUEST.
       01  WS-RESPONSE.
           COPY RESPONSE.
       01  WS-RESULT.
           COPY RSPCODE REPLACING ==:TAG:== BY ==WS==.
       01  WS-RESPONSE-CONTROL.
           COPY RSPCTL REPLACING ==:TAG:== BY ==RCT==.

       PROCEDURE DIVISION.
      *================================================================*
       0000-MAIN.
           PERFORM 1000-INITIALIZE
           PERFORM 2000-PROCESS-NEXT-MESSAGE
               UNTIL WS-STOP-PROCESSING
           PERFORM 9000-FINALIZE
           EXEC CICS RETURN END-EXEC
           .

      *================================================================*
      * 1000 - START-UP: TRIGGER DATA, SERVED OPERATION, QUEUE, POLICY *
      *================================================================*
       1000-INITIALIZE.
           SET WS-CONTINUE-PROCESSING TO TRUE
           SET WS-QUEUE-CLOSED        TO TRUE
           MOVE SPACES                TO WS-REQUEST
                                         WS-RESPONSE
                                         WS-TECH-CODE
           INITIALIZE WS-RESPONSE-CONTROL
           MOVE SPACES TO WS-LOG-EVENT
                          WS-LOG-TECH
           MOVE ZERO   TO WS-LOG-REASON
           MOVE MQHC-DEF-HCONN     TO WS-HCONN
           MOVE MQHO-UNUSABLE-HOBJ TO WS-HOBJ
           PERFORM 1100-READ-TRIGGER-MESSAGE
           IF WS-CONTINUE-PROCESSING
               PERFORM 1200-RESOLVE-SERVED-OPERATION
           END-IF
           IF WS-CONTINUE-PROCESSING
               PERFORM 1300-OPEN-REQUEST-QUEUE
           END-IF
           IF WS-CONTINUE-PROCESSING
               PERFORM 1400-READ-BACKOUT-POLICY
           END-IF
           .

      *    A TASK STARTED WITHOUT TRIGGER DATA HAS NOTHING TO SERVE.
       1100-READ-TRIGGER-MESSAGE.
           MOVE LENGTH OF WS-TRIGGER-MESSAGE TO WS-TRIGGER-LENGTH
           EXEC CICS RETRIEVE
               INTO(WS-TRIGGER-MESSAGE)
               LENGTH(WS-TRIGGER-LENGTH)
               RESP(WS-CICS-RESP)
           END-EXEC
           IF WS-CICS-RESP NOT = DFHRESP(NORMAL)
               MOVE WS-EVENT-NO-TRIGGER TO WS-LOG-EVENT
               MOVE WS-CICS-RESP        TO WS-LOG-REASON
               PERFORM 8000-WRITE-LOG
               SET WS-STOP-PROCESSING TO TRUE
           END-IF
           .

      *    THE CONTRACT'S OWN 88-LEVELS ARE THE WHITELIST: THE SERVED
      *    OPERATION IS PLACED IN THE (STILL EMPTY) REQUEST AREA ONLY
      *    TO BE TESTED, AND THE AREA IS CLEARED AFTERWARDS.
       1200-RESOLVE-SERVED-OPERATION.
           MOVE MQTM-USERDATA(1:8) TO WS-SERVED-OPERATION
           MOVE WS-SERVED-OPERATION TO REQ-OPERATION-CODE
           EVALUATE TRUE
               WHEN REQ-OP-ACCOUNT-INQUIRY
                   MOVE WS-PGM-ACCOUNT-INQUIRY     TO WS-TARGET-PROGRAM
               WHEN REQ-OP-DEPOSIT
                   MOVE WS-PGM-DEPOSIT             TO WS-TARGET-PROGRAM
               WHEN REQ-OP-WITHDRAWAL
                   MOVE WS-PGM-WITHDRAWAL          TO WS-TARGET-PROGRAM
               WHEN REQ-OP-TRANSACTION-INQUIRY
                   MOVE WS-PGM-TRANSACTION-INQUIRY TO WS-TARGET-PROGRAM
               WHEN OTHER
                   MOVE WS-EVENT-BAD-USERDATA      TO WS-LOG-EVENT
                   PERFORM 8000-WRITE-LOG
                   SET WS-STOP-PROCESSING TO TRUE
           END-EVALUATE
           MOVE SPACES TO WS-REQUEST
           .

      *    SAVE-ALL-CONTEXT KEEPS THE ORIGINAL IDENTITY FOR MESSAGES
      *    MOVED TO THE BACKOUT QUEUE.
       1300-OPEN-REQUEST-QUEUE.
           MOVE WS-DEFAULT-OD TO WS-QUEUE-OD
           MOVE MQTM-QNAME TO MQOD-OBJECTNAME OF WS-QUEUE-OD
           COMPUTE WS-OPEN-OPTIONS = MQOO-INPUT-SHARED
                                   + MQOO-INQUIRE
                                   + MQOO-SAVE-ALL-CONTEXT
                                   + MQOO-FAIL-IF-QUIESCING
           END-COMPUTE
           CALL 'MQOPEN' USING WS-HCONN
                               WS-QUEUE-OD
                               WS-OPEN-OPTIONS
                               WS-HOBJ
                               WS-COMPCODE
                               WS-REASON
           END-CALL
           IF WS-COMPCODE = MQCC-OK
               SET WS-QUEUE-OPEN TO TRUE
           ELSE
               MOVE WS-EVENT-OPEN-FAILED TO WS-LOG-EVENT
               MOVE WS-REASON            TO WS-LOG-REASON
               PERFORM 8000-WRITE-LOG
               SET WS-STOP-PROCESSING TO TRUE
           END-IF
           .

      *    FAIL-SAFE: WITHOUT A BACKOUT POLICY A FAILING MESSAGE WOULD
      *    BE REDELIVERED FOREVER, SO NO MESSAGE IS PROCESSED AT ALL.
       1400-READ-BACKOUT-POLICY.
           MOVE MQIA-BACKOUT-THRESHOLD  TO WS-SELECTOR(1)
           MOVE MQCA-BACKOUT-REQ-Q-NAME TO WS-SELECTOR(2)
           CALL 'MQINQ' USING WS-HCONN
                              WS-HOBJ
                              WS-SELECTOR-COUNT
                              WS-SELECTORS
                              WS-INT-ATTR-COUNT
                              WS-BACKOUT-THRESHOLD
                              WS-CHAR-ATTR-LENGTH
                              WS-BACKOUT-QUEUE-NAME
                              WS-COMPCODE
                              WS-REASON
           END-CALL
           EVALUATE TRUE
               WHEN WS-COMPCODE NOT = MQCC-OK
                   MOVE WS-EVENT-INQUIRE-FAILED TO WS-LOG-EVENT
                   MOVE WS-REASON               TO WS-LOG-REASON
                   PERFORM 8000-WRITE-LOG
                   SET WS-STOP-PROCESSING TO TRUE
               WHEN WS-BACKOUT-THRESHOLD NOT > ZERO
               WHEN WS-BACKOUT-QUEUE-NAME = SPACES
                   MOVE WS-EVENT-NO-BACKOUT-POLICY TO WS-LOG-EVENT
                   PERFORM 8000-WRITE-LOG
                   SET WS-STOP-PROCESSING TO TRUE
               WHEN OTHER
                   CONTINUE
           END-EVALUATE
           .

      *================================================================*
      * 2000 - ONE MESSAGE = ONE UNIT OF WORK                          *
      * THE OUTCOME STARTS AS ROLLBACK AND IS CHANGED TO COMMIT ONLY   *
      * WHEN THE MESSAGE HAS BEEN FULLY HANDLED (FAIL-SAFE).           *
      *================================================================*
       2000-PROCESS-NEXT-MESSAGE.
           PERFORM 2100-GET-MESSAGE
           IF WS-MESSAGE-RECEIVED
               SET WS-UOW-ROLLBACK TO TRUE
               MOVE SPACES TO WS-TECH-CODE
               PERFORM 2200-CLASSIFY-MESSAGE
               EVALUATE TRUE
                   WHEN WS-ACTION-DIVERT
                       PERFORM 3000-DIVERT-TO-BACKOUT-QUEUE
                   WHEN WS-ACTION-REJECT
                       PERFORM 4000-REJECT-MESSAGE
                   WHEN WS-ACTION-PROCESS
                       PERFORM 5000-PROCESS-REQUEST
               END-EVALUATE
               PERFORM 6000-END-UNIT-OF-WORK
           END-IF
           .

      *    MSGID/CORRELID/ENCODING/CCSID ARE RESET BEFORE EVERY GET:
      *    MQGET OVERWRITES THEM, AND STALE VALUES WOULD EITHER MATCH
      *    ONLY ONE MESSAGE OR DISABLE DATA CONVERSION.
      *    TRUNCATED MESSAGES ARE ACCEPTED (AND REJECTED LATER) SO AN
      *    OVERSIZED MESSAGE CANNOT BLOCK THE QUEUE.
       2100-GET-MESSAGE.
           SET WS-NO-MESSAGE TO TRUE
           MOVE SPACES        TO WS-REQUEST
           MOVE WS-DEFAULT-MD TO WS-REQUEST-MD
           COMPUTE MQGMO-OPTIONS OF WS-GET-OPTIONS =
                   MQGMO-SYNCPOINT
                 + MQGMO-WAIT
                 + MQGMO-CONVERT
                 + MQGMO-ACCEPT-TRUNCATED-MSG
                 + MQGMO-FAIL-IF-QUIESCING
           END-COMPUTE
           MOVE WS-GET-WAIT-INTERVAL
             TO MQGMO-WAITINTERVAL OF WS-GET-OPTIONS
           CALL 'MQGET' USING WS-HCONN
                              WS-HOBJ
                              WS-REQUEST-MD
                              WS-GET-OPTIONS
                              WS-REQUEST-BUFFER-LENGTH
                              WS-REQUEST
                              WS-DATA-LENGTH
                              WS-COMPCODE
                              WS-REASON
           END-CALL
           EVALUATE TRUE
               WHEN WS-COMPCODE = MQCC-OK
               WHEN WS-COMPCODE = MQCC-WARNING
                   SET WS-MESSAGE-RECEIVED TO TRUE
               WHEN WS-REASON = MQRC-NO-MSG-AVAILABLE
                   SET WS-STOP-PROCESSING TO TRUE
               WHEN OTHER
                   MOVE WS-EVENT-GET-FAILED TO WS-LOG-EVENT
                   MOVE WS-REASON           TO WS-LOG-REASON
                   PERFORM 8000-WRITE-LOG
                   SET WS-STOP-PROCESSING TO TRUE
           END-EVALUATE
           .

      *    ORDER MATTERS: A POISON MESSAGE IS DIVERTED BEFORE ANY OTHER
      *    CHECK, AND ONLY WELL-FORMED MESSAGES REACH THE ENTRY PROGRAM.
      *    A FORMAT OTHER THAN MQSTR (E.G. A JMS RFH2 HEADER) OR A
      *    FAILED CONVERSION MEANS THE BYTES CANNOT BE TRUSTED: THE
      *    REQUEST AREA IS CLEARED SO NOTHING OF IT IS ECHOED.
       2200-CLASSIFY-MESSAGE.
           EVALUATE TRUE
               WHEN MQMD-BACKOUTCOUNT OF WS-REQUEST-MD
                    >= WS-BACKOUT-THRESHOLD
                   SET WS-ACTION-DIVERT TO TRUE
                   MOVE WS-REASON-BACKOUT TO WS-TECH-CODE
               WHEN MQMD-MSGTYPE OF WS-REQUEST-MD NOT = MQMT-REQUEST
               WHEN MQMD-REPLYTOQ OF WS-REQUEST-MD = SPACES
                   SET WS-ACTION-DIVERT TO TRUE
                   MOVE WS-REASON-NO-REPLY-TO TO WS-TECH-CODE
               WHEN MQMD-FORMAT OF WS-REQUEST-MD NOT = MQFMT-STRING
               WHEN WS-COMPCODE = MQCC-WARNING
                AND WS-REASON NOT = MQRC-TRUNCATED-MSG-ACCEPTED
                   SET WS-ACTION-REJECT TO TRUE
                   MOVE WS-REASON-FORMAT TO WS-TECH-CODE
                   MOVE SPACES TO WS-REQUEST
               WHEN WS-DATA-LENGTH NOT = WS-REQUEST-BUFFER-LENGTH
                   SET WS-ACTION-REJECT TO TRUE
                   MOVE WS-REASON-LENGTH TO WS-TECH-CODE
               WHEN REQ-OPERATION-CODE NOT = WS-SERVED-OPERATION
                   SET WS-ACTION-REJECT TO TRUE
                   MOVE WS-REASON-WRONG-OPERATION TO WS-TECH-CODE
               WHEN OTHER
                   SET WS-ACTION-PROCESS TO TRUE
           END-EVALUATE
           .

      *================================================================*
      * 3000 - POISON / UNANSWERABLE MESSAGES                          *
      * THE ORIGINAL MESSAGE (DESCRIPTOR AND CONTEXT) IS MOVED TO THE  *
      * BACKOUT QUEUE FOR INVESTIGATION. A FAILED 9004 REPLY DOES NOT  *
      * UNDO THE DIVERSION, OTHERWISE THE MESSAGE WOULD LOOP.          *
      *================================================================*
       3000-DIVERT-TO-BACKOUT-QUEUE.
           MOVE WS-EVENT-DIVERTED TO WS-LOG-EVENT
           MOVE WS-REASON         TO WS-LOG-REASON
           MOVE WS-TECH-CODE      TO WS-LOG-TECH
           PERFORM 8000-WRITE-LOG
           MOVE WS-DEFAULT-OD TO WS-TARGET-OD
           MOVE WS-BACKOUT-QUEUE-NAME
             TO MQOD-OBJECTNAME OF WS-TARGET-OD
           COMPUTE MQPMO-OPTIONS OF WS-PUT-OPTIONS =
                   MQPMO-SYNCPOINT
                 + MQPMO-PASS-ALL-CONTEXT
                 + MQPMO-FAIL-IF-QUIESCING
           END-COMPUTE
           MOVE WS-HOBJ TO MQPMO-CONTEXT OF WS-PUT-OPTIONS
           COMPUTE WS-DIVERT-LENGTH =
                   FUNCTION MIN(WS-DATA-LENGTH
                                WS-REQUEST-BUFFER-LENGTH)
           END-COMPUTE
           CALL 'MQPUT1' USING WS-HCONN
                               WS-TARGET-OD
                               WS-REQUEST-MD
                               WS-PUT-OPTIONS
                               WS-DIVERT-LENGTH
                               WS-REQUEST
                               WS-COMPCODE
                               WS-REASON
           END-CALL
           IF WS-COMPCODE = MQCC-OK
               SET WS-UOW-COMMIT TO TRUE
               IF WS-TECH-CODE = WS-REASON-BACKOUT
                   SET WS-RC-RETRIES-EXHAUSTED TO TRUE
                   PERFORM 7100-BUILD-ADAPTER-RESPONSE
                   PERFORM 7000-SEND-REPLY
               END-IF
           ELSE
               MOVE WS-EVENT-DIVERT-FAILED TO WS-LOG-EVENT
               MOVE WS-REASON              TO WS-LOG-REASON
               PERFORM 8000-WRITE-LOG
               SET WS-STOP-PROCESSING TO TRUE
           END-IF
           .

      *================================================================*
      * 4000 - MALFORMED MESSAGE: ANSWER 1001, CONSUME THE MESSAGE     *
      *================================================================*
       4000-REJECT-MESSAGE.
           MOVE WS-EVENT-REJECTED TO WS-LOG-EVENT
           MOVE WS-REASON         TO WS-LOG-REASON
           MOVE WS-TECH-CODE      TO WS-LOG-TECH
           PERFORM 8000-WRITE-LOG
           SET WS-RC-INVALID-REQUEST TO TRUE
           PERFORM 7100-BUILD-ADAPTER-RESPONSE
           PERFORM 7000-SEND-REPLY
           IF WS-REPLY-SENT
               SET WS-UOW-COMMIT TO TRUE
           END-IF
           .

      *================================================================*
      * 5000 - BUSINESS REQUEST                                        *
      * ONLY DEFINITIVE OUTCOMES ARE ANSWERED AND COMMITTED. TRANSIENT *
      * AND TECHNICAL FAILURES ROLL EVERYTHING BACK, INCLUDING THE GET,*
      * SO MQ REDELIVERS THE MESSAGE (BACKOUT COUNT + 1).              *
      *================================================================*
       5000-PROCESS-REQUEST.
           MOVE SPACES TO WS-RESPONSE
           CALL WS-TARGET-PROGRAM USING WS-REQUEST
                                        WS-RESPONSE
               ON EXCEPTION
                   SET WS-RC-UNEXPECTED-ERROR TO TRUE
                   MOVE WS-REASON-MODULE-MISSING TO WS-TECH-CODE
                   PERFORM 7100-BUILD-ADAPTER-RESPONSE
           END-CALL
           MOVE RSP-RESPONSE-CODE TO WS-RESPONSE-CODE
           EVALUATE TRUE
               WHEN WS-RC-CAT-SUCCESS
               WHEN WS-RC-CAT-VALIDATION
               WHEN WS-RC-CAT-BUSINESS
                   PERFORM 7000-SEND-REPLY
                   IF WS-REPLY-SENT
                       SET WS-UOW-COMMIT TO TRUE
                   END-IF
               WHEN OTHER
                   SET WS-UOW-ROLLBACK TO TRUE
           END-EVALUATE
           .

      *================================================================*
      * 6000 - COMMIT OR BACK OUT DB2 CHANGES, MQGET AND MQPUT TOGETHER*
      *================================================================*
       6000-END-UNIT-OF-WORK.
           IF WS-UOW-COMMIT
               EXEC CICS SYNCPOINT
                   RESP(WS-CICS-RESP)
               END-EXEC
           ELSE
               EXEC CICS SYNCPOINT ROLLBACK
                   RESP(WS-CICS-RESP)
               END-EXEC
           END-IF
           IF WS-CICS-RESP NOT = DFHRESP(NORMAL)
               MOVE WS-EVENT-SYNCPOINT-FAILED TO WS-LOG-EVENT
               MOVE WS-CICS-RESP              TO WS-LOG-REASON
               PERFORM 8000-WRITE-LOG
               SET WS-STOP-PROCESSING TO TRUE
           END-IF
           .

      *================================================================*
      * 7000 - REPLY                                                   *
      * CORRELID FOLLOWS THE REQUESTER'S REPORT OPTIONS: REQUEST MSGID *
      * BY DEFAULT, REQUEST CORRELID WHEN MQRO_PASS_CORREL_ID IS SET.  *
      * PERSISTENCE, PRIORITY AND REMAINING EXPIRY ARE INHERITED, SO   *
      * A REPLY NEVER OUTLIVES THE REQUESTER'S INTEREST IN IT.         *
      *================================================================*
       7000-SEND-REPLY.
           SET WS-REPLY-NOT-SENT TO TRUE
           MOVE WS-DEFAULT-MD TO WS-REPLY-MD
           MOVE MQMT-REPLY    TO MQMD-MSGTYPE OF WS-REPLY-MD
           MOVE MQFMT-STRING  TO MQMD-FORMAT  OF WS-REPLY-MD
           MOVE MQMD-PERSISTENCE OF WS-REQUEST-MD
             TO MQMD-PERSISTENCE OF WS-REPLY-MD
           MOVE MQMD-PRIORITY    OF WS-REQUEST-MD
             TO MQMD-PRIORITY    OF WS-REPLY-MD
           MOVE MQMD-EXPIRY      OF WS-REQUEST-MD
             TO MQMD-EXPIRY      OF WS-REPLY-MD
           PERFORM 7010-SET-REPLY-CORRELATION
           MOVE WS-DEFAULT-OD TO WS-TARGET-OD
           MOVE MQMD-REPLYTOQ    OF WS-REQUEST-MD
             TO MQOD-OBJECTNAME     OF WS-TARGET-OD
           MOVE MQMD-REPLYTOQMGR OF WS-REQUEST-MD
             TO MQOD-OBJECTQMGRNAME OF WS-TARGET-OD
           COMPUTE MQPMO-OPTIONS OF WS-PUT-OPTIONS =
                   MQPMO-SYNCPOINT
                 + MQPMO-NEW-MSG-ID
                 + MQPMO-FAIL-IF-QUIESCING
           END-COMPUTE
           MOVE ZERO TO MQPMO-CONTEXT OF WS-PUT-OPTIONS
           CALL 'MQPUT1' USING WS-HCONN
                               WS-TARGET-OD
                               WS-REPLY-MD
                               WS-PUT-OPTIONS
                               WS-RESPONSE-BUFFER-LENGTH
                               WS-RESPONSE
                               WS-COMPCODE
                               WS-REASON
           END-CALL
           IF WS-COMPCODE = MQCC-OK
               SET WS-REPLY-SENT TO TRUE
           ELSE
               MOVE WS-EVENT-REPLY-FAILED TO WS-LOG-EVENT
               MOVE WS-REASON             TO WS-LOG-REASON
               PERFORM 8000-WRITE-LOG
           END-IF
           .

      *    REPORT IS A BIT MASK; MQRO_PASS_CORREL_ID IS A POWER OF TWO.
       7010-SET-REPLY-CORRELATION.
           COMPUTE WS-REPORT-QUOTIENT =
                   MQMD-REPORT OF WS-REQUEST-MD / MQRO-PASS-CORREL-ID
           END-COMPUTE
           IF FUNCTION MOD(WS-REPORT-QUOTIENT 2) = 1
               MOVE MQMD-CORRELID OF WS-REQUEST-MD
                 TO MQMD-CORRELID OF WS-REPLY-MD
           ELSE
               MOVE MQMD-MSGID    OF WS-REQUEST-MD
                 TO MQMD-CORRELID OF WS-REPLY-MD
           END-IF
           .

      *    RESPONSES PRODUCED BY THE ADAPTER ITSELF (WS-RESPONSE-CODE).
       7100-BUILD-ADAPTER-RESPONSE.
           MOVE WS-THIS-PROGRAM  TO RCT-PROGRAM-ID
           MOVE WS-RESPONSE-CODE TO RCT-RESPONSE-CODE
           MOVE WS-TECH-CODE     TO RCT-TECH-CODE
           SET RCT-FN-INIT TO TRUE
           PERFORM 7110-CALL-RESPONSE-BUILDER
           SET RCT-FN-FINISH TO TRUE
           PERFORM 7110-CALL-RESPONSE-BUILDER
           .

       7110-CALL-RESPONSE-BUILDER.
           CALL WS-PGM-RESPONSE-BUILDER USING WS-RESPONSE-CONTROL
                                              WS-REQUEST
                                              WS-RESPONSE
               ON EXCEPTION
                   MOVE SPACES TO WS-RESPONSE
           END-CALL
           .

      *================================================================*
      * 8000 - TECHNICAL LOG (NO PAYLOAD). A LOGGING FAILURE NEVER     *
      * CHANGES THE OUTCOME OF THE MESSAGE.                            *
      *================================================================*
       8000-WRITE-LOG.
           MOVE WS-THIS-PROGRAM    TO WS-LOG-PROGRAM
           MOVE EIBTRNID           TO WS-LOG-TRANSACTION
           MOVE REQ-CORRELATION-ID TO WS-LOG-CORRELATION
           MOVE LENGTH OF WS-LOG-RECORD TO WS-LOG-LENGTH
           EXEC CICS WRITEQ TD
               QUEUE(WS-LOG-TDQ)
               FROM(WS-LOG-RECORD)
               LENGTH(WS-LOG-LENGTH)
               RESP(WS-LOG-RESP)
           END-EXEC
           MOVE SPACES TO WS-LOG-EVENT
                          WS-LOG-TECH
           MOVE ZERO   TO WS-LOG-REASON
           .

      *================================================================*
       9000-FINALIZE.
           IF WS-QUEUE-OPEN
               MOVE MQCO-NONE TO WS-CLOSE-OPTIONS
               CALL 'MQCLOSE' USING WS-HCONN
                                    WS-HOBJ
                                    WS-CLOSE-OPTIONS
                                    WS-COMPCODE
                                    WS-REASON
               END-CALL
               SET WS-QUEUE-CLOSED TO TRUE
               IF WS-COMPCODE NOT = MQCC-OK
                   MOVE WS-EVENT-CLOSE-FAILED TO WS-LOG-EVENT
                   MOVE WS-REASON             TO WS-LOG-REASON
                   PERFORM 8000-WRITE-LOG
               END-IF
           END-IF
           .
