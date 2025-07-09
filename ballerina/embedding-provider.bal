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

import ballerina/ai;
import ballerinax/openai.embeddings;

# EmbeddingProvider provides an interface for interacting with OpenAI Embedding Models.
public distinct isolated client class EmbeddingProvider {
    *ai:EmbeddingProvider;
    private final embeddings:Client embeddingsClient;
    private final string modelType;

    # Initializes the OpenAI embedding model with the given connection configuration.
    #
    # + apiKey - The OpenAI API key
    # + modelType - The OpenAI embedding model name
    # + serviceUrl - The base URL of OpenAI API endpoint
    # + connectionConfig - Additional HTTP connection configuration
    # + return - `nil` on successful initialization; otherwise, returns an `ai:Error`
    public isolated function init(@display {label: "API Key"} string apiKey,
            @display {label: "Embedding Model Type"} OPEN_AI_EMBEDDING_MODEL_NAMES modelType,
            @display {label: "Service URL"} string serviceUrl = DEFAULT_OPENAI_SERVICE_URL,
            @display {label: "Connection Configuration"} *ConnectionConfig connectionConfig) returns ai:Error? {
        embeddings:ClientHttp1Settings?|error http1Settings = connectionConfig?.http1Settings.cloneWithType();
        if http1Settings is error {
            return error ai:Error("Failed to clone http1Settings", http1Settings);
        }
        embeddings:ConnectionConfig openAiConfig = {
            auth: {
                token: apiKey
            },
            httpVersion: connectionConfig.httpVersion,
            http1Settings: http1Settings,
            http2Settings: connectionConfig.http2Settings,
            timeout: connectionConfig.timeout,
            forwarded: connectionConfig.forwarded,
            poolConfig: connectionConfig.poolConfig,
            cache: connectionConfig.cache,
            compression: connectionConfig.compression,
            circuitBreaker: connectionConfig.circuitBreaker,
            retryConfig: connectionConfig.retryConfig,
            responseLimits: connectionConfig.responseLimits,
            secureSocket: connectionConfig.secureSocket,
            proxy: connectionConfig.proxy,
            validation: connectionConfig.validation
        };
        embeddings:Client|error embeddingsClient = new (openAiConfig, serviceUrl);
        if embeddingsClient is error {
            return error ai:Error("Failed to initialize OpenAI embedding provider", embeddingsClient);
        }
        self.embeddingsClient = embeddingsClient;
        self.modelType = modelType;
    }

    # Generates an embedding vector for the provided chunk.
    #
    # + chunk - The `ai:Chunk` containing the content to embed
    # + return - The resulting `ai:Embedding` on success; otherwise, returns an `ai:Error`
    isolated remote function embed(ai:Chunk chunk) returns ai:Embedding|ai:Error {
        if chunk !is ai:TextDocument|ai:TextChunk {
            return error ai:Error("Unsupported document type. only 'ai:TextDocument|ai:TextChunk' is supported");
        }
        do {
            embeddings:CreateEmbeddingRequest request = {
                model: self.modelType,
                input: chunk.content
            };
            embeddings:CreateEmbeddingResponse response = check self.embeddingsClient->/embeddings.post(request);
            return check trap response.data[0].embedding;
        } on fail error e {
            return error ai:Error("Unable to obtain embedding for the provided document", e);
        }
    }
}
