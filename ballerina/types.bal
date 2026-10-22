// Copyright (c) 2025 WSO2 LLC (http://www.wso2.com).
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

import ballerina/http;

# Configurations for controlling the behaviours when communicating with a remote HTTP endpoint.
@display {label: "Connection Configuration"}
public type ConnectionConfig record {|

    # The HTTP version understood by the client
    @display {label: "HTTP Version"}
    http:HttpVersion httpVersion = http:HTTP_2_0;

    # Configurations related to HTTP/1.x protocol
    @display {label: "HTTP1 Settings"}
    http:ClientHttp1Settings http1Settings?;

    # Configurations related to HTTP/2 protocol
    @display {label: "HTTP2 Settings"}
    http:ClientHttp2Settings http2Settings?;

    # The maximum time to wait (in seconds) for a response before closing the connection
    @display {label: "Timeout"}
    decimal timeout = 60;

    # The choice of setting `forwarded`/`x-forwarded` header
    @display {label: "Forwarded"}
    string forwarded = "disable";

    # Configurations associated with request pooling
    @display {label: "Pool Configuration"}
    http:PoolConfiguration poolConfig?;

    # HTTP caching related configurations
    @display {label: "Cache Configuration"}
    http:CacheConfig cache?;

    # Specifies the way of handling compression (`accept-encoding`) header
    @display {label: "Compression"}
    http:Compression compression = http:COMPRESSION_AUTO;

    # Configurations associated with the behaviour of the Circuit Breaker
    @display {label: "Circuit Breaker Configuration"}
    http:CircuitBreakerConfig circuitBreaker?;

    # Configurations associated with retrying
    @display {label: "Retry Configuration"}
    http:RetryConfig retryConfig?;

    # Configurations associated with inbound response size limits
    @display {label: "Response Limit Configuration"}
    http:ResponseLimitConfigs responseLimits?;

    # SSL/TLS-related options
    @display {label: "Secure Socket Configuration"}
    http:ClientSecureSocket secureSocket?;

    # Proxy server related options
    @display {label: "Proxy Configuration"}
    http:ProxyConfig proxy?;

    # Enables the inbound payload validation functionality which provided by the constraint package. Enabled by default
    @display {label: "Payload Validation"}
    boolean validation = true;
|};

# Defines which OpenAI API endpoint to use for model interactions.
@display {label: "OpenAI API Type"}
public enum ApiType {
    # Use the OpenAI Chat Completions API (`/chat/completions`)
    CHAT_COMPLETIONS = "chat_completions",
    # Use the OpenAI Responses API (`/responses`)
    RESPONSES = "responses"
}

# Constrains the effort spent on reasoning for reasoning-capable models.
# Supported by both the Chat Completions API (`reasoning_effort`) and the Responses API (`reasoning.effort`).
# Reducing reasoning effort can result in faster responses and fewer tokens used on reasoning.
#
# Each model accepts only a subset of these values; for example, `gpt-5` accepts
# `minimal`, `low`, `medium` and `high`, while `gpt-5-pro` accepts only `high`.
# The value is validated against the selected model when the provider is initialized.
#
# Note: the `max` effort accepted by the `gpt-5.6` family cannot be represented yet, because
# `ballerinax/openai.chat` and `ballerinax/openai.responses` declare a closed `ReasoningEffort`
# union without it. Add `MAX` here once those connectors are regenerated.
@display {label: "Reasoning Effort"}
public enum ReasoningEffort {
    NONE = "none",
    MINIMAL = "minimal",
    LOW = "low",
    MEDIUM = "medium",
    HIGH = "high",
    XHIGH = "xhigh"
}

# Model types for OpenAI
@display {label: "OpenAI Model Names"}
public enum OPEN_AI_MODEL_NAMES {
    GPT_4O = "gpt-4o",
    GPT_4O_2024_11_20 = "gpt-4o-2024-11-20",
    GPT_4O_2024_08_06 = "gpt-4o-2024-08-06",
    GPT_4O_MINI = "gpt-4o-mini",
    GPT_4O_MINI_2024_07_18 = "gpt-4o-mini-2024-07-18",
    O3 = "o3",
    O3_PRO = "o3-pro",
    GPT_4_1_2025_04_14 = "gpt-4.1-2025-04-14",
    GPT_4_1 = "gpt-4.1",
    GPT_4_1_MINI_2025_04_14 = "gpt-4.1-mini-2025-04-14",
    GPT_4_1_MINI = "gpt-4.1-mini",
    GPT_5 = "gpt-5",
    GPT_5_MINI = "gpt-5-mini",
    GPT_5_NANO = "gpt-5-nano",
    GPT_5_PRO = "gpt-5-pro",
    GPT_5_1 = "gpt-5.1",
    GPT_5_2 = "gpt-5.2",
    GPT_5_2_PRO = "gpt-5.2-pro",
    GPT_5_3_CODEX = "gpt-5.3-codex",
    GPT_5_4 = "gpt-5.4",
    GPT_5_4_MINI = "gpt-5.4-mini",
    GPT_5_4_NANO = "gpt-5.4-nano",
    GPT_5_4_PRO = "gpt-5.4-pro",
    GPT_5_5 = "gpt-5.5",
    GPT_5_5_PRO = "gpt-5.5-pro",
    # Alias that always routes to the latest `gpt-5.6-sol` snapshot.
    GPT_5_6 = "gpt-5.6",
    GPT_5_6_SOL = "gpt-5.6-sol",
    GPT_5_6_TERRA = "gpt-5.6-terra",
    GPT_5_6_LUNA = "gpt-5.6-luna"
}

@display {label: "OpenAI Embedding Model Names"}
public enum OPEN_AI_EMBEDDING_MODEL_NAMES {
    TEXT_EMBEDDING_3_SMALL = "text-embedding-3-small",
    TEXT_EMBEDDING_3_LARGE = "text-embedding-3-large",
    TEXT_EMBEDDING_ADA_002 = "text-embedding-ada-002"
}
