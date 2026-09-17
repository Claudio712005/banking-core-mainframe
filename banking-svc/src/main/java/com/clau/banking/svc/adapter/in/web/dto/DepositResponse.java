package com.clau.banking.svc.adapter.in.web.dto;

import java.math.BigDecimal;
import java.time.LocalDateTime;

import com.fasterxml.jackson.annotation.JsonFormat;

import io.swagger.v3.oas.annotations.media.Schema;

@Schema(name = "DepositResponse", description = "Deposit posted by the core banking system.")
public record DepositResponse(

        @Schema(description = "Transaction identifier assigned by the core banking system (16 digits).",
                example = "0000000000000003")
        String transactionId,

        @Schema(description = "Posting status. Only POSTED is returned; rejections are reported as errors.",
                example = "POSTED")
        DepositStatus status,

        @Schema(description = "true when this response replays the original result of a previous request "
                + "with the same Idempotency-Key; no money was moved by this request.",
                example = "false")
        boolean idempotentReplay,

        @Schema(description = "Credited account (10 digits, leading zeros preserved).", example = "1000000001")
        String accountId,

        @Schema(description = "Posted amount with exactly 2 decimal places, serialized as a string.",
                type = "string", format = "decimal", example = "100.50")
        @JsonFormat(shape = JsonFormat.Shape.STRING)
        BigDecimal amount,

        @Schema(description = "Account balance immediately after this posting, exactly 2 decimal places. "
                + "For a replay it is the balance at the time of the original posting, not the current one.",
                type = "string", format = "decimal", example = "1600.50")
        @JsonFormat(shape = JsonFormat.Shape.STRING)
        BigDecimal newBalance,

        @Schema(description = "ISO 4217 currency code.", example = "BRL")
        String currency,

        @Schema(description = "Posting timestamp reported by the core banking system, in its local time "
                + "(ISO-8601 without offset).", example = "2026-09-16T10:30:00.000000")
        LocalDateTime postedAt,

        @Schema(description = "Correlation ID of the request (also returned in the X-Correlation-Id header).",
                example = "c0ffee00-0000-4000-8000-000000000001")
        String correlationId) {

    public enum DepositStatus {
        POSTED
    }
}
