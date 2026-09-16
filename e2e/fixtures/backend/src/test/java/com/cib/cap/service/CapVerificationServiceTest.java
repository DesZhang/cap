package com.cib.cap.service;

import com.cib.cap.model.VerifyResult;
import com.cib.cap.model.VerifyResult.Status;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.web.client.RestClient;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;

/**
 * CapVerificationService 单元测试
 */
@ExtendWith(MockitoExtension.class)
class CapVerificationServiceTest {

    @Mock
    private RestClient.Builder restClientBuilder;

    @Mock
    private RestClient restClient;

    private final ObjectMapper objectMapper = new ObjectMapper();

    private CapVerificationService createService(String instanceUrl, String siteKey, String secretKey) {
        lenient().when(restClientBuilder.requestFactory(any(org.springframework.http.client.ClientHttpRequestFactory.class)))
                .thenReturn(restClientBuilder);
        lenient().when(restClientBuilder.build()).thenReturn(restClient);
        return new CapVerificationService(restClientBuilder, objectMapper, instanceUrl, siteKey, secretKey);
    }

    @Test
    void constructor_missingSiteKey_throwsException() {
        IllegalStateException ex = assertThrows(IllegalStateException.class,
                () -> createService("http://localhost:3000", "", "test-secret"));
        assertTrue(ex.getMessage().contains("cap.site-key"));
    }

    @Test
    void constructor_missingSecretKey_throwsException() {
        IllegalStateException ex = assertThrows(IllegalStateException.class,
                () -> createService("http://localhost:3000", "test-site-key", ""));
        assertTrue(ex.getMessage().contains("cap.secret-key"));
    }

    @Test
    void constructor_missingInstanceUrl_throwsException() {
        IllegalStateException ex = assertThrows(IllegalStateException.class,
                () -> createService("", "test-site-key", "test-secret"));
        assertTrue(ex.getMessage().contains("cap.instance-url"));
    }

    @Test
    void verifyToken_nullToken_returnsEmptyToken() {
        CapVerificationService service = createService("http://localhost:3000", "test-site-key", "test-secret");
        VerifyResult result = service.verifyToken(null);

        assertEquals(Status.EMPTY_TOKEN, result.getStatus());
    }

    @Test
    void verifyToken_blankToken_returnsEmptyToken() {
        CapVerificationService service = createService("http://localhost:3000", "test-site-key", "test-secret");
        VerifyResult result = service.verifyToken("   ");

        assertEquals(Status.EMPTY_TOKEN, result.getStatus());
    }

    @Test
    void verifyToken_retriesOnFailure_thenGivesUp() {
        CapVerificationService service = createService("http://localhost:9999", "test-site-key", "test-secret");

        RestClient.RequestBodySpec bodySpec = mock(RestClient.RequestBodySpec.class);
        RestClient.RequestBodyUriSpec uriSpec = mock(RestClient.RequestBodyUriSpec.class);
        when(restClient.post()).thenReturn(uriSpec);
        when(uriSpec.uri(anyString())).thenReturn(bodySpec);
        when(bodySpec.header(anyString(), anyString())).thenReturn(bodySpec);
        when(bodySpec.body(any(String.class))).thenReturn(bodySpec);
        when(bodySpec.retrieve()).thenThrow(new RuntimeException("Connection refused"));

        VerifyResult result = service.verifyToken("valid-token");

        assertEquals(Status.SERVICE_UNAVAILABLE, result.getStatus());
        verify(restClient, times(3)).post();
    }

    @Test
    void verifyToken_succeedsOnRetry() {
        CapVerificationService service = createService("http://localhost:9999", "test-site-key", "test-secret");

        RestClient.RequestBodySpec bodySpec = mock(RestClient.RequestBodySpec.class);
        RestClient.RequestBodyUriSpec uriSpec = mock(RestClient.RequestBodyUriSpec.class);
        RestClient.ResponseSpec responseSpec = mock(RestClient.ResponseSpec.class);
        when(restClient.post()).thenReturn(uriSpec);
        when(uriSpec.uri(anyString())).thenReturn(bodySpec);
        when(bodySpec.header(anyString(), anyString())).thenReturn(bodySpec);
        when(bodySpec.body(any(String.class))).thenReturn(bodySpec);
        when(bodySpec.retrieve())
                .thenThrow(new RuntimeException("Connection refused"))
                .thenReturn(responseSpec);
        when(responseSpec.onStatus(any(), any())).thenReturn(responseSpec);
        when(responseSpec.body(String.class)).thenReturn("{\"success\":true}");

        VerifyResult result = service.verifyToken("valid-token");

        assertEquals(Status.SUCCESS, result.getStatus());
        verify(restClient, times(2)).post();
    }
}
