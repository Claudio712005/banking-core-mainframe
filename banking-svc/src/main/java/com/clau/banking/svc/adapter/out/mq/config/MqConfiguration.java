package com.clau.banking.svc.adapter.out.mq.config;

import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.context.annotation.Configuration;

@Configuration(proxyBeanMethods = false)
@EnableConfigurationProperties(MqProperties.class)
public class MqConfiguration {
}
