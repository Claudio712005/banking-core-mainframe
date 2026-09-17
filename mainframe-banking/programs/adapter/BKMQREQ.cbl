       IDENTIFICATION DIVISION.
       PROGRAM-ID. BKMQREQ.
      *================================================================*
      * PROGRAM  : BKMQREQ                                             *
      * TYPE     : LAB TEST TOOL (IBM MQ CLIENT REQUESTER)             *
      * PURPOSE  : SENDS EACH 200-BYTE LINE OF DD REQIN AS AN MQ       *
      *            REQUEST AND PRINTS THE 300-BYTE REPLY, MATCHED BY   *
      *            CORRELID. USED TO EXERCISE BKMQLSN WITHOUT THE      *
      *            JAVA SERVICE. NOT PART OF THE PRODUCTION FLOW.      *
      * ENVIRONMENT                                                    *
      *   MQSERVER, MQ_QUEUE_MANAGER, MQ_USERNAME, MQ_PASSWORD         *
      *   BK_TARGET_QUEUE   REQUEST QUEUE                              *
      *   BK_REPLY_QUEUE    REPLY QUEUE                                *
      *   DD_REQIN          REQUEST FILE (E.G. /DEV/STDIN)             *
      * OUTPUT   : ONE 'REPLY' OR 'NO REPLY' LINE PER REQUEST.         *
      *================================================================*
       ENVIRONMENT DIVISION.
       INPUT-OUTPUT SECTION.
       FILE-CONTROL.
           SELECT REQUEST-FILE
               ASSIGN TO REQIN
               ORGANIZATION IS LINE SEQUENTIAL
               FILE STATUS IS WS-REQUEST-FILE-STATUS.

       DATA DIVISION.
       FILE SECTION.
       FD  REQUEST-FILE.
       01  REQUEST-FILE-RECORD              PIC X(200).

       WORKING-STORAGE SECTION.
       01  WS-CONSTANTS.
           05  WS-REQUEST-LENGTH            PIC S9(09) BINARY
                                            VALUE +200.
           05  WS-REPLY-BUFFER-LENGTH       PIC S9(09) BINARY
                                            VALUE +300.
           05  WS-REPLY-WAIT-MS             PIC S9(09) BINARY
                                            VALUE +15000.
           05  WS-APPLICATION-NAME          PIC X(28)
                                            VALUE 'BKMQREQ'.

       01  WS-MQ-USER                       PIC X(64).
       01  WS-MQ-PASSWORD                   PIC X(256).
       01  WS-SECRET-LENGTH                 PIC S9(09) BINARY.

       01  WS-CONFIGURATION.
           05  WS-QUEUE-MANAGER             PIC X(48).
           05  WS-TARGET-QUEUE              PIC X(48).
           05  WS-REPLY-QUEUE               PIC X(48).

       01  WS-FLAGS.
           05  WS-REQUEST-FILE-STATUS       PIC X(02).
               88  WS-REQUEST-OK                     VALUE '00'.
               88  WS-REQUEST-END                    VALUE '10'.
           05  WS-RUN-FLAG                  PIC X(01).
               88  WS-RUNNING                        VALUE 'Y'.
               88  WS-FINISHED                       VALUE 'N'.

       01  WS-MQ-CALL-AREAS.
           05  WS-HCONN                     PIC S9(09) BINARY.
           05  WS-HOBJ-REPLY                PIC S9(09) BINARY.
           05  WS-OPTIONS                   PIC S9(09) BINARY.
           05  WS-COMPCODE                  PIC S9(09) BINARY.
           05  WS-REASON                    PIC S9(09) BINARY.
           05  WS-DATA-LENGTH               PIC S9(09) BINARY.
           05  WS-SENT-MSGID                PIC X(24).

       01  WS-DISPLAY-REASON                PIC 9(04).
       01  WS-REPLY                         PIC X(300).

       01  MQM-CONSTANTS.
           COPY CMQV.
       01  WS-CONNECT-OPTIONS.
           COPY CMQCNOV.
       01  WS-SECURITY-PARMS.
           COPY CMQCSPV.
       01  WS-DEFAULT-OD.
           COPY CMQODV.
       01  WS-OD.
           COPY CMQODV.
       01  WS-DEFAULT-MD.
           COPY CMQMDV.
       01  WS-MD.
           COPY CMQMDV.
       01  WS-PUT-OPTIONS.
           COPY CMQPMOV.
       01  WS-GET-OPTIONS.
           COPY CMQGMOV.

       PROCEDURE DIVISION.
       0000-MAIN.
           SET WS-RUNNING TO TRUE
           PERFORM 1000-CONNECT
           IF WS-RUNNING
               PERFORM 1100-OPEN-REPLY-QUEUE
           END-IF
           IF WS-RUNNING
               OPEN INPUT REQUEST-FILE
               IF NOT WS-REQUEST-OK
                   DISPLAY 'BKMQREQ CANNOT OPEN REQIN FS='
                           WS-REQUEST-FILE-STATUS
                   SET WS-FINISHED TO TRUE
               END-IF
           END-IF
           PERFORM 2000-SEND-NEXT-REQUEST UNTIL WS-FINISHED
           CLOSE REQUEST-FILE
           CALL 'MQDISC' USING WS-HCONN WS-COMPCODE WS-REASON
           STOP RUN
           .

       1000-CONNECT.
           MOVE SPACES TO WS-QUEUE-MANAGER WS-TARGET-QUEUE
                          WS-REPLY-QUEUE WS-MQ-USER WS-MQ-PASSWORD
           ACCEPT WS-QUEUE-MANAGER FROM ENVIRONMENT 'MQ_QUEUE_MANAGER'
           ACCEPT WS-MQ-USER       FROM ENVIRONMENT 'MQ_USERNAME'
           ACCEPT WS-MQ-PASSWORD   FROM ENVIRONMENT 'MQ_PASSWORD'
           ACCEPT WS-TARGET-QUEUE  FROM ENVIRONMENT 'BK_TARGET_QUEUE'
           ACCEPT WS-REPLY-QUEUE   FROM ENVIRONMENT 'BK_REPLY_QUEUE'
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
           CALL 'MQCONNX' USING WS-QUEUE-MANAGER WS-CONNECT-OPTIONS
                                WS-HCONN WS-COMPCODE WS-REASON
           MOVE SPACES TO WS-MQ-PASSWORD
           IF WS-COMPCODE = MQCC-FAILED
               MOVE WS-REASON TO WS-DISPLAY-REASON
               DISPLAY 'BKMQREQ MQCONNX FAILED REASON='
                       WS-DISPLAY-REASON
               SET WS-FINISHED TO TRUE
           END-IF
           .

       1100-OPEN-REPLY-QUEUE.
           MOVE WS-DEFAULT-OD TO WS-OD
           MOVE WS-REPLY-QUEUE TO MQOD-OBJECTNAME OF WS-OD
           COMPUTE WS-OPTIONS = MQOO-INPUT-SHARED
                              + MQOO-FAIL-IF-QUIESCING
           END-COMPUTE
           CALL 'MQOPEN' USING WS-HCONN WS-OD WS-OPTIONS
                               WS-HOBJ-REPLY WS-COMPCODE WS-REASON
           IF WS-COMPCODE NOT = MQCC-OK
               MOVE WS-REASON TO WS-DISPLAY-REASON
               DISPLAY 'BKMQREQ MQOPEN FAILED REASON=' WS-DISPLAY-REASON
               SET WS-FINISHED TO TRUE
           END-IF
           .

       2000-SEND-NEXT-REQUEST.
           READ REQUEST-FILE
           EVALUATE TRUE
               WHEN WS-REQUEST-OK
                   PERFORM 2100-PUT-REQUEST
                   IF WS-COMPCODE = MQCC-OK
                       PERFORM 2200-GET-REPLY
                   END-IF
               WHEN OTHER
                   SET WS-FINISHED TO TRUE
           END-EVALUATE
           .

       2100-PUT-REQUEST.
           MOVE WS-DEFAULT-MD TO WS-MD
           MOVE MQMT-REQUEST     TO MQMD-MSGTYPE     OF WS-MD
           MOVE MQFMT-STRING     TO MQMD-FORMAT      OF WS-MD
           MOVE MQPER-PERSISTENT TO MQMD-PERSISTENCE OF WS-MD
           MOVE WS-REPLY-QUEUE   TO MQMD-REPLYTOQ    OF WS-MD
           MOVE WS-DEFAULT-OD TO WS-OD
           MOVE WS-TARGET-QUEUE TO MQOD-OBJECTNAME OF WS-OD
           COMPUTE MQPMO-OPTIONS OF WS-PUT-OPTIONS =
                   MQPMO-NO-SYNCPOINT
                 + MQPMO-NEW-MSG-ID
                 + MQPMO-FAIL-IF-QUIESCING
           END-COMPUTE
           CALL 'MQPUT1' USING WS-HCONN WS-OD WS-MD WS-PUT-OPTIONS
                               WS-REQUEST-LENGTH REQUEST-FILE-RECORD
                               WS-COMPCODE WS-REASON
           IF WS-COMPCODE = MQCC-OK
               MOVE MQMD-MSGID OF WS-MD TO WS-SENT-MSGID
           ELSE
               MOVE WS-REASON TO WS-DISPLAY-REASON
               DISPLAY 'SEND FAILED REASON=' WS-DISPLAY-REASON
           END-IF
           .

       2200-GET-REPLY.
           MOVE WS-DEFAULT-MD TO WS-MD
           MOVE MQMI-NONE     TO MQMD-MSGID    OF WS-MD
           MOVE WS-SENT-MSGID TO MQMD-CORRELID OF WS-MD
           COMPUTE MQGMO-OPTIONS OF WS-GET-OPTIONS =
                   MQGMO-NO-SYNCPOINT
                 + MQGMO-WAIT
                 + MQGMO-CONVERT
                 + MQGMO-FAIL-IF-QUIESCING
           END-COMPUTE
           MOVE WS-REPLY-WAIT-MS TO MQGMO-WAITINTERVAL OF WS-GET-OPTIONS
           MOVE SPACES TO WS-REPLY
           CALL 'MQGET' USING WS-HCONN WS-HOBJ-REPLY WS-MD
                              WS-GET-OPTIONS WS-REPLY-BUFFER-LENGTH
                              WS-REPLY WS-DATA-LENGTH
                              WS-COMPCODE WS-REASON
           IF WS-COMPCODE = MQCC-FAILED
               MOVE WS-REASON TO WS-DISPLAY-REASON
               DISPLAY 'NO REPLY REASON=' WS-DISPLAY-REASON
           ELSE
               DISPLAY 'REPLY ' FUNCTION TRIM(WS-REPLY TRAILING)
           END-IF
           .
