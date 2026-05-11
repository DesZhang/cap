package com.cib.cap.config;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.servlet.config.annotation.CorsRegistry;
import org.springframework.web.servlet.config.annotation.WebMvcConfigurer;

/**
 * Web 配置
 * <p>
 * CORS 允许的前端域名通过 cap.cors-origins 配置，支持多环境切换。
 */
@Configuration
public class WebConfig implements WebMvcConfigurer {

    @Value("${cap.cors-origins:http://localhost:5173,http://localhost:3000}")
    private String corsOrigins;

    @Override
    public void addCorsMappings(CorsRegistry registry) {
        registry.addMapping("/api/**")
                .allowedOrigins(corsOrigins.split(","))
                .allowedMethods("POST", "GET", "OPTIONS")
                .allowedHeaders("*");
    }
}
