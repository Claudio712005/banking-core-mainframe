package com.clau.banking.svc.adapter.out.mq.config;

import java.time.Duration;

import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.validation.annotation.Validated;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

@Validated
@ConfigurationProperties(prefix = "banking.mq")
public record MqProperties(
        @Valid @NotNull Queues queues,
        @NotNull Duration replyTimeout) {

    public record Queues(
            @NotBlank @Size(max = 48) String depositRequest,
            @NotBlank @Size(max = 48) String reply) {
    }
}
