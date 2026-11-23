// Copyright (c) 2026 WSO2 LLC (http://www.wso2.com).
//
// WSO2 LLC. licenses this file to you under the Apache License,
// Version 2.0 (the "License"); you may not use this file except
// in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing,
// software distributed under the License is distributed on an
// "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied.  See the License for the
// specific language governing permissions and limitations
// under the License.

import ballerina/ai;
import ballerina/http;
import ballerina/lang.runtime;
import ballerina/test;
import ballerinax/openai.chat;
import ballerinax/openai.embeddings;
import ballerinax/openai.responses;

const AUTH_SERVICE_URL = "http://localhost:8091/auth";
const TOKEN_SERVICE_URL = "http://localhost:8091/auth/oauth";
const AUTH_API_KEY = "sk-test-key";
const ORGANIZATION_ID = "org-test";
const PROJECT_ID = "proj_test";
const IDENTITY_PROVIDER_ID = "idp_test";
const SERVICE_ACCOUNT_ID = "svc_acct_test";
const IDENTITY_TOKEN = "eyJ.test-identity-token.sig";
const AUTH_HEADERS = ["authorization", "openai-organization", "openai-project"];

// The headers received by the mock API, keyed by `<test ID>:<call>:<header>`.
isolated map<json> capturedAuthHeaders = {};
// The token exchange requests received by the mock token endpoint, keyed by test ID.
isolated map<map<json>[]> tokenExchangeRequests = {};

isolated function captureAuthHeaders(string testId, string call, http:Request req) {
    foreach string header in AUTH_HEADERS {
        string|http:HeaderNotFoundError value = req.getHeader(header);
        lock {
            capturedAuthHeaders[string `${testId}:${call}:${header}`] = value is string ? value : ();
        }
    }
}

isolated function getAuthHeader(string testId, string call, string header) returns string?|error {
    json value;
    lock {
        if !capturedAuthHeaders.hasKey(string `${testId}:${call}:${header}`) {
            return error(string `No ${call} request was received for ${testId}`);
        }
        value = capturedAuthHeaders[string `${testId}:${call}:${header}`].clone();
    }
    return value.ensureType();
}

isolated function getTokenExchangeRequests(string testId) returns map<json>[] {
    lock {
        return (tokenExchangeRequests[testId] ?: []).clone();
    }
}

service /auth on new http:Listener(8091) {
    resource function post [string testId]/chat/completions(http:Request req, @http:Payload json payload)
            returns chat:CreateChatCompletionResponse {
        boolean isGenerate = payload.tools is json[];
        captureAuthHeaders(testId, isGenerate ? "generate" : "chat", req);
        return isGenerate ? getGenerateResultToolResponse("{\"result\": 5}")
            : getChatCompletionsSimpleChatResponse("Hi");
    }

    resource function post [string testId]/responses(http:Request req, @http:Payload json payload)
            returns responses:Response {
        boolean isGenerate = payload.tools is json[];
        captureAuthHeaders(testId, isGenerate ? "generate" : "chat", req);
        return isGenerate ? getResponsesGenerateResultResponse("{\"result\": 5}")
            : getTestResponsesApiChatResponse("Hi");
    }

    resource function post [string testId]/embeddings(http:Request req, @http:Payload json payload)
            returns embeddings:CreateEmbeddingResponse|error {
        json input = check payload.input;
        int count = input is json[] ? input.length() : 1;
        captureAuthHeaders(testId, input is json[] ? "batchEmbed" : "embed", req);
        embeddings:CreateEmbeddingResponse_data[] data = [];
        foreach int i in 0 ..< count {
            data.push({index: i, 'object: "embedding", embedding: [0.1, 0.2, 0.3]});
        }
        return {'object: "list", model: TEXT_EMBEDDING_3_SMALL, data, usage: {prompt_tokens: 5, total_tokens: 5}};
    }

    // Mock token exchange endpoint. Issues access tokens that expire in `expiresIn` seconds. With `failAfter` > 0,
    // exchanges after the first `failAfter` fail; with -1, every exchange fails. With `failDelay`, a failing
    // exchange responds after that many seconds. A failing exchange returns a 401, or a 503 with `unavailable`.
    resource function post oauth/[string testId]/[int expiresIn]/[int failAfter]/token(
            @http:Payload map<json> payload, decimal? failDelay, boolean unavailable = false)
            returns json|http:Unauthorized|http:ServiceUnavailable {
        int count;
        lock {
            map<json>[] requests = tokenExchangeRequests[testId] ?: [];
            requests.push(payload.clone());
            tokenExchangeRequests[testId] = requests;
            count = requests.length();
        }
        if failAfter == -1 || (failAfter > 0 && count > failAfter) {
            if failDelay is decimal {
                runtime:sleep(failDelay);
            }
            if unavailable {
                return <http:ServiceUnavailable>{body: {'error: "temporarily_unavailable"}};
            }
            return <http:Unauthorized>{body: {'error: "invalid_grant", error_description: "Token exchange denied"}};
        }
        return {
            access_token: string `wif-access-token-${testId}-${count}`,
            issued_token_type: "urn:ietf:params:oauth:token-type:access_token",
            token_type: "Bearer",
            expires_in: expiresIn,
            expires_at: 1789045200
        };
    }
}

function authServiceUrl(string testId) returns string => string `${AUTH_SERVICE_URL}/${testId}`;

function tokenUrl(string testId, int expiresIn = 3600, int failAfter = 0, decimal? failDelay = (),
        boolean unavailable = false) returns string {
    string url = string `${TOKEN_SERVICE_URL}/${testId}/${expiresIn}/${failAfter}/token?unavailable=${unavailable}`;
    return failDelay is () ? url : string `${url}&failDelay=${failDelay}`;
}

function workloadIdentityConfig(string testId, int expiresIn = 3600, int failAfter = 0,
        SubjectTokenType identityTokenType = JWT, decimal? failDelay = (), boolean unavailable = false)
        returns WorkloadIdentityConfig => {
    identityProviderId: IDENTITY_PROVIDER_ID,
    serviceAccountId: SERVICE_ACCOUNT_ID,
    identityToken: IDENTITY_TOKEN,
    identityTokenType,
    tokenUrl: tokenUrl(testId, expiresIn, failAfter, failDelay, unavailable)
};

function chatConcurrently(ModelProvider provider, int count) returns (ai:ChatAssistantMessage|ai:Error)[] {
    future<ai:ChatAssistantMessage|ai:Error>[] calls = [];
    foreach int i in 0 ..< count {
        future<ai:ChatAssistantMessage|ai:Error> call = start provider->chat([{role: ai:USER, content: "Hi"}]);
        calls.push(call);
    }
    (ai:ChatAssistantMessage|ai:Error)[] results = [];
    foreach future<ai:ChatAssistantMessage|ai:Error> call in calls {
        ai:ChatAssistantMessage|ai:Error result = wait call;
        results.push(result);
    }
    return results;
}

function callChatAndGenerate(ModelProvider provider) returns error? {
    _ = check provider->chat([{role: ai:USER, content: "Hi"}]);
    int result = check provider->generate(`Pick a number`);
    test:assertEquals(result, 5);
}

function assertAuthHeaders(string testId, string[] calls, string authorization, string? organization = (),
        string? project = ()) returns error? {
    foreach string call in calls {
        test:assertEquals(check getAuthHeader(testId, call, "authorization"), authorization,
            string `Unexpected Authorization header on ${call}`);
        test:assertEquals(check getAuthHeader(testId, call, "openai-organization"), organization,
            string `Unexpected OpenAI-Organization header on ${call}`);
        test:assertEquals(check getAuthHeader(testId, call, "openai-project"), project,
            string `Unexpected OpenAI-Project header on ${call}`);
    }
}

function assertTokenExchangeRequest(map<json> request, SubjectTokenType identityTokenType = JWT) {
    test:assertEquals(request, {
        grant_type: "urn:ietf:params:oauth:grant-type:token-exchange",
        subject_token: IDENTITY_TOKEN,
        subject_token_type: identityTokenType,
        identity_provider_id: IDENTITY_PROVIDER_ID,
        service_account_id: SERVICE_ACCOUNT_ID
    });
}

// ---------------------------------------------------------------------------------------------------------------
// API keys and bearer tokens
// ---------------------------------------------------------------------------------------------------------------

@test:Config
function testStringApiKeyAuth() returns error? {
    string testId = "string-api-key";
    check callChatAndGenerate(check new (AUTH_API_KEY, GPT_4_1, authServiceUrl(testId)));
    check assertAuthHeaders(testId, ["chat", "generate"], string `Bearer ${AUTH_API_KEY}`);
}

@test:Config
function testStringApiKeyAuthAsNamedArgumentWithResponsesApi() returns error? {
    string testId = "string-api-key-responses";
    check callChatAndGenerate(check new (apiKey = AUTH_API_KEY, modelType = GPT_4O,
        serviceUrl = authServiceUrl(testId), apiType = RESPONSES));
    check assertAuthHeaders(testId, ["chat", "generate"], string `Bearer ${AUTH_API_KEY}`);
}

@test:Config
function testApiKeyConfigAuth() returns error? {
    string testId = "api-key-config";
    check callChatAndGenerate(check new ({apiKey: AUTH_API_KEY}, GPT_4_1, authServiceUrl(testId)));
    check assertAuthHeaders(testId, ["chat", "generate"], string `Bearer ${AUTH_API_KEY}`);
}

@test:Config
function testApiKeyConfigWithOrganizationAndProject() returns error? {
    string testId = "api-key-org-project";
    check callChatAndGenerate(check new ({apiKey: AUTH_API_KEY, organization: ORGANIZATION_ID, project: PROJECT_ID},
        GPT_4_1, authServiceUrl(testId)));
    check assertAuthHeaders(testId, ["chat", "generate"], string `Bearer ${AUTH_API_KEY}`, ORGANIZATION_ID,
        PROJECT_ID);
}

@test:Config
function testApiKeyConfigWithProjectOnlyWithResponsesApi() returns error? {
    string testId = "api-key-project-responses";
    check callChatAndGenerate(check new ({apiKey: AUTH_API_KEY, project: PROJECT_ID}, GPT_4O,
        authServiceUrl(testId), apiType = RESPONSES));
    check assertAuthHeaders(testId, ["chat", "generate"], string `Bearer ${AUTH_API_KEY}`, project = PROJECT_ID);
}

@test:Config
function testBearerTokenAuth() returns error? {
    string testId = "bearer-token";
    check callChatAndGenerate(check new ({token: "access-token-from-elsewhere"}, GPT_4_1, authServiceUrl(testId)));
    check assertAuthHeaders(testId, ["chat", "generate"], "Bearer access-token-from-elsewhere");
}

@test:Config
function testApiKeyIsTrimmed() returns error? {
    string testId = "api-key-trimmed";
    // A key read from a file or an environment variable may end with a newline.
    ModelProvider stringProvider = check new (string ` ${AUTH_API_KEY}${"\n"}`, GPT_4_1, authServiceUrl(testId));
    _ = check stringProvider->chat([{role: ai:USER, content: "Hi"}]);
    check assertAuthHeaders(testId, ["chat"], string `Bearer ${AUTH_API_KEY}`);
    ModelProvider configProvider = check new ({apiKey: string `${AUTH_API_KEY}${"\n"}`, project: PROJECT_ID},
        GPT_4_1, authServiceUrl(testId));
    _ = check configProvider->chat([{role: ai:USER, content: "Hi"}]);
    check assertAuthHeaders(testId, ["chat"], string `Bearer ${AUTH_API_KEY}`, project = PROJECT_ID);
}

@test:Config
function testEmptyApiKeyFails() {
    foreach string|ApiKeyConfig apiKey in ["", " \n", {apiKey: ""}] {
        ModelProvider|ai:Error provider = new (apiKey, GPT_4_1);
        if provider !is ai:Error {
            test:assertFail("Expected an ai:Error for an empty API key");
        }
        test:assertEquals(provider.message(), "The OpenAI API key is empty");
        EmbeddingProvider|ai:Error embeddingProvider = new (apiKey, TEXT_EMBEDDING_3_SMALL);
        if embeddingProvider !is ai:Error {
            test:assertFail("Expected an ai:Error for an empty API key");
        }
        test:assertEquals(embeddingProvider.message(), "The OpenAI API key is empty");
    }
}

@test:Config
function testAuthConfigType() returns error? {
    // `AuthConfig` is public, so callers can keep the authentication configuration in their own variables, and it
    // is `anydata`, so it can be `configurable`.
    AuthConfig[] configs = [AUTH_API_KEY, {apiKey: AUTH_API_KEY}, {token: "access-token"},
        workloadIdentityConfig("wif-auth-config-type")];
    foreach AuthConfig config in configs {
        test:assertTrue(config is anydata);
        ModelProvider _ = check new (config, GPT_4_1, authServiceUrl("auth-config-type"));
    }
}

@test:Config
function testEmbeddingProviderStringApiKeyAuth() returns error? {
    string testId = "embeddings-string-api-key";
    EmbeddingProvider provider = check new (AUTH_API_KEY, TEXT_EMBEDDING_3_SMALL, authServiceUrl(testId));
    _ = check provider->embed(<ai:TextChunk>{content: "Hello"});
    _ = check provider->batchEmbed([<ai:TextChunk>{content: "Hello"}, <ai:TextChunk>{content: "World"}]);
    check assertAuthHeaders(testId, ["embed", "batchEmbed"], string `Bearer ${AUTH_API_KEY}`);
}

@test:Config
function testEmbeddingProviderApiKeyConfigWithOrganizationAndProject() returns error? {
    string testId = "embeddings-org-project";
    EmbeddingProvider provider = check new ({apiKey: AUTH_API_KEY, organization: ORGANIZATION_ID,
        project: PROJECT_ID}, TEXT_EMBEDDING_3_SMALL, authServiceUrl(testId));
    _ = check provider->embed(<ai:TextChunk>{content: "Hello"});
    _ = check provider->batchEmbed([<ai:TextChunk>{content: "Hello"}, <ai:TextChunk>{content: "World"}]);
    check assertAuthHeaders(testId, ["embed", "batchEmbed"], string `Bearer ${AUTH_API_KEY}`, ORGANIZATION_ID,
        PROJECT_ID);
}

// ---------------------------------------------------------------------------------------------------------------
// Workload Identity Federation
// ---------------------------------------------------------------------------------------------------------------

@test:Config
function testWorkloadIdentityAuth() returns error? {
    string testId = "wif-chat-completions";
    check callChatAndGenerate(check new (workloadIdentityConfig(testId), GPT_4_1, authServiceUrl(testId)));
    // One exchange; the access token is reused for the second request.
    map<json>[] requests = getTokenExchangeRequests(testId);
    test:assertEquals(requests.length(), 1);
    assertTokenExchangeRequest(requests[0]);
    check assertAuthHeaders(testId, ["chat", "generate"], string `Bearer wif-access-token-${testId}-1`);
}

@test:Config
function testWorkloadIdentityAuthWithResponsesApiAndIdToken() returns error? {
    string testId = "wif-responses";
    check callChatAndGenerate(check new (workloadIdentityConfig(testId, identityTokenType = ID_TOKEN), GPT_4O,
        authServiceUrl(testId), apiType = RESPONSES));
    map<json>[] requests = getTokenExchangeRequests(testId);
    test:assertEquals(requests.length(), 1);
    assertTokenExchangeRequest(requests[0], ID_TOKEN);
    check assertAuthHeaders(testId, ["chat", "generate"], string `Bearer wif-access-token-${testId}-1`);
}

@test:Config
function testWorkloadIdentityAuthWithEmbeddingProvider() returns error? {
    string testId = "wif-embeddings";
    EmbeddingProvider provider = check new (workloadIdentityConfig(testId), TEXT_EMBEDDING_3_SMALL,
        authServiceUrl(testId));
    _ = check provider->embed(<ai:TextChunk>{content: "Hello"});
    _ = check provider->batchEmbed([<ai:TextChunk>{content: "Hello"}, <ai:TextChunk>{content: "World"}]);
    test:assertEquals(getTokenExchangeRequests(testId).length(), 1);
    check assertAuthHeaders(testId, ["embed", "batchEmbed"], string `Bearer wif-access-token-${testId}-1`);
}

@test:Config
function testWorkloadIdentityConcurrentRequestsExchangeOnce() returns error? {
    string testId = "wif-concurrent";
    ModelProvider provider = check new (workloadIdentityConfig(testId), GPT_4_1, authServiceUrl(testId));
    foreach ai:ChatAssistantMessage|ai:Error result in chatConcurrently(provider, 10) {
        _ = check result;
    }
    test:assertEquals(getTokenExchangeRequests(testId).length(), 1);
}

@test:Config
function testWorkloadIdentityReusesShortLivedAccessToken() returns error? {
    string testId = "wif-short-lived";
    // A 100-second access token is inside the 120-second refresh buffer from the start. It is refreshed halfway
    // through its lifetime instead, so back-to-back requests share one exchange.
    ModelProvider provider = check new (workloadIdentityConfig(testId, expiresIn = 100), GPT_4_1,
        authServiceUrl(testId));
    check callChatAndGenerate(provider);
    test:assertEquals(getTokenExchangeRequests(testId).length(), 1);
}

@test:Config
function testWorkloadIdentityRefreshesAccessTokenBeforeExpiry() returns error? {
    string testId = "wif-refresh";
    // A 6-second access token is refreshed after 3 seconds, halfway through its lifetime.
    ModelProvider provider = check new (workloadIdentityConfig(testId, expiresIn = 6), GPT_4_1,
        authServiceUrl(testId));
    _ = check provider->chat([{role: ai:USER, content: "Hi"}]);
    runtime:sleep(3.5);
    int _ = check provider->generate(`Pick a number`);
    test:assertEquals(getTokenExchangeRequests(testId).length(), 2);
    check assertAuthHeaders(testId, ["chat"], string `Bearer wif-access-token-${testId}-1`);
    check assertAuthHeaders(testId, ["generate"], string `Bearer wif-access-token-${testId}-2`);
}

@test:Config
function testWorkloadIdentityUsesCachedTokenWhenRefreshFails() returns error? {
    string testId = "wif-refresh-fails";
    // A 6-second access token is refreshed after 3 seconds, and used until 4.5 seconds if the refresh fails.
    // The first exchange succeeds and the rest fail, so the request at 3.5 seconds uses the cached token.
    ModelProvider provider = check new (workloadIdentityConfig(testId, expiresIn = 6, failAfter = 1), GPT_4_1,
        authServiceUrl(testId));
    _ = check provider->chat([{role: ai:USER, content: "Hi"}]);
    runtime:sleep(3.5);
    int _ = check provider->generate(`Pick a number`);
    test:assertEquals(getTokenExchangeRequests(testId).length(), 2);
    check assertAuthHeaders(testId, ["generate"], string `Bearer wif-access-token-${testId}-1`);
}

@test:Config
function testWorkloadIdentityRechecksExpiryAfterRefreshFails() returns error? {
    string testId = "wif-refresh-fails-slowly";
    // A 6-second access token may be used until 4.5 seconds if a refresh fails. The refresh starts at 3.5 seconds
    // and fails 2 seconds later, after that point, so the cached token must not be used.
    ModelProvider provider = check new (workloadIdentityConfig(testId, expiresIn = 6, failAfter = 1, failDelay = 2),
        GPT_4_1, authServiceUrl(testId));
    _ = check provider->chat([{role: ai:USER, content: "Hi"}]);
    runtime:sleep(3.5);
    ai:ChatAssistantMessage|ai:Error result = provider->chat([{role: ai:USER, content: "Hi"}]);
    if result !is ai:LlmError {
        test:assertFail("Expected an ai:LlmError once the access token is inside the expiry buffer");
    }
    test:assertEquals(getTokenExchangeRequests(testId).length(), 2);
}

@test:Config
function testWorkloadIdentityDoesNotRetryTokenExchange() returns error? {
    string testId = "wif-no-retry";
    // The retry configuration applies only to requests to the OpenAI API, not to the token exchange.
    ModelProvider provider = check new (workloadIdentityConfig(testId, failAfter = -1), GPT_4_1,
        authServiceUrl(testId), retryConfig = {count: 3, interval: 0.1, statusCodes: [401]});
    ai:ChatAssistantMessage|ai:Error result = provider->chat([{role: ai:USER, content: "Hi"}]);
    if result !is ai:LlmError {
        test:assertFail("Expected an ai:LlmError");
    }
    test:assertEquals(getTokenExchangeRequests(testId).length(), 1);
}

@test:Config
function testWorkloadIdentityStopsExchangingAfterRejection() returns error? {
    string testId = "wif-rejected";
    // A rejected identity token cannot succeed later, so concurrent and later requests return the same error
    // without calling the token endpoint again.
    ModelProvider provider = check new (workloadIdentityConfig(testId, failAfter = -1, failDelay = 0.5), GPT_4_1,
        authServiceUrl(testId));
    foreach ai:ChatAssistantMessage|ai:Error result in chatConcurrently(provider, 10) {
        if result !is ai:LlmError {
            test:assertFail("Expected an ai:LlmError");
        }
        test:assertTrue(result.message().includes("Create a new provider with a new identity token"),
            result.message());
    }
    runtime:sleep(5.5);
    int|ai:Error later = provider->generate(`Pick a number`);
    if later !is ai:LlmError {
        test:assertFail("Expected an ai:LlmError after the backoff period");
    }
    test:assertEquals(getTokenExchangeRequests(testId).length(), 1);
}

@test:Config
function testWorkloadIdentityBacksOffAfterFailedRefresh() returns error? {
    string testId = "wif-backoff";
    // An 8-second access token is refreshed after 4 seconds, and used until 6 seconds if the refresh fails. The
    // token endpoint is unavailable after the first exchange and takes 0.5 seconds to fail.
    ModelProvider provider = check new (workloadIdentityConfig(testId, expiresIn = 8, failAfter = 1,
        failDelay = 0.5, unavailable = true), GPT_4_1, authServiceUrl(testId));
    _ = check provider->chat([{role: ai:USER, content: "Hi"}]);
    runtime:sleep(4.2);
    // Concurrent requests in the refresh window make one failed refresh between them and use the cached token.
    foreach ai:ChatAssistantMessage|ai:Error result in chatConcurrently(provider, 10) {
        _ = check result;
    }
    test:assertEquals(getTokenExchangeRequests(testId).length(), 2);
    check assertAuthHeaders(testId, ["chat"], string `Bearer wif-access-token-${testId}-1`);
    // Once the cached token is past its fallback window, requests inside the backoff period return the
    // recorded error without calling the token endpoint.
    runtime:sleep(1.5);
    ai:ChatAssistantMessage|ai:Error result = provider->chat([{role: ai:USER, content: "Hi"}]);
    if result !is ai:LlmError {
        test:assertFail("Expected the recorded ai:LlmError inside the backoff period");
    }
    test:assertTrue(result.message().includes("status 503"), result.message());
    test:assertEquals(getTokenExchangeRequests(testId).length(), 2);
}

@test:Config
function testWorkloadIdentityExchangeFailure() returns error? {
    string testId = "wif-exchange-fails";
    ModelProvider provider = check new (workloadIdentityConfig(testId, failAfter = -1), GPT_4_1,
        authServiceUrl(testId));
    ai:ChatAssistantMessage|ai:Error chatResult = provider->chat([{role: ai:USER, content: "Hi"}]);
    if chatResult !is ai:Error {
        return error("Expected the chat request to fail");
    }
    test:assertTrue(chatResult.message().startsWith(
        "Workload Identity Federation token exchange failed with status 401"), chatResult.message());
    int|ai:Error generateResult = provider->generate(`Pick a number`);
    if generateResult !is ai:Error {
        return error("Expected the generate request to fail");
    }
    test:assertTrue(generateResult.message().includes("status 401"), generateResult.message());

    EmbeddingProvider embeddingProvider = check new (workloadIdentityConfig(testId, failAfter = -1),
        TEXT_EMBEDDING_3_SMALL, authServiceUrl(testId));
    ai:Embedding|ai:Error embedResult = embeddingProvider->embed(<ai:TextChunk>{content: "Hello"});
    test:assertTrue(embedResult is ai:Error);
    // No request reached the API.
    test:assertTrue(getAuthHeader(testId, "chat", "authorization") is error);
}

@test:Config
function testWorkloadIdentityTokenEndpointUnreachable() returns error? {
    ModelProvider provider = check new ({
        identityProviderId: IDENTITY_PROVIDER_ID,
        serviceAccountId: SERVICE_ACCOUNT_ID,
        identityToken: IDENTITY_TOKEN,
        tokenUrl: "http://localhost:8099/oauth/token"
    }, GPT_4_1, authServiceUrl("wif-unreachable"));
    ai:ChatAssistantMessage|ai:Error result = provider->chat([{role: ai:USER, content: "Hi"}]);
    test:assertTrue(result is ai:LlmConnectionError);
}

@test:Config
function testWorkloadIdentityDefaultTokenUrl() {
    WorkloadIdentityConfig config = {
        identityProviderId: IDENTITY_PROVIDER_ID,
        serviceAccountId: SERVICE_ACCOUNT_ID,
        identityToken: IDENTITY_TOKEN
    };
    test:assertEquals(config.tokenUrl, "https://auth.openai.com/oauth/token");
    test:assertEquals(config.identityTokenType, JWT);
}
