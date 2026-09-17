package com.clau.banking.svc.adapter.in.web.dto;

import java.math.BigDecimal;

import io.swagger.v3.oas.annotations.media.Schema;
import io.swagger.v3.oas.annotations.media.Schema.RequiredMode;
import jakarta.validation.constraints.Digits;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Positive;

@Schema(name = "DepositRequest", description = "Deposit to be credited to the account identified in the path.")
public record DepositRequest(

        @Schema(description = """
                Monetary amount to credit.
                Decimal value with at most 13 integer digits and at most 2 decimal places; \
                it is stored and forwarded with exactly 2 decimal places and is never rounded. \
                Must be greater than zero. Send it as a JSON decimal literal (100.50) or as a \
                string ("100.50"); clients must not compute it with binary floating point \
                (double/float).""",
                type = "string", format = "decimal", example = "100.50",
                minimum = "0.01", maximum = "9999999999999.99", requiredMode = RequiredMode.REQUIRED)
        @NotNull(message = "is required")
        @Positive(message = "must be greater than zero")
        @Digits(integer = 13, fraction = 2, message = "must have at most 13 integer digits and 2 decimal places")
        BigDecimal amount,

        @Schema(description = """
                Currency of the amount, ISO 4217 alphabetic code in upper case. \
                Must match the currency of the account; the core banking system rejects \
                deposits in a different currency.""",
                example = "BRL", pattern = "^[A-Z]{3}$", minLength = 3, maxLength = 3,
                requiredMode = RequiredMode.REQUIRED)
        @NotBlank(message = "is required")
        @Pattern(regexp = "^[A-Z]{3}$", message = "must be a 3-letter upper-case ISO 4217 code")
        String currency) {
}
