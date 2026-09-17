package com.clau.banking.svc.adapter.in.web.dto;

import java.time.Instant;
import java.util.List;

import io.swagger.v3.oas.annotations.media.Schema;

@Schema(name = "ErrorResponse", description = "Standard error body. Never contains stack traces, "
        + "IBM MQ details or rejected values.")
public record ErrorResponse(

        @Schema(description = "Instant (UTC, ISO-8601) the error occurred.", example = "2026-09-16T20:00:00Z")
        Instant timestamp,

        @Schema(description = "HTTP status code.", example = "422")
        int status,

        @Schema(description = "Stable, machine-readable error code.",
                allowableValues = {"INVALID_REQUEST", "MALFORMED_REQUEST", "NOT_FOUND", "METHOD_NOT_ALLOWED",
                        "UNSUPPORTED_MEDIA_TYPE", "ACCOUNT_NOT_FOUND", "IDEMPOTENCY_KEY_CONFLICT",
                        "ACCOUNT_NOT_ACTIVE", "BALANCE_LIMIT_EXCEEDED", "CUSTOMER_NOT_ACTIVE",
                        "CURRENCY_MISMATCH", "CORE_BANKING_UNAVAILABLE", "CORE_BANKING_TIMEOUT",
                        "INTERNAL_ERROR"},
                example = "ACCOUNT_NOT_ACTIVE")
        String code,

        @Schema(description = "Human-readable summary. Not meant to be parsed.", example = "Account is not active")
        String message,

        @Schema(description = "Correlation ID of the failed request.",
                example = "c0ffee00-0000-4000-8000-000000000001")
        String correlationId,

        @Schema(description = "Field-level problems; empty when not applicable.")
        List<Detail> details) {

    @Schema(name = "ErrorDetail", description = "One validation problem.")
    public record Detail(

            @Schema(description = "Body field, path variable or header that was rejected.", example = "amount")
            String field,

            @Schema(description = "Rule that was violated.", example = "must be greater than zero")
            String message) {
    }
}
