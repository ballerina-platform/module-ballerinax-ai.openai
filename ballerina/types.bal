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
import ballerina/ai;
import ballerinax/openai.responses as responses;

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

# Defines which OpenAI API endpoint to use for model interactions (internal).
enum ApiType {
    CHAT_COMPLETIONS = "chat_completions",
    RESPONSES = "responses"
}

# Model types for OpenAI
@display {label: "OpenAI Model Names"}
public enum OPEN_AI_MODEL_NAMES {
    GPT_4O = "gpt-4o",
    GPT_4O_2024_11_20 = "gpt-4o-2024-11-20",
    GPT_4O_2024_08_06 = "gpt-4o-2024-08-06",
    GPT_4O_2024_05_13 = "gpt-4o-2024-05-13",
    GPT_4O_MINI = "gpt-4o-mini",
    GPT_4O_MINI_2024_07_18 = "gpt-4o-mini-2024-07-18",
    GPT_4_TURBO = "gpt-4-turbo",
    GPT_4_TURBO_2024_04_09 = "gpt-4-turbo-2024-04-09",
    GPT_4_0125_PREVIEW = "gpt-4-0125-preview",
    GPT_4_TURBO_PREVIEW = "gpt-4-turbo-preview",
    GPT_4_1106_PREVIEW = "gpt-4-1106-preview",
    GPT_4_0613 = "gpt-4-0613",
    O1 = "o1",
    O1_2024_12_17 = "o1-2024-12-17",
    O1_PRO_2025_03_19 = "o1-pro-2025-03-19",
    O1_PRO = "o1-pro",
    O1_MINI = "o1-mini",
    O3 = "o3",
    O3_MINI = "o3-mini",
    O3_PRO = "o3-pro",
    O4_MINI = "o4-mini",
    GPT_3_5_TURBO = "gpt-3.5-turbo",
    GPT_3_5_TURBO_16K = "gpt-3.5-turbo-16k",
    GPT_3_5_TURBO_1106 = "gpt-3.5-turbo-1106",
    GPT_3_5_TURBO_0125 = "gpt-3.5-turbo-0125",
    GPT_4_1_2025_04_14 = "gpt-4.1-2025-04-14",
    GPT_4_1 = "gpt-4.1",
    GPT_4_1_MINI_2025_04_14 = "gpt-4.1-mini-2025-04-14",
    GPT_4_1_MINI = "gpt-4.1-mini",
    GPT_4_1_NANO = "gpt-4.1-nano",
    GPT_4_1_NANO_2025_04_14 = "gpt-4.1-nano-2025-04-14",
    GPT_5 = "gpt-5",
    GPT_5_MINI = "gpt-5-mini",
    GPT_5_NANO = "gpt-5-nano",
    GPT_5_PRO = "gpt-5-pro",
    GPT_5_CHAT = "gpt-5-chat",
    GPT_5_CODEX = "gpt-5-codex",
    GPT_5_1 = "gpt-5.1",
    GPT_5_1_CHAT = "gpt-5.1-chat",
    GPT_5_1_CODEX = "gpt-5.1-codex",
    GPT_5_1_CODEX_MINI = "gpt-5.1-codex-mini",
    GPT_5_2 = "gpt-5.2",
    GPT_5_2_CHAT = "gpt-5.2-chat",
    GPT_5_2_CODEX = "gpt-5.2-codex",
    GPT_5_2_PRO = "gpt-5.2-pro",
    GPT_5_1_CODEX_MAX = "gpt-5.1-codex-max",
    CHATGPT_4O_LATEST = "chatgpt-4o-latest",
    GPT_4O_AUDIO_PREVIEW = "gpt-4o-audio-preview",
    COMPUTER_USE_PREVIEW = "computer-use-preview",
    CODEX_MINI_LATEST = "codex-mini-latest"
}

@display {label: "OpenAI Embedding Model Names"}
public enum OPEN_AI_EMBEDDING_MODEL_NAMES {
    TEXT_EMBEDDING_3_SMALL = "text-embedding-3-small",
    TEXT_EMBEDDING_3_LARGE = "text-embedding-3-large",
    TEXT_EMBEDDING_ADA_002 = "text-embedding-ada-002"
}

type ToolInfo readonly & record {|
    string toolList;
    string toolIntro;
|};

type LlmChatResponse record {|
    string content;
|};

# Code interpreter tool for OpenAI models.
# Allows the model to execute code in a sandboxed environment during a conversation.
# Ref: https://platform.openai.com/docs/guides/tools/code-interpreter
public type CodeInterpreterTool record {|
    *ai:BuiltInTool;
    # Tool identifier. Always `"code_interpreter"`.
    "code_interpreter" name;
    # Code interpreter configurations
    record {|
        # The container to run the code in. Either a string container ID or an auto-provisioned container configuration.
        string|responses:AutoCodeInterpreterToolParam container;
    |} configurations;
|};

# Web search tool for OpenAI models.
# Enables the model to search the web for real-time information during a conversation.
# Ref: https://platform.openai.com/docs/guides/tools/web-search
public type WebsearchTool record {|
    *ai:BuiltInTool;
    # Tool identifier. Use `"web_search"` (default) or `"web_search_2025_08_26"` for an older version.
    "web_search"|"web_search_2025_08_26" name;
    # Web search configurations
    record {|
        # Domain filters for narrowing search results
        responses:WebSearchTool_filters? filters?;
        # Approximate user location for localizing search results
        responses:WebSearchApproximateLocation user_location?;
        # High level guidance for the amount of context window space to use for the search.
        # One of `low`, `medium`, or `high`. Defaults to `medium`.
        "low"|"medium"|"high" search_context_size = "medium";
    |} configurations;
|};

# File search tool for OpenAI models.
# Enables the model to search through uploaded files in vector stores.
# Ref: https://platform.openai.com/docs/guides/tools/file-search
public type FileSearchTool record {|
    *ai:BuiltInTool;
    # Tool identifier. Always `"file_search"`.
    "file_search" name;
    # File search configurations
    record {|
        # The IDs of the vector stores to search
        string[] vector_store_ids;
        # Maximum number of results to return (1-50)
        int max_num_results?;
        # Ranking options for fine-tuning search result ordering
        responses:RankingOptions ranking_options?;
        # Metadata filters for narrowing search results
        responses:Filters filters?;
    |} configurations;
|};

# Union type representing all built-in tools supported by the OpenAI provider.
type OpenAIBuiltInTool CodeInterpreterTool|WebsearchTool|FileSearchTool;
