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

const DEFAULT_TOKEN_URL = "https://auth.openai.com/oauth/token";
const TOKEN_EXCHANGE_GRANT_TYPE = "urn:ietf:params:oauth:grant-type:token-exchange";
const AUTHORIZATION_HEADER = "authorization";
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

# Provides the authentication headers for each request to the OpenAI API.
type AuthProvider isolated object {
    # Returns the authentication headers to send with a request.
    #
    # + return - The authentication headers, or an `ai:Error` if they could not be obtained
    isolated function getHeaders() returns map<string> & readonly|ai:Error;
};

# Provides headers that do not change, for API key and bearer token authentication.
isolated class StaticAuthProvider {
    *AuthProvider;
    private final map<string> & readonly headers;

    isolated function init(map<string> & readonly headers) {
        self.headers = headers;
    }

    isolated function getHeaders() returns map<string> & readonly|ai:Error => self.headers;
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

# Provides the headers for Workload Identity Federation. Exchanges the identity token for an access token,
# caches the access token, and exchanges again before it expires.
isolated class WorkloadIdentityAuthProvider {
    *AuthProvider;
    private final http:Client tokenClient;
    private final TokenExchangeParams & readonly exchangeParams;
    private final string identityToken;
    private string? accessToken = ();
    // The monotonic time, in seconds, after which the cached access token is refreshed.
    private decimal refreshAt = 0;
    // The monotonic time, in seconds, until which the cached access token is used if a refresh fails.
    private decimal usableUntil = 0;
    // The last failed exchange, returned without calling the token endpoint until `retryAfter`.
    private ai:Error? lastError = ();
    // The monotonic time, in seconds, before which a failed exchange is not tried again.
    private decimal retryAfter = 0;
    // Set when the token endpoint rejects the identity token. The identity token does not change, so no later
    // exchange can succeed, and the token endpoint is not called again.
    private ai:Error? rejectedError = ();

    isolated function init(http:Client tokenClient, TokenExchangeParams & readonly exchangeParams,
            string identityToken) {
        self.tokenClient = tokenClient;
        self.exchangeParams = exchangeParams;
        self.identityToken = identityToken;
    }

    isolated function getHeaders() returns map<string> & readonly|ai:Error {
        string accessToken = check self.getAccessToken();
        return {[AUTHORIZATION_HEADER]: string `Bearer ${accessToken}`};
    }

    # Returns the cached access token, exchanging the identity token for a new one when the cached access token
    # is about to expire. The exchange runs inside the lock so that concurrent requests trigger only one exchange.
    #
    # A failed exchange is recorded, so requests queued behind it do not call the token endpoint again. They use
    # the cached access token while it is still valid, or return the recorded error. After an error that may be
    # temporary, the exchange is tried again after `TOKEN_EXCHANGE_BACKOFF_SECONDS`. After the token endpoint
    # rejects the identity token, it is never tried again.
    #
    # + return - The access token, or an `ai:Error` if the exchange fails
    isolated function getAccessToken() returns string|ai:Error {
        lock {
            decimal now = time:monotonicNow();
            string? cachedToken = self.accessToken;
            if cachedToken is string && now < self.refreshAt {
                return cachedToken;
            }
            ai:Error? recordedError = self.rejectedError ?: (now < self.retryAfter ? self.lastError : ());
            if recordedError is ai:Error {
                return cachedToken is string && now < self.usableUntil ? cachedToken : recordedError;
            }
            TokenExchangeResponse|ai:Error response =
                exchangeIdentityToken(self.tokenClient, self.exchangeParams, self.identityToken);
            if response is ai:Error {
                // The exchange may have taken a while to fail, so use the current time from here on.
                decimal failedAt = time:monotonicNow();
                ai:Error exchangeError = response;
                if isIdentityTokenRejected(response) {
                    exchangeError = error ai:LlmError(string `${response.message()}. The identity token is not `
                        + "exchanged again. Create a new provider with a new identity token.", response);
                    self.rejectedError = exchangeError;
                } else {
                    self.lastError = exchangeError;
                    self.retryAfter = failedAt + TOKEN_EXCHANGE_BACKOFF_SECONDS;
                }
                // Keep using the cached access token while it is still valid.
                return cachedToken is string && failedAt < self.usableUntil ? cachedToken : exchangeError;
            }
            decimal expiresIn = <decimal>response.expires_in;
            self.accessToken = response.access_token;
            self.refreshAt = now + expiresIn - decimal:min(TOKEN_REFRESH_BUFFER_SECONDS, expiresIn / 2);
            self.usableUntil = now + expiresIn - decimal:min(TOKEN_EXPIRY_BUFFER_SECONDS, expiresIn / 4);
            self.lastError = ();
            self.retryAfter = 0;
            return response.access_token;
        }
    }
}

# Creates the authentication provider for the given authentication configuration.
#
# + auth - The authentication configuration. A `string` is an OpenAI API key
# + clientConfig - The HTTP client configuration, used for the token exchange endpoint without its retry
# configuration
# + return - The authentication provider, or an `ai:Error` if it could not be created
isolated function createAuthProvider(AuthConfig auth, http:ClientConfiguration clientConfig)
        returns AuthProvider|ai:Error {
    if auth is string {
        // Sent in the `Authorization: Bearer` header, as in 1.x, so existing users see no change on the wire.
        return new StaticAuthProvider({[AUTHORIZATION_HEADER]: string `Bearer ${check validateApiKey(auth)}`});
    }
    if auth is ApiKeyConfig {
        map<string> headers = {[AUTHORIZATION_HEADER]: string `Bearer ${check validateApiKey(auth.apiKey)}`};
        string? organization = auth.organization;
        if organization is string {
            headers[ORGANIZATION_HEADER] = organization;
        }
        string? project = auth.project;
        if project is string {
            headers[PROJECT_HEADER] = project;
        }
        return new StaticAuthProvider(headers.cloneReadOnly());
    }
    if auth is http:BearerTokenConfig {
        return new StaticAuthProvider({[AUTHORIZATION_HEADER]: string `Bearer ${auth.token}`});
    }

    // The token exchange is not retried, so that a failing identity token is not sent again and again.
    var {retryConfig: _, ...tokenClientConfig} = clientConfig;
    http:Client|error tokenClient = new (auth.tokenUrl, {...tokenClientConfig});
    if tokenClient is error {
        return error ai:Error("Failed to initialize the Workload Identity Federation token client", tokenClient);
    }
    TokenExchangeParams & readonly exchangeParams = {
        subject_token_type: auth.identityTokenType,
        identity_provider_id: auth.identityProviderId,
        service_account_id: auth.serviceAccountId
    };
    return new WorkloadIdentityAuthProvider(tokenClient, exchangeParams, auth.identityToken);
}

# Exchanges the identity token for a short-lived OpenAI access token.
#
# + tokenClient - The HTTP client for the token exchange endpoint
# + exchangeParams - The fields of the token exchange request that do not change between exchanges
# + identityToken - The identity token
# + return - The token exchange response, or an `ai:Error` if the exchange fails
isolated function exchangeIdentityToken(http:Client tokenClient, TokenExchangeParams & readonly exchangeParams,
        string identityToken) returns TokenExchangeResponse|ai:Error {
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

# Trims an API key, so a key read from a file or an environment variable with a trailing newline still works.
#
# + apiKey - The API key
# + return - The trimmed API key, or an `ai:Error` if it is empty
isolated function validateApiKey(string apiKey) returns string|ai:Error {
    string trimmed = apiKey.trim();
    if trimmed == "" {
        return error ai:Error("The OpenAI API key is empty");
    }
    return trimmed;
}

# Converts the connection configuration to an HTTP client configuration, used for the token exchange endpoint.
#
# + connectionConfig - The connection configuration
# + return - The HTTP client configuration
isolated function toHttpClientConfig(ConnectionConfig connectionConfig) returns http:ClientConfiguration => {
    httpVersion: connectionConfig.httpVersion,
    http1Settings: connectionConfig.http1Settings ?: {},
    http2Settings: connectionConfig.http2Settings ?: {},
    timeout: connectionConfig.timeout,
    forwarded: connectionConfig.forwarded,
    poolConfig: connectionConfig.poolConfig,
    cache: connectionConfig.cache ?: {},
    compression: connectionConfig.compression,
    circuitBreaker: connectionConfig.circuitBreaker,
    retryConfig: connectionConfig.retryConfig,
    responseLimits: connectionConfig.responseLimits ?: {},
    secureSocket: connectionConfig.secureSocket,
    proxy: connectionConfig.proxy,
    validation: connectionConfig.validation
};
