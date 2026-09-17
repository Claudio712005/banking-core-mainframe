package com.clau.banking.svc.config;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

import io.swagger.v3.oas.models.OpenAPI;
import io.swagger.v3.oas.models.info.Info;

@Configuration(proxyBeanMethods = false)
public class OpenApiConfiguration {

    @Bean
    OpenAPI bankingOpenApi() {
        return new OpenAPI().info(new Info()
                .title("banking-svc")
                .version("v1")
                .description("""
                        Integration service between REST clients and the COBOL core banking system.
                        Requests are validated here and exchanged with the core system through IBM MQ \
                        (request/reply); the core banking system is the system of record."""));
    }
}
