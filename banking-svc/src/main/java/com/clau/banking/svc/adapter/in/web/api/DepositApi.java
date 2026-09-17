package com.clau.banking.svc.adapter.in.web.api;

import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;

import com.clau.banking.svc.adapter.in.web.dto.DepositRequest;
import com.clau.banking.svc.adapter.in.web.dto.DepositResponse;
import com.clau.banking.svc.adapter.in.web.dto.ErrorResponse;

import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.Parameter;
import io.swagger.v3.oas.annotations.headers.Header;
import io.swagger.v3.oas.annotations.media.Content;
import io.swagger.v3.oas.annotations.media.ExampleObject;
import io.swagger.v3.oas.annotations.media.Schema;
import io.swagger.v3.oas.annotations.responses.ApiResponse;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import jakarta.validation.constraints.Pattern;

@Tag(name = "Deposits", description = "Credit operations posted by the COBOL core banking system")
@RequestMapping("/api/v1/accounts/{accountId}/deposits")
public interface DepositApi {

    String IDEMPOTENCY_KEY_HEADER = "Idempotency-Key";
    String CORRELATION_ID_HEADER = "X-Correlation-Id";
    String ACCOUNT_ID_FORMAT = "^(?!0{10}$)[0-9]{10}$";
    String IDEMPOTENCY_KEY_FORMAT = "^[A-Za-z0-9-]{16,36}$";
    String CORRELATION_ID_FORMAT = "^[A-Za-z0-9-]{1,36}$";

    @Operation(
            summary = "Post a deposit",
            description = """
                    Sends the deposit to the COBOL core banking system (program ACCTDEP) through IBM MQ \
                    and waits for its reply.

                    The core banking system posts a given `Idempotency-Key` at most once. Retrying with \
                    the same key after a timeout or a 503 is safe: the original result is returned with \
                    `idempotentReplay = true`. Reusing a key for a different deposit is rejected with 409.""")
    @ApiResponse(responseCode = "200", description = "Deposit posted, or original result of an idempotent replay.",
            headers = @Header(name = CORRELATION_ID_HEADER, description = "Correlation ID of the request.",
                    schema = @Schema(implementation = String.class)),
            content = @Content(mediaType = MediaType.APPLICATION_JSON_VALUE,
                    schema = @Schema(implementation = DepositResponse.class)))
    @ApiResponse(responseCode = "400", description = "Invalid path, header or body (`INVALID_REQUEST`, `MALFORMED_REQUEST`).",
            content = @Content(mediaType = MediaType.APPLICATION_JSON_VALUE,
                    schema = @Schema(implementation = ErrorResponse.class),
                    examples = @ExampleObject(value = """
                            {"timestamp":"2026-09-16T20:00:00Z","status":400,"code":"INVALID_REQUEST",
                             "message":"Request validation failed",
                             "correlationId":"c0ffee00-0000-4000-8000-000000000001",
                             "details":[{"field":"amount","message":"must be greater than zero"}]}""")))
    @ApiResponse(responseCode = "404", description = "Account does not exist (`ACCOUNT_NOT_FOUND`, core code 2001).",
            content = @Content(mediaType = MediaType.APPLICATION_JSON_VALUE,
                    schema = @Schema(implementation = ErrorResponse.class)))
    @ApiResponse(responseCode = "409", description = "Idempotency-Key already used for a different operation "
            + "(`IDEMPOTENCY_KEY_CONFLICT`, core code 2007).",
            content = @Content(mediaType = MediaType.APPLICATION_JSON_VALUE,
                    schema = @Schema(implementation = ErrorResponse.class)))
    @ApiResponse(responseCode = "415", description = "Content type other than application/json (`UNSUPPORTED_MEDIA_TYPE`).",
            content = @Content(mediaType = MediaType.APPLICATION_JSON_VALUE,
                    schema = @Schema(implementation = ErrorResponse.class)))
    @ApiResponse(responseCode = "422", description = """
            Rejected by a business rule of the core banking system: \
            `ACCOUNT_NOT_ACTIVE` (2002), `BALANCE_LIMIT_EXCEEDED` (2004), `CUSTOMER_NOT_ACTIVE` (2006), \
            `CURRENCY_MISMATCH` (2008).""",
            content = @Content(mediaType = MediaType.APPLICATION_JSON_VALUE,
                    schema = @Schema(implementation = ErrorResponse.class),
                    examples = @ExampleObject(value = """
                            {"timestamp":"2026-09-16T20:00:00Z","status":422,"code":"ACCOUNT_NOT_ACTIVE",
                             "message":"Account is not active",
                             "correlationId":"c0ffee00-0000-4000-8000-000000000001","details":[]}""")))
    @ApiResponse(responseCode = "503", description = """
            Core banking system unreachable or retries exhausted (`CORE_BANKING_UNAVAILABLE`, core codes 9xxx). \
            Retry later with the same Idempotency-Key.""",
            content = @Content(mediaType = MediaType.APPLICATION_JSON_VALUE,
                    schema = @Schema(implementation = ErrorResponse.class)))
    @ApiResponse(responseCode = "504", description = """
            No reply from the core banking system within the configured timeout (`CORE_BANKING_TIMEOUT`). \
            The deposit may or may not have been posted: retry with the same Idempotency-Key.""",
            content = @Content(mediaType = MediaType.APPLICATION_JSON_VALUE,
                    schema = @Schema(implementation = ErrorResponse.class)))
    @ApiResponse(responseCode = "500", description = "Unexpected error (`INTERNAL_ERROR`).",
            content = @Content(mediaType = MediaType.APPLICATION_JSON_VALUE,
                    schema = @Schema(implementation = ErrorResponse.class)))
    @PostMapping(consumes = MediaType.APPLICATION_JSON_VALUE, produces = MediaType.APPLICATION_JSON_VALUE)
    ResponseEntity<DepositResponse> requestDeposit(

            @Parameter(description = "Account to credit: exactly 10 digits, leading zeros are significant, not all zeros.",
                    example = "1000000001", schema = @Schema(pattern = ACCOUNT_ID_FORMAT))
            @PathVariable("accountId")
            @Pattern(regexp = ACCOUNT_ID_FORMAT, message = "must be exactly 10 digits and not all zeros")
            String accountId,

            @Parameter(description = "Client-generated key identifying this financial intent (UUID recommended). "
                    + "16 to 36 characters from [A-Za-z0-9-]. Reuse it on every retry of the same deposit.",
                    required = true, example = "7f1c2a9e-5b3d-4c8e-9a01-000000000001",
                    schema = @Schema(minLength = 16, maxLength = 36, pattern = IDEMPOTENCY_KEY_FORMAT))
            @RequestHeader(IDEMPOTENCY_KEY_HEADER)
            @Pattern(regexp = IDEMPOTENCY_KEY_FORMAT, message = "must have 16 to 36 characters from [A-Za-z0-9-]")
            String idempotencyKey,

            @Parameter(description = "Optional correlation ID (up to 36 characters from [A-Za-z0-9-]). "
                    + "Generated by the service when absent; always returned in the response header.",
                    example = "c0ffee00-0000-4000-8000-000000000001",
                    schema = @Schema(maxLength = 36, pattern = CORRELATION_ID_FORMAT))
            @RequestHeader(value = CORRELATION_ID_HEADER, required = false)
            @Pattern(regexp = CORRELATION_ID_FORMAT, message = "must have up to 36 characters from [A-Za-z0-9-]")
            String correlationId,

            @Valid @RequestBody
            DepositRequest request);
}
