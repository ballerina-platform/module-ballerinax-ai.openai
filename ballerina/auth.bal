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
import ballerina/time;
import ballerinax/openai.chat;
import ballerinax/openai.embeddings;
import ballerinax/openai.responses;

const DEFAULT_TOKEN_URL = "https://auth.openai.com/oauth/token";
const TOKEN_EXCHANGE_GRANT_TYPE = "urn:ietf:params:oauth:grant-type:token-exchange";
const ORGANIZATION_HEADER = "openai-organization";
const PROJECT_HEADER = "openai-project";

// A cached access token is refreshed this many seconds before it expires, or halfway through its lifetime if
// that is sooner, so a short-lived access token is not exchanged again on every request.
const decimal TOKEN_REFRESH_BUFFER_SECONDS = 120;
// If a refresh fails, the cached access token is still used until this many seconds before it expires, or until
// three quarters of its lifetime if that is sooner.
const decimal TOKEN_EXPIRY_BUFFER_SECONDS = 30;
// After a token exchange fails with an error that may be temporary, the token endpoint is not called again for
// this many seconds, so concurrent requests and an outage do not call it at request rate.
const decimal TOKEN_EXCHANGE_BACKOFF_SECONDS = 5;

# Authentication with an OpenAI API key.
# See https://developers.openai.com/api/reference/overview
public type ApiKeyConfig record {|
    # The OpenAI API key, sent in the `Authorization: Bearer` header
    @display {label: "API Key"}
    string apiKey;
    # The organization to run requests in (`org-...`), sent in the `OpenAI-Organization` header. Usage is
    # counted for this organization. Needed when the key's user belongs to more than one organization
    @display {label: "Organization ID"}
    string organization?;
    # The project to run requests in (`proj_...`), sent in the `OpenAI-Project` header. Usage is counted for
    # this project. Needed when a legacy user API key accesses projects
    @display {label: "Project ID"}
    string project?;
|};

# The type of the identity token exchanged with Workload Identity Federation.
public enum SubjectTokenType {
    # A JWT, such as a SPIFFE JWT-SVID or a Kubernetes service account token
    JWT = "urn:ietf:params:oauth:token-type:jwt",
    # An OpenID Connect ID token
    ID_TOKEN = "urn:ietf:params:oauth:token-type:id_token"
}

# Authentication with Workload Identity Federation. The connector exchanges an identity token issued by your
# identity provider (for example, AWS, Google Cloud, Microsoft Entra ID, Kubernetes, or GitHub Actions) for a
# short-lived OpenAI access token, and reuses the access token until it is about to expire.
# See https://developers.openai.com/api/docs/guides/workload-identity-federation
public type WorkloadIdentityConfig record {|
    # The ID of the OpenAI workload identity provider that trusts your identity provider
    @display {label: "Identity Provider ID"}
    string identityProviderId;
    # The ID of the OpenAI service account that the access token acts as
    @display {label: "Service Account ID"}
    string serviceAccountId;
    # The identity token (JWT) issued by your identity provider. The same identity token is used for every
    # exchange, and an access token never outlives the identity token it was exchanged for, so once the identity
    # token expires, create a new model provider with a new identity token
    @display {label: "Identity Token"}
    string identityToken;
    # The type of the identity token
    @display {label: "Identity Token Type"}
    SubjectTokenType identityTokenType = JWT;
    # The URL of the OpenAI token exchange endpoint
    @display {label: "Token URL"}
    string tokenUrl = DEFAULT_TOKEN_URL;
|};

# How the model or embedding provider authenticates with the OpenAI API: an API key (`string`), an API key with an
# organization or project (`ApiKeyConfig`), Workload Identity Federation (`WorkloadIdentityConfig`), or an access
# token (`http:BearerTokenConfig`), which is not refreshed. The record types come first so that the connection form
# offers a record editor for them.
public type AuthConfig ApiKeyConfig|WorkloadIdentityConfig|http:BearerTokenConfig|string;

# A client of one of the OpenAI connectors.
type ConnectorClient chat:Client|responses:Client|embeddings:Client;

# Creates a connector client that sends the given token in the `Authorization: Bearer` header.
type ClientFactory isolated function (string token) returns ConnectorClient|ai:Error;

# Provides the connector client for each request to the OpenAI API. The token is set in the `auth` configuration of
# the client, so a token that changes needs a new client.
type ClientProvider isolated object {
    # Returns the connector client to send a request with.
    #
    # + return - The connector client, or an `ai:Error` if it could not be obtained
    isolated function getClient() returns ConnectorClient|ai:Error;
};

# Provides a client created once, for an API key or an access token that does not change.
isolated class StaticClientProvider {
    *ClientProvider;
    private final ConnectorClient connectorClient;

    isolated function init(ConnectorClient connectorClient) {
        self.connectorClient = connectorClient;
    }

    isolated function getClient() returns ConnectorClient|ai:Error => self.connectorClient;
}

# The fields of the token exchange request that do not change between exchanges.
type TokenExchangeParams record {|
    # The type of the identity token
    SubjectTokenType subject_token_type;
    # The ID of the OpenAI workload identity provider
    string identity_provider_id;
    # The ID of the OpenAI service account that the access token acts as
    string service_account_id;
|};

# The response of the token exchange endpoint.
type TokenExchangeResponse record {
    # The short-lived OpenAI access token
    string access_token;
    # The number of seconds until the access token expires
    int expires_in;
};

# Returns the current monotonic time, in seconds.
type Clock isolated function () returns decimal;

# The timing settings of `WorkloadIdentityClientProvider`. Every provider uses the defaults. Tests set a clock that
# they move forward, so they check the timing without waiting.
type WorkloadIdentityTimings record {|
    # A cached access token is refreshed this many seconds before it expires, or halfway through its lifetime if
    # that is sooner
    decimal refreshBufferSeconds = TOKEN_REFRESH_BUFFER_SECONDS;
    # If a refresh fails, the cached access token is used until this many seconds before it expires, or until
    # three quarters of its lifetime if that is sooner
    decimal expiryBufferSeconds = TOKEN_EXPIRY_BUFFER_SECONDS;
    # After an exchange fails with an error that may be temporary, the token endpoint is not called again for
    # this many seconds
    decimal backoffSeconds = TOKEN_EXCHANGE_BACKOFF_SECONDS;
    # Returns the current time
    Clock clock = time:monotonicNow;
|};

# Provides the client for Workload Identity Federation. Exchanges the identity token for an access token, creates a
# connector client that sends the access token, and caches both. Before the access token expires, exchanges the
# identity token again and replaces the client with one that sends the new access token. Requests already sent on
# the previous client are not affected.
isolated class WorkloadIdentityClientProvider {
    *ClientProvider;
    private final http:Client tokenClient;
    private final TokenExchangeParams & readonly exchangeParams;
    private final string identityToken;
    private final ClientFactory clientFactory;
    private final WorkloadIdentityTimings & readonly timings;
    // The connector client that sends the cached access token.
    private ConnectorClient? connectorClient = ();
    // The monotonic time, in seconds, after which the cached access token is refreshed.
    private decimal refreshAt = 0;
    // The monotonic time, in seconds, until which the cached access token is used if a refresh fails.
    private decimal usableUntil = 0;
    // The last failed refresh, returned without calling the token endpoint until `retryAfter`.
    private ai:Error? lastError = ();
    // The monotonic time, in seconds, before which a failed refresh is not tried again.
    private decimal retryAfter = 0;
    // Set when the token endpoint rejects the identity token. The identity token does not change, so no later
    // exchange can succeed, and the token endpoint is not called again.
    private ai:Error? rejectedError = ();

    isolated function init(http:Client tokenClient, TokenExchangeParams & readonly exchangeParams,
            string identityToken, ClientFactory clientFactory, WorkloadIdentityTimings & readonly timings = {}) {
        self.tokenClient = tokenClient;
        self.exchangeParams = exchangeParams;
        self.identityToken = identityToken;
        self.clientFactory = clientFactory;
        self.timings = timings;
    }

    # Returns the client for the cached access token. When the cached access token is about to expire, exchanges
    # the identity token for a new one and creates a client for it. The exchange runs inside the lock so that
    # concurrent requests trigger only one exchange.
    #
    # While an exchange runs, every other request through this provider waits for it, even when the cached access
    # token is still valid. An exchange happens about once per access token lifetime, and if the token endpoint
    # does not respond, the wait lasts at most the `timeout` of the connection configuration (60 seconds by
    # default), because the exchange is not retried.
    #
    # A failed refresh is recorded, so requests queued behind it do not call the token endpoint again. They use
    # the client for the cached access token while the access token is still valid, or return the recorded error.
    # After an error that may be temporary, the refresh is tried again after the backoff period. After the token
    # endpoint rejects the identity token, it is never tried again.
    #
    # + return - The connector client, or an `ai:Error` if the refresh fails
    isolated function getClient() returns ConnectorClient|ai:Error {
        WorkloadIdentityTimings & readonly timings = self.timings;
        Clock clock = timings.clock;
        ClientFactory clientFactory = self.clientFactory;
        lock {
            decimal now = clock();
            ConnectorClient? cachedClient = self.connectorClient;
            if cachedClient !is () && now < self.refreshAt {
                return cachedClient;
            }
            ai:Error? recordedError = self.rejectedError ?: (now < self.retryAfter ? self.lastError : ());
            if recordedError is ai:Error {
                return cachedClient !is () && now < self.usableUntil ? cachedClient : recordedError;
            }
            TokenExchangeResponse|ai:Error response =
                exchangeIdentityToken(self.tokenClient, self.exchangeParams, self.identityToken);
            ConnectorClient|ai:Error newClient = response is ai:Error ? response
                : clientFactory(response.access_token);
            if response is ai:Error || newClient is ai:Error {
                // The exchange may have taken a while to fail, so use the current time from here on.
                decimal failedAt = clock();
                ai:Error refreshError = response is ai:Error ? response : <ai:Error>newClient;
                if isIdentityTokenRejected(refreshError) {
                    refreshError = error ai:LlmError(string `${refreshError.message()}. The identity token is not `
                        + "exchanged again. Create a new provider with a new identity token.", refreshError);
                    self.rejectedError = refreshError;
                } else {
                    self.lastError = refreshError;
                    self.retryAfter = failedAt + timings.backoffSeconds;
                }
                // Keep using the client for the cached access token while the access token is still valid.
                return cachedClient !is () && failedAt < self.usableUntil ? cachedClient : refreshError;
            }
            decimal expiresIn = <decimal>response.expires_in;
            self.connectorClient = newClient;
            self.refreshAt = now + expiresIn - decimal:min(timings.refreshBufferSeconds, expiresIn / 2);
            self.usableUntil = now + expiresIn - decimal:min(timings.expiryBufferSeconds, expiresIn / 4);
            self.lastError = ();
            self.retryAfter = 0;
            return newClient;
        }
    }
}

# Returns the headers to send with every request, other than `Authorization`, which the connector client sends.
#
# + auth - The authentication configuration
# + return - The `OpenAI-Organization` and `OpenAI-Project` headers of an `ApiKeyConfig`, or no headers. An empty or
# blank organization or project is not sent
isolated function getAuthHeaders(AuthConfig auth) returns map<string> & readonly {
    if auth !is ApiKeyConfig {
        return {};
    }
    map<string> headers = {};
    string organization = (auth.organization ?: "").trim();
    if organization != "" {
        headers[ORGANIZATION_HEADER] = organization;
    }
    string project = (auth.project ?: "").trim();
    if project != "" {
        headers[PROJECT_HEADER] = project;
    }
    return headers.cloneReadOnly();
}

# Creates the client provider for the given authentication configuration.
#
# + auth - The authentication configuration. A `string` is an OpenAI API key
# + clientFactory - Creates a connector client that sends a given token
# + tokenClientConfig - The HTTP client configuration for the token exchange endpoint
# + return - The client provider, or an `ai:Error` if it could not be created
isolated function createClientProvider(AuthConfig auth, ClientFactory clientFactory,
        http:ClientConfiguration tokenClientConfig) returns ClientProvider|ai:Error {
    if auth is string {
        // Sent in the `Authorization: Bearer` header, as in 1.x, so existing users see no change on the wire.
        return new StaticClientProvider(check clientFactory(check validateToken(auth, "The OpenAI API key is empty")));
    }
    if auth is ApiKeyConfig {
        return new StaticClientProvider(
            check clientFactory(check validateToken(auth.apiKey, "The OpenAI API key is empty")));
    }
    if auth is http:BearerTokenConfig {
        return new StaticClientProvider(
            check clientFactory(check validateToken(auth.token, "The OpenAI access token is empty")));
    }

    // The access token is obtained on the first request. Create a client now as well, so that an invalid
    // connection configuration fails here, as it does for an API key.
    _ = check clientFactory("");
    http:Client|error tokenClient = new (auth.tokenUrl, tokenClientConfig);
    if tokenClient is error {
        return error ai:Error("Failed to initialize the Workload Identity Federation token client", tokenClient);
    }
    TokenExchangeParams & readonly exchangeParams = {
        subject_token_type: auth.identityTokenType,
        identity_provider_id: auth.identityProviderId,
        service_account_id: auth.serviceAccountId
    };
    return new WorkloadIdentityClientProvider(tokenClient, exchangeParams, auth.identityToken, clientFactory);
}

# Exchanges the identity token for a short-lived OpenAI access token.
#
# + tokenClient - The HTTP client for the token exchange endpoint
# + exchangeParams - The fields of the token exchange request that do not change between exchanges
# + identityToken - The identity token
# + return - The token exchange response, or an `ai:Error` if the exchange fails
isolated function exchangeIdentityToken(http:Client tokenClient, TokenExchangeParams & readonly exchangeParams,
        string identityToken) returns TokenExchangeResponse|ai:Error {
    // OpenAI's token endpoint takes the token exchange request as a JSON body. See
    // https://developers.openai.com/api/docs/guides/workload-identity-federation
    map<json> request = {
        grant_type: TOKEN_EXCHANGE_GRANT_TYPE,
        subject_token: identityToken.trim(),
        ...exchangeParams
    };
    TokenExchangeResponse|error response = tokenClient->post("", request);
    if response is error {
        if response is http:ApplicationResponseError {
            http:Detail detail = response.detail();
            return error ai:LlmError(string `Workload Identity Federation token exchange failed with status ${
                detail.statusCode}: ${detail.body.toString()}`, response);
        }
        if response is http:ClientConnectorError|http:ResiliencyError|http:SslError {
            return error ai:LlmConnectionError("Error while connecting to the OpenAI token exchange endpoint",
                response);
        }
        return error ai:LlmError("Unexpected response from the OpenAI token exchange endpoint", response);
    }
    if response.expires_in <= 0 {
        // Otherwise the access token would be refreshed on every request, inside the lock.
        return error ai:LlmError(string `The OpenAI token exchange endpoint returned an access token with an invalid `
            + string `lifetime: expires_in is ${response.expires_in}`);
    }
    return response;
}

# Returns whether the token endpoint rejected the identity token, for example because it has expired or does not
# match the workload identity provider or the service account mapping. A 4xx response other than 408 and 429 means
# the same identity token cannot succeed later.
#
# + err - The error returned by the token exchange
# + return - `true` if the identity token was rejected
isolated function isIdentityTokenRejected(ai:Error err) returns boolean {
    error? cause = err.cause();
    if cause !is http:ApplicationResponseError {
        return false;
    }
    int statusCode = cause.detail().statusCode;
    return statusCode >= 400 && statusCode < 500 && statusCode != 408 && statusCode != 429;
}

# Trims an API key or access token, so a value read from a file or an environment variable with a trailing newline
# still works.
#
# + token - The API key or access token
# + emptyMessage - The error message if it is empty
# + return - The trimmed API key or access token, or an `ai:Error` if it is empty
isolated function validateToken(string token, string emptyMessage) returns string|ai:Error {
    string trimmed = token.trim();
    if trimmed == "" {
        return error ai:Error(emptyMessage);
    }
    return trimmed;
}

# Returns the HTTP client configuration for the token exchange endpoint. It keeps the connection settings of the
# connection configuration, such as the timeout, TLS and proxy, but not its retry, circuit breaker and cache
# settings, which are meant for requests to the OpenAI API. The token exchange is not retried, so that a failing
# identity token is not sent again and again.
#
# + connectionConfig - The connection configuration
# + return - The HTTP client configuration for the token exchange endpoint
isolated function toTokenClientConfig(ConnectionConfig connectionConfig) returns http:ClientConfiguration => {
    httpVersion: connectionConfig.httpVersion,
    http1Settings: connectionConfig.http1Settings ?: {},
    http2Settings: connectionConfig.http2Settings ?: {},
    timeout: connectionConfig.timeout,
    poolConfig: connectionConfig.poolConfig,
    cache: {enabled: false},
    secureSocket: connectionConfig.secureSocket,
    proxy: connectionConfig.proxy
};
