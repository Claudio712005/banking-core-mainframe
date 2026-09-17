       IDENTIFICATION DIVISION.
       PROGRAM-ID. BKMQLSN.
      *================================================================*
      * PROGRAM  : BKMQLSN                                             *
      * TYPE     : BATCH MAIN PROGRAM (IBM MQ CLIENT LISTENER)         *
      * TARGET   : LAB - GNUCOBOL 3.2 + IBM MQ C CLIENT (LIBMQICB),    *
      *            LINUX X86-64. SEE MAINFRAME-BANKING/DOCKERFILE.     *
      * PURPOSE  : LOCAL COUNTERPART OF THE CICS ADAPTER BKMQADP.      *
      *            SERVES THE FOUR BANKCORE REQUEST QUEUES FROM ONE    *
      *            PROCESS, CALLS THE ENTRY PROGRAMS AND REPLIES,      *
      *            ONE MQ UNIT OF WORK PER MESSAGE (MQCMIT / MQBACK).  *
      *----------------------------------------------------------------*
      * WHY ONE PROCESS FOR ALL QUEUES                                 *
      *   THE LAB DATA ACCESS MODULES ARE SINGLE-WRITER. THE QUEUES    *
      *   ARE POLLED IN TURN WITH A SHORT WAIT EACH                    *
      *   (BK_POLL_WAIT_MS), SO POSTINGS NEVER RUN CONCURRENTLY.       *
      *----------------------------------------------------------------*
      * CONSISTENCY WITHOUT A TRANSACTION MANAGER                      *
      *   FILES ARE UPDATED BEFORE MQCMIT. IF THE PROCESS DIES IN      *
      *   BETWEEN, MQ REDELIVERS THE MESSAGE AND ACCTPOST ANSWERS 0001 *
      *   WITH THE ORIGINAL RESULT (IDEMPOTENCY KEY IN THE JOURNAL).   *
      *----------------------------------------------------------------*
      * MESSAGE DISPOSITION: IDENTICAL TO BKMQADP.                     *
      *----------------------------------------------------------------*
      * ENVIRONMENT                                                    *
      *   MQSERVER          CHANNEL/TCP/HOST(PORT)   (READ BY MQ)      *
      *   MQ_QUEUE_MANAGER  QUEUE MANAGER NAME                         *
      *   MQ_USERNAME       CONNECTION USER                            *
      *   MQ_PASSWORD       CONNECTION PASSWORD (NEVER LOGGED)         *
      *   BK_ACCTINQ_QUEUE  BK_ACCTDEP_QUEUE                           *
      *   BK_ACCTWDR_QUEUE  BK_TRXINQ_QUEUE     REQUEST QUEUE NAMES    *
      *   BK_POLL_WAIT_MS   WAIT PER QUEUE, 1..60000 (DEFAULT 250)     *
      *----------------------------------------------------------------*
      * EXIT     : RC 12 WHEN THE CONNECTION CANNOT BE ESTABLISHED OR  *
      *            IS LOST. THE CONTAINER RESTART POLICY RECONNECTS;   *
      *            UNCOMMITTED WORK IS BACKED OUT BY THE QUEUE MANAGER.*
      * BUILD    : -STD=IBM -FNOTRUNC -FSTATIC-CALL, LINK -LMQICB.     *
      *            BINARY STAYS BIG-ENDIAN, AS EXPECTED BY LIBMQICB.   *
      *================================================================*
       ENVIRONMENT DIVISION.
       CONFIGURATION SECTION.
       SPECIAL-NAMES.
           CLASS BK-LOG-SAFE-CHAR IS 'A' THRU 'I'
                                     'J' THRU 'R'
                                     'S' THRU 'Z'
                                     'a' THRU 'i'
                                     'j' THRU 'r'
                                     's' THRU 'z'
                                     '0' THRU '9'
                                     '-' ' '.

       DATA DIVISION.
       WORKING-STORAGE SECTION.
       01  WS-PROGRAM-NAMES.
           05  WS-THIS-PROGRAM              PIC X(08) VALUE 'BKMQLSN'.
           05  WS-PGM-RESPONSE-BUILDER      PIC X(08) VALUE 'BKRESP'.

       01  WS-CONSTANTS.
           05  WS-REQUEST-BUFFER-LENGTH     PIC S9(09) BINARY
                                            VALUE +200.
           05  WS-RESPONSE-BUFFER-LENGTH    PIC S9(09) BINARY
                                            VALUE +300.
           05  WS-DEFAULT-POLL-WAIT-MS      PIC S9(09) BINARY
                                            VALUE +250.
           05  WS-MAX-POLL-WAIT-MS          PIC S9(09) BINARY
                                            VALUE +60000.
           05  WS-EXIT-CODE-FAILURE         PIC S9(04) BINARY
                                            VALUE +12.
           05  WS-APPLICATION-NAME          PIC X(28)
                                            VALUE 'BKMQLSN'.
           05  WS-REASON-BACKOUT            PIC X(08) VALUE 'BACKOUT'.
           05  WS-REASON-NO-REPLY-TO        PIC X(08) VALUE 'NOREPLY'.
           05  WS-REASON-FORMAT             PIC X(08) VALUE 'FORMAT'.
           05  WS-REASON-LENGTH             PIC X(08) VALUE 'LENGTH'.
           05  WS-REASON-WRONG-OPERATION    PIC X(08) VALUE 'WRONGOP'.
           05  WS-REASON-MODULE-MISSING     PIC X(08) VALUE 'NOMODULE'.
           05  WS-UNSAFE-VALUE              PIC X(08) VALUE 'INVALID'.

       01  WS-ENVIRONMENT-NAMES.
           05  WS-ENV-QUEUE-MANAGER         PIC X(16)
                                            VALUE 'MQ_QUEUE_MANAGER'.
           05  WS-ENV-USERNAME              PIC X(16)
                                            VALUE 'MQ_USERNAME'.
           05  WS-ENV-PASSWORD              PIC X(16)
                                            VALUE 'MQ_PASSWORD'.
           05  WS-ENV-POLL-WAIT             PIC X(16)
                                            VALUE 'BK_POLL_WAIT_MS'.

       01  WS-LOG-EVENTS.
           05  WS-EVENT-STARTED             PIC X(16)
                                            VALUE 'LISTENER STARTED'.
           05  WS-EVENT-STOPPED             PIC X(16)
                                            VALUE 'LISTENER STOPPED'.
           05  WS-EVENT-CONFIG-INVALID      PIC X(16)
                                            VALUE 'CONFIG INVALID'.
           05  WS-EVENT-CONNECT-FAILED      PIC X(16)
                                            VALUE 'MQCONNX FAILED'.
           05  WS-EVENT-OPEN-FAILED         PIC X(16)
                                            VALUE 'MQOPEN FAILED'.
           05  WS-EVENT-INQUIRE-FAILED      PIC X(16)
                                            VALUE 'MQINQ FAILED'.
           05  WS-EVENT-NO-BACKOUT-POLICY   PIC X(16)
                                            VALUE 'NO BACKOUT QUEUE'.
           05  WS-EVENT-GET-FAILED          PIC X(16)
                                            VALUE 'MQGET FAILED'.
           05  WS-EVENT-PROCESSED           PIC X(16)
                                            VALUE 'MSG PROCESSED'.
           05  WS-EVENT-BACKED-OUT          PIC X(16)
                                            VALUE 'MSG BACKED OUT'.
           05  WS-EVENT-REJECTED            PIC X(16)
                                            VALUE 'MSG REJECTED'.
           05  WS-EVENT-DIVERTED            PIC X(16)
                                            VALUE 'MSG DIVERTED'.
           05  WS-EVENT-DIVERT-FAILED       PIC X(16)
                                            VALUE 'DIVERT FAILED'.
           05  WS-EVENT-REPLY-FAILED        PIC X(16)
                                            VALUE 'REPLY FAILED'.
           05  WS-EVENT-COMMIT-FAILED       PIC X(16)
                                            VALUE 'MQCMIT FAILED'.
           05  WS-EVENT-BACKOUT-FAILED      PIC X(16)
                                            VALUE 'MQBACK FAILED'.
           05  WS-EVENT-CLOSE-FAILED        PIC X(16)
                                            VALUE 'MQCLOSE FAILED'.

      *----------------------------------------------------------------*
      * SERVED QUEUES. OPERATION AND PROGRAM ARE FIXED (WHITELIST);    *
      * ONLY THE QUEUE NAME CAN BE OVERRIDDEN BY THE ENVIRONMENT.      *
      *----------------------------------------------------------------*
       01  WS-QUEUE-DEFINITIONS.
           05  FILLER PIC X(08) VALUE 'ACCTINQ '.
           05  FILLER PIC X(08) VALUE 'ACCTINQ '.
           05  FILLER PIC X(16) VALUE 'BK_ACCTINQ_QUEUE'.
           05  FILLER PIC X(48) VALUE 'BANKCORE.ACCTINQ.REQUEST'.
           05  FILLER PIC X(08) VALUE 'ACCTDEP '.
           05  FILLER PIC X(08) VALUE 'ACCTDEP '.
           05  FILLER PIC X(16) VALUE 'BK_ACCTDEP_QUEUE'.
           05  FILLER PIC X(48) VALUE 'BANKCORE.ACCTDEP.REQUEST'.
           05  FILLER PIC X(08) VALUE 'ACCTWDR '.
           05  FILLER PIC X(08) VALUE 'ACCTWDR '.
           05  FILLER PIC X(16) VALUE 'BK_ACCTWDR_QUEUE'.
           05  FILLER PIC X(48) VALUE 'BANKCORE.ACCTWDR.REQUEST'.
           05  FILLER PIC X(08) VALUE 'TRXINQ  '.
           05  FILLER PIC X(08) VALUE 'TRXINQ  '.
           05  FILLER PIC X(16) VALUE 'BK_TRXINQ_QUEUE '.
           05  FILLER PIC X(48) VALUE 'BANKCORE.TRXINQ.REQUEST'.
       01  WS-QUEUE-DEFINITION-TABLE REDEFINES WS-QUEUE-DEFINITIONS.
           05  WS-QUEUE-DEFINITION OCCURS 4 TIMES.
               10  QD-OPERATION             PIC X(08).
               10  QD-PROGRAM               PIC X(08).
               10  QD-ENVIRONMENT-NAME      PIC X(16).
               10  QD-DEFAULT-QUEUE         PIC X(48).

       01  WS-QUEUE-COUNT                   PIC S9(04) BINARY
                                            VALUE +4.
       01  WS-QX                            PIC S9(04) BINARY.

       01  WS-QUEUE-TABLE.
           05  WS-QUEUE-ENTRY OCCURS 4 TIMES.
               10  QT-QUEUE-NAME            PIC X(48).
               10  QT-HOBJ                  PIC S9(09) BINARY.
               10  QT-OPEN-FLAG             PIC X(01).
                   88  QT-OPEN                       VALUE 'Y'.
                   88  QT-CLOSED                     VALUE 'N'.
               10  QT-BACKOUT-THRESHOLD     PIC S9(09) BINARY.
               10  QT-BACKOUT-QUEUE         PIC X(48).

       01  WS-CONTROL-FLAGS.
           05  WS-PROCESSING-FLAG           PIC X(01).
               88  WS-CONTINUE-PROCESSING            VALUE 'Y'.
               88  WS-STOP-PROCESSING                VALUE 'N'.
           05  WS-CONNECTION-FLAG           PIC X(01).
               88  WS-CONNECTED                      VALUE 'Y'.
               88  WS-NOT-CONNECTED                  VALUE 'N'.
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

       01  WS-MQ-USER                       PIC X(64).
       01  WS-MQ-PASSWORD                   PIC X(256).
       01  WS-SECRET-LENGTH                 PIC S9(09) BINARY.

       01  WS-CONFIGURATION.
           05  WS-QUEUE-MANAGER             PIC X(48).
           05  WS-POLL-WAIT-TEXT            PIC X(09).
           05  WS-POLL-WAIT-MS              PIC S9(09) BINARY.
           05  WS-ENVIRONMENT-VALUE         PIC X(48).

       01  WS-MQ-CALL-AREAS.
           05  WS-HCONN                     PIC S9(09) BINARY.
           05  WS-OPEN-OPTIONS              PIC S9(09) BINARY.
           05  WS-CLOSE-OPTIONS             PIC S9(09) BINARY.
           05  WS-COMPCODE                  PIC S9(09) BINARY.
           05  WS-REASON                    PIC S9(09) BINARY.
           05  WS-GET-COMPCODE              PIC S9(09) BINARY.
           05  WS-GET-REASON                PIC S9(09) BINARY.
           05  WS-DATA-LENGTH               PIC S9(09) BINARY.
           05  WS-DIVERT-LENGTH             PIC S9(09) BINARY.
           05  WS-REPORT-QUOTIENT           PIC S9(09) BINARY.

       01  WS-BACKOUT-INQUIRY.
           05  WS-SELECTOR-COUNT            PIC S9(09) BINARY
                                            VALUE +2.
           05  WS-SELECTORS.
               10  WS-SELECTOR              PIC S9(09) BINARY
                                            OCCURS 2 TIMES.
           05  WS-INT-ATTR-COUNT            PIC S9(09) BINARY
                                            VALUE +1.
           05  WS-INQ-BACKOUT-THRESHOLD     PIC S9(09) BINARY.
           05  WS-CHAR-ATTR-LENGTH          PIC S9(09) BINARY
                                            VALUE +48.
           05  WS-INQ-BACKOUT-QUEUE         PIC X(48).

       01  WS-TECH-CODE                     PIC X(08).

       01  WS-LOG-RECORD.
           05  WS-LOG-PROGRAM               PIC X(08).
           05  FILLER                       PIC X(01) VALUE SPACE.
           05  WS-LOG-EVENT                 PIC X(16).
           05  FILLER                       PIC X(07) VALUE ' QUEUE='.
           05  WS-LOG-QUEUE                 PIC X(24).
           05  FILLER                       PIC X(04) VALUE ' RC='.
           05  WS-LOG-RESPONSE-CODE         PIC X(04).
           05  FILLER                       PIC X(08) VALUE ' REASON='.
           05  WS-LOG-REASON                PIC 9(09).
           05  FILLER                       PIC X(06) VALUE ' TECH='.
           05  WS-LOG-TECH                  PIC X(08).
           05  FILLER                       PIC X(06) VALUE ' CORR='.
           05  WS-LOG-CORRELATION           PIC X(36).

      *    IBM MQ DEFINITIONS (REDISTRIBUTABLE CLIENT, INC/COBCPY64)
       01  MQM-CONSTANTS.
           COPY CMQV.
       01  WS-CONNECT-OPTIONS.
           COPY CMQCNOV.
       01  WS-SECURITY-PARMS.
           COPY CMQCSPV.
       01  WS-DEFAULT-OD.
           COPY CMQODV.
       01  WS-QUEUE-OD.
           COPY CMQODV.
       01  WS-TARGET-OD.
           COPY CMQODV.
       01  WS-DEFAULT-MD.
           COPY CMQMDV.
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
           PERFORM 2000-POLL-QUEUES
               UNTIL WS-STOP-PROCESSING
           PERFORM 9000-FINALIZE
           MOVE WS-EXIT-CODE-FAILURE TO RETURN-CODE
           STOP RUN
           .

      *================================================================*
      * 1000 - CONFIGURATION, CONNECTION, QUEUES, BACKOUT POLICY       *
      *================================================================*
       1000-INITIALIZE.
           SET WS-CONTINUE-PROCESSING TO TRUE
           SET WS-NOT-CONNECTED       TO TRUE
           MOVE SPACES TO WS-REQUEST
                          WS-RESPONSE
                          WS-TECH-CODE
           INITIALIZE WS-RESPONSE-CONTROL
           PERFORM 8900-CLEAR-LOG-FIELDS
           MOVE MQHC-UNUSABLE-HCONN TO WS-HCONN
           PERFORM VARYING WS-QX FROM 1 BY 1
                   UNTIL WS-QX > WS-QUEUE-COUNT
               SET QT-CLOSED(WS-QX) TO TRUE
               MOVE MQHO-UNUSABLE-HOBJ TO QT-HOBJ(WS-QX)
           END-PERFORM
           PERFORM 1100-READ-CONFIGURATION
           IF WS-CONTINUE-PROCESSING
               PERFORM 1200-CONNECT
           END-IF
           PERFORM VARYING WS-QX FROM 1 BY 1
                   UNTIL WS-QX > WS-QUEUE-COUNT
                      OR WS-STOP-PROCESSING
               PERFORM 1300-OPEN-REQUEST-QUEUE
               IF WS-CONTINUE-PROCESSING
                   PERFORM 1400-READ-BACKOUT-POLICY
               END-IF
           END-PERFORM
           IF WS-CONTINUE-PROCESSING
               MOVE WS-EVENT-STARTED TO WS-LOG-EVENT
               MOVE WS-POLL-WAIT-MS  TO WS-LOG-REASON
               PERFORM 8000-WRITE-LOG
           END-IF
           .

       1100-READ-CONFIGURATION.
           MOVE SPACES TO WS-QUEUE-MANAGER
                          WS-MQ-USER
                          WS-MQ-PASSWORD
                          WS-POLL-WAIT-TEXT
           ACCEPT WS-QUEUE-MANAGER FROM ENVIRONMENT WS-ENV-QUEUE-MANAGER
           ACCEPT WS-MQ-USER       FROM ENVIRONMENT WS-ENV-USERNAME
           ACCEPT WS-MQ-PASSWORD   FROM ENVIRONMENT WS-ENV-PASSWORD
           ACCEPT WS-POLL-WAIT-TEXT FROM ENVIRONMENT WS-ENV-POLL-WAIT
           PERFORM 1110-RESOLVE-POLL-WAIT
           PERFORM VARYING WS-QX FROM 1 BY 1
                   UNTIL WS-QX > WS-QUEUE-COUNT
               MOVE SPACES TO WS-ENVIRONMENT-VALUE
               ACCEPT WS-ENVIRONMENT-VALUE
                   FROM ENVIRONMENT QD-ENVIRONMENT-NAME(WS-QX)
               IF WS-ENVIRONMENT-VALUE = SPACES
                   MOVE QD-DEFAULT-QUEUE(WS-QX) TO QT-QUEUE-NAME(WS-QX)
               ELSE
                   MOVE WS-ENVIRONMENT-VALUE TO QT-QUEUE-NAME(WS-QX)
               END-IF
           END-PERFORM
           IF WS-QUEUE-MANAGER = SPACES
              OR WS-MQ-USER = SPACES
               MOVE WS-EVENT-CONFIG-INVALID TO WS-LOG-EVENT
               PERFORM 8000-WRITE-LOG
               SET WS-STOP-PROCESSING TO TRUE
           END-IF
           .

       1110-RESOLVE-POLL-WAIT.
           EVALUATE TRUE
               WHEN WS-POLL-WAIT-TEXT = SPACES
                   MOVE WS-DEFAULT-POLL-WAIT-MS TO WS-POLL-WAIT-MS
               WHEN FUNCTION TEST-NUMVAL(WS-POLL-WAIT-TEXT) NOT = ZERO
                   MOVE WS-DEFAULT-POLL-WAIT-MS TO WS-POLL-WAIT-MS
               WHEN OTHER
                   COMPUTE WS-POLL-WAIT-MS =
                           FUNCTION NUMVAL(WS-POLL-WAIT-TEXT)
                   END-COMPUTE
                   IF WS-POLL-WAIT-MS < 1
                      OR WS-POLL-WAIT-MS > WS-MAX-POLL-WAIT-MS
                       MOVE WS-DEFAULT-POLL-WAIT-MS TO WS-POLL-WAIT-MS
                   END-IF
           END-EVALUATE
           .

      *    CLIENT CONNECTION WITH USER/PASSWORD (MQCSP). THE CHANNEL
      *    AND HOST COME FROM MQSERVER, READ BY THE MQ CLIENT ITSELF.
       1200-CONNECT.
           MOVE MQCNO-VERSION-7 TO MQCNO-VERSION
           MOVE WS-APPLICATION-NAME TO MQCNO-APPLNAME
           SET MQCNO-SECURITYPARMSPTR TO ADDRESS OF WS-SECURITY-PARMS
           MOVE MQCSP-AUTH-USER-ID-AND-PWD TO MQCSP-AUTHENTICATIONTYPE
           SET MQCSP-CSPUSERIDPTR TO ADDRESS OF WS-MQ-USER
           MOVE ZERO TO WS-SECRET-LENGTH
           INSPECT FUNCTION REVERSE(WS-MQ-USER)
               TALLYING WS-SECRET-LENGTH FOR LEADING SPACES
           COMPUTE MQCSP-CSPUSERIDLENGTH =
                   LENGTH OF WS-MQ-USER - WS-SECRET-LENGTH
           END-COMPUTE
           SET MQCSP-CSPPASSWORDPTR TO ADDRESS OF WS-MQ-PASSWORD
           MOVE ZERO TO WS-SECRET-LENGTH
           INSPECT FUNCTION REVERSE(WS-MQ-PASSWORD)
               TALLYING WS-SECRET-LENGTH FOR LEADING SPACES
           COMPUTE MQCSP-CSPPASSWORDLENGTH =
                   LENGTH OF WS-MQ-PASSWORD - WS-SECRET-LENGTH
           END-COMPUTE
           CALL 'MQCONNX' USING WS-QUEUE-MANAGER
                                WS-CONNECT-OPTIONS
                                WS-HCONN
                                WS-COMPCODE
                                WS-REASON
           END-CALL
           MOVE SPACES TO WS-MQ-PASSWORD
           IF WS-COMPCODE = MQCC-FAILED
               MOVE WS-EVENT-CONNECT-FAILED TO WS-LOG-EVENT
               MOVE WS-REASON               TO WS-LOG-REASON
               PERFORM 8000-WRITE-LOG
               SET WS-STOP-PROCESSING TO TRUE
           ELSE
               SET WS-CONNECTED TO TRUE
           END-IF
           .

      *    SAVE-ALL-CONTEXT KEEPS THE ORIGINAL IDENTITY FOR MESSAGES
      *    MOVED TO THE BACKOUT QUEUE.
       1300-OPEN-REQUEST-QUEUE.
           MOVE WS-DEFAULT-OD TO WS-QUEUE-OD
           MOVE QT-QUEUE-NAME(WS-QX) TO MQOD-OBJECTNAME OF WS-QUEUE-OD
           COMPUTE WS-OPEN-OPTIONS = MQOO-INPUT-SHARED
                                   + MQOO-INQUIRE
                                   + MQOO-SAVE-ALL-CONTEXT
                                   + MQOO-FAIL-IF-QUIESCING
           END-COMPUTE
           CALL 'MQOPEN' USING WS-HCONN
                               WS-QUEUE-OD
                               WS-OPEN-OPTIONS
                               QT-HOBJ(WS-QX)
                               WS-COMPCODE
                               WS-REASON
           END-CALL
           IF WS-COMPCODE = MQCC-OK
               SET QT-OPEN(WS-QX) TO TRUE
           ELSE
               MOVE WS-EVENT-OPEN-FAILED TO WS-LOG-EVENT
               MOVE WS-REASON            TO WS-LOG-REASON
               PERFORM 8000-WRITE-LOG
               SET WS-STOP-PROCESSING TO TRUE
           END-IF
           .

      *    FAIL-SAFE: WITHOUT A BACKOUT POLICY A FAILING MESSAGE WOULD
      *    BE REDELIVERED FOREVER, SO THE LISTENER REFUSES TO START.
       1400-READ-BACKOUT-POLICY.
           MOVE MQIA-BACKOUT-THRESHOLD  TO WS-SELECTOR(1)
           MOVE MQCA-BACKOUT-REQ-Q-NAME TO WS-SELECTOR(2)
           CALL 'MQINQ' USING WS-HCONN
                              QT-HOBJ(WS-QX)
                              WS-SELECTOR-COUNT
                              WS-SELECTORS
                              WS-INT-ATTR-COUNT
                              WS-INQ-BACKOUT-THRESHOLD
                              WS-CHAR-ATTR-LENGTH
                              WS-INQ-BACKOUT-QUEUE
                              WS-COMPCODE
                              WS-REASON
           END-CALL
           EVALUATE TRUE
               WHEN WS-COMPCODE NOT = MQCC-OK
                   MOVE WS-EVENT-INQUIRE-FAILED TO WS-LOG-EVENT
                   MOVE WS-REASON               TO WS-LOG-REASON
                   PERFORM 8000-WRITE-LOG
                   SET WS-STOP-PROCESSING TO TRUE
               WHEN WS-INQ-BACKOUT-THRESHOLD NOT > ZERO
               WHEN WS-INQ-BACKOUT-QUEUE = SPACES
                   MOVE WS-EVENT-NO-BACKOUT-POLICY TO WS-LOG-EVENT
                   PERFORM 8000-WRITE-LOG
                   SET WS-STOP-PROCESSING TO TRUE
               WHEN OTHER
                   MOVE WS-INQ-BACKOUT-THRESHOLD
                     TO QT-BACKOUT-THRESHOLD(WS-QX)
                   MOVE WS-INQ-BACKOUT-QUEUE
                     TO QT-BACKOUT-QUEUE(WS-QX)
           END-EVALUATE
           .

      *================================================================*
      * 2000 - ONE POLLING CYCLE OVER ALL QUEUES                       *
      * EACH MESSAGE IS ONE UNIT OF WORK. THE OUTCOME STARTS AS        *
      * ROLLBACK AND BECOMES COMMIT ONLY WHEN FULLY HANDLED.           *
      *================================================================*
       2000-POLL-QUEUES.
           PERFORM VARYING WS-QX FROM 1 BY 1
                   UNTIL WS-QX > WS-QUEUE-COUNT
                      OR WS-STOP-PROCESSING
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
           END-PERFORM
           .

      *    MSGID/CORRELID/ENCODING/CCSID ARE RESET BEFORE EVERY GET.
      *    TRUNCATED MESSAGES ARE ACCEPTED (AND REJECTED LATER) SO AN
      *    OVERSIZED MESSAGE CANNOT BLOCK THE QUEUE.
       2100-GET-MESSAGE.
           SET WS-NO-MESSAGE TO TRUE
           MOVE SPACES        TO WS-REQUEST
                                 WS-RESPONSE
           MOVE WS-DEFAULT-MD TO WS-REQUEST-MD
           COMPUTE MQGMO-OPTIONS OF WS-GET-OPTIONS =
                   MQGMO-SYNCPOINT
                 + MQGMO-WAIT
                 + MQGMO-CONVERT
                 + MQGMO-ACCEPT-TRUNCATED-MSG
                 + MQGMO-FAIL-IF-QUIESCING
           END-COMPUTE
           MOVE WS-POLL-WAIT-MS TO MQGMO-WAITINTERVAL OF WS-GET-OPTIONS
           CALL 'MQGET' USING WS-HCONN
                              QT-HOBJ(WS-QX)
                              WS-REQUEST-MD
                              WS-GET-OPTIONS
                              WS-REQUEST-BUFFER-LENGTH
                              WS-REQUEST
                              WS-DATA-LENGTH
                              WS-GET-COMPCODE
                              WS-GET-REASON
           END-CALL
           EVALUATE TRUE
               WHEN WS-GET-COMPCODE = MQCC-OK
               WHEN WS-GET-COMPCODE = MQCC-WARNING
                   SET WS-MESSAGE-RECEIVED TO TRUE
               WHEN WS-GET-REASON = MQRC-NO-MSG-AVAILABLE
                   CONTINUE
               WHEN OTHER
                   MOVE WS-EVENT-GET-FAILED TO WS-LOG-EVENT
                   MOVE WS-GET-REASON       TO WS-LOG-REASON
                   PERFORM 8000-WRITE-LOG
                   SET WS-STOP-PROCESSING TO TRUE
           END-EVALUATE
           .

      *    ORDER MATTERS: A POISON MESSAGE IS DIVERTED BEFORE ANY OTHER
      *    CHECK. A FORMAT OTHER THAN MQSTR (E.G. A JMS RFH2 HEADER) OR
      *    A FAILED CONVERSION MEANS THE BYTES CANNOT BE TRUSTED: THE
      *    REQUEST AREA IS CLEARED SO NOTHING OF IT IS ECHOED.
       2200-CLASSIFY-MESSAGE.
           EVALUATE TRUE
               WHEN MQMD-BACKOUTCOUNT OF WS-REQUEST-MD
                    >= QT-BACKOUT-THRESHOLD(WS-QX)
                   SET WS-ACTION-DIVERT TO TRUE
                   MOVE WS-REASON-BACKOUT TO WS-TECH-CODE
               WHEN MQMD-MSGTYPE OF WS-REQUEST-MD NOT = MQMT-REQUEST
               WHEN MQMD-REPLYTOQ OF WS-REQUEST-MD = SPACES
                   SET WS-ACTION-DIVERT TO TRUE
                   MOVE WS-REASON-NO-REPLY-TO TO WS-TECH-CODE
               WHEN MQMD-FORMAT OF WS-REQUEST-MD NOT = MQFMT-STRING
               WHEN WS-GET-COMPCODE = MQCC-WARNING
                AND WS-GET-REASON NOT = MQRC-TRUNCATED-MSG-ACCEPTED
                   SET WS-ACTION-REJECT TO TRUE
                   MOVE WS-REASON-FORMAT TO WS-TECH-CODE
                   MOVE SPACES TO WS-REQUEST
               WHEN WS-DATA-LENGTH NOT = WS-REQUEST-BUFFER-LENGTH
                   SET WS-ACTION-REJECT TO TRUE
                   MOVE WS-REASON-LENGTH TO WS-TECH-CODE
               WHEN REQ-OPERATION-CODE NOT = QD-OPERATION(WS-QX)
                   SET WS-ACTION-REJECT TO TRUE
                   MOVE WS-REASON-WRONG-OPERATION TO WS-TECH-CODE
               WHEN OTHER
                   SET WS-ACTION-PROCESS TO TRUE
           END-EVALUATE
           .

      *================================================================*
      * 3000 - POISON / UNANSWERABLE MESSAGES -> BACKOUT QUEUE         *
      * A FAILED 9004 REPLY DOES NOT UNDO THE DIVERSION, OTHERWISE THE *
      * MESSAGE WOULD LOOP.                                            *
      *================================================================*
       3000-DIVERT-TO-BACKOUT-QUEUE.
           MOVE WS-DEFAULT-OD TO WS-TARGET-OD
           MOVE QT-BACKOUT-QUEUE(WS-QX)
             TO MQOD-OBJECTNAME OF WS-TARGET-OD
           COMPUTE MQPMO-OPTIONS OF WS-PUT-OPTIONS =
                   MQPMO-SYNCPOINT
                 + MQPMO-PASS-ALL-CONTEXT
                 + MQPMO-FAIL-IF-QUIESCING
           END-COMPUTE
           MOVE QT-HOBJ(WS-QX) TO MQPMO-CONTEXT OF WS-PUT-OPTIONS
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
               MOVE WS-EVENT-DIVERTED TO WS-LOG-EVENT
               MOVE WS-TECH-CODE      TO WS-LOG-TECH
               PERFORM 8000-WRITE-LOG
               SET WS-UOW-COMMIT TO TRUE
               IF WS-TECH-CODE = WS-REASON-BACKOUT
                  AND MQMD-REPLYTOQ OF WS-REQUEST-MD NOT = SPACES
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
           MOVE WS-GET-REASON     TO WS-LOG-REASON
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
      * AND TECHNICAL FAILURES BACK OUT THE GET SO MQ REDELIVERS.      *
      *================================================================*
       5000-PROCESS-REQUEST.
           MOVE SPACES TO WS-RESPONSE
           CALL QD-PROGRAM(WS-QX) USING WS-REQUEST
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
                       MOVE WS-EVENT-PROCESSED TO WS-LOG-EVENT
                       PERFORM 8000-WRITE-LOG
                   END-IF
               WHEN OTHER
                   SET WS-UOW-ROLLBACK TO TRUE
                   MOVE WS-EVENT-BACKED-OUT TO WS-LOG-EVENT
                   PERFORM 8000-WRITE-LOG
           END-EVALUATE
           .

      *================================================================*
      * 6000 - COMMIT OR BACK OUT THE GET AND THE REPLY TOGETHER       *
      *================================================================*
       6000-END-UNIT-OF-WORK.
           IF WS-UOW-COMMIT
               CALL 'MQCMIT' USING WS-HCONN
                                   WS-COMPCODE
                                   WS-REASON
               END-CALL
               IF WS-COMPCODE NOT = MQCC-OK
                   MOVE WS-EVENT-COMMIT-FAILED TO WS-LOG-EVENT
                   MOVE WS-REASON              TO WS-LOG-REASON
                   PERFORM 8000-WRITE-LOG
                   SET WS-STOP-PROCESSING TO TRUE
               END-IF
           ELSE
               CALL 'MQBACK' USING WS-HCONN
                                   WS-COMPCODE
                                   WS-REASON
               END-CALL
               IF WS-COMPCODE NOT = MQCC-OK
                   MOVE WS-EVENT-BACKOUT-FAILED TO WS-LOG-EVENT
                   MOVE WS-REASON               TO WS-LOG-REASON
                   PERFORM 8000-WRITE-LOG
                   SET WS-STOP-PROCESSING TO TRUE
               END-IF
           END-IF
           .

      *================================================================*
      * 7000 - REPLY (SAME RULES AS BKMQADP)                           *
      * CORRELID = REQUEST MSGID, OR REQUEST CORRELID WHEN THE         *
      * REQUESTER ASKED FOR MQRO_PASS_CORREL_ID. PERSISTENCE, PRIORITY *
      * AND REMAINING EXPIRY ARE INHERITED FROM THE REQUEST.           *
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
      * 8000 - LOG (STDOUT). NO PAYLOAD, ACCOUNT OR AMOUNT IS LOGGED.  *
      *================================================================*
       8000-WRITE-LOG.
           MOVE WS-THIS-PROGRAM TO WS-LOG-PROGRAM
           IF WS-QX >= 1 AND WS-QX <= WS-QUEUE-COUNT
               MOVE QT-QUEUE-NAME(WS-QX) TO WS-LOG-QUEUE
           END-IF
           MOVE RSP-RESPONSE-CODE  TO WS-LOG-RESPONSE-CODE
           IF REQ-CORRELATION-ID IS BK-LOG-SAFE-CHAR
               MOVE REQ-CORRELATION-ID TO WS-LOG-CORRELATION
           ELSE
               MOVE WS-UNSAFE-VALUE    TO WS-LOG-CORRELATION
           END-IF
           DISPLAY WS-LOG-RECORD
           PERFORM 8900-CLEAR-LOG-FIELDS
           .

       8900-CLEAR-LOG-FIELDS.
           MOVE SPACES TO WS-LOG-EVENT
                          WS-LOG-QUEUE
                          WS-LOG-RESPONSE-CODE
                          WS-LOG-TECH
                          WS-LOG-CORRELATION
           MOVE ZERO   TO WS-LOG-REASON
           .

      *================================================================*
       9000-FINALIZE.
           PERFORM VARYING WS-QX FROM 1 BY 1
                   UNTIL WS-QX > WS-QUEUE-COUNT
               IF QT-OPEN(WS-QX)
                   MOVE MQCO-NONE TO WS-CLOSE-OPTIONS
                   CALL 'MQCLOSE' USING WS-HCONN
                                        QT-HOBJ(WS-QX)
                                        WS-CLOSE-OPTIONS
                                        WS-COMPCODE
                                        WS-REASON
                   END-CALL
                   SET QT-CLOSED(WS-QX) TO TRUE
                   IF WS-COMPCODE NOT = MQCC-OK
                       MOVE WS-EVENT-CLOSE-FAILED TO WS-LOG-EVENT
                       MOVE WS-REASON             TO WS-LOG-REASON
                       PERFORM 8000-WRITE-LOG
                   END-IF
               END-IF
           END-PERFORM
           IF WS-CONNECTED
               CALL 'MQDISC' USING WS-HCONN
                                   WS-COMPCODE
                                   WS-REASON
               END-CALL
               SET WS-NOT-CONNECTED TO TRUE
           END-IF
           MOVE ZERO TO WS-QX
           MOVE WS-EVENT-STOPPED TO WS-LOG-EVENT
           PERFORM 8000-WRITE-LOG
           .
