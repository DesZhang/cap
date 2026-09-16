package com.cib.cap.controller;

import com.cib.cap.model.VerifyResult;
import com.cib.cap.service.CapVerificationService;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;

import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

/**
 * CapController 单元测试
 */
@WebMvcTest(CapController.class)
class CapControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private ObjectMapper objectMapper;

    @MockitoBean
    private CapVerificationService verificationService;

    @Test
    void verify_emptyToken_returns400() throws Exception {
        when(verificationService.verifyToken(""))
                .thenReturn(VerifyResult.emptyToken());

        mockMvc.perform(post("/api/cap/verify")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"token\":\"\"}"))
                .andExpect(status().isBadRequest())
                .andExpect(content().string(""));
    }

    @Test
    void verify_nullToken_returns400() throws Exception {
        when(verificationService.verifyToken(null))
                .thenReturn(VerifyResult.emptyToken());

        mockMvc.perform(post("/api/cap/verify")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{}"))
                .andExpect(status().isBadRequest())
                .andExpect(content().string(""));
    }

    @Test
    void verify_validToken_returns200() throws Exception {
        when(verificationService.verifyToken("valid-token"))
                .thenReturn(VerifyResult.success());

        mockMvc.perform(post("/api/cap/verify")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"token\":\"valid-token\"}"))
                .andExpect(status().isOk())
                .andExpect(content().string(""));
    }

    @Test
    void verify_invalidToken_returns401() throws Exception {
        when(verificationService.verifyToken("bad-token"))
                .thenReturn(VerifyResult.tokenInvalid("Token not found"));

        mockMvc.perform(post("/api/cap/verify")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"token\":\"bad-token\"}"))
                .andExpect(status().isUnauthorized())
                .andExpect(content().string(""));
    }

    @Test
    void verify_serviceUnavailable_returns503() throws Exception {
        when(verificationService.verifyToken("some-token"))
                .thenReturn(VerifyResult.serviceUnavailable("重试耗尽"));

        mockMvc.perform(post("/api/cap/verify")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"token\":\"some-token\"}"))
                .andExpect(status().isServiceUnavailable())
                .andExpect(content().string(""));
    }
}
