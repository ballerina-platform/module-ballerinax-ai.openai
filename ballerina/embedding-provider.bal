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

    # Generates an embedding vector for the provided document content.
    #
    # + document - The `ai:Document` containing the content to embed
    # + return - The resulting `ai:Embedding` on success; otherwise, returns an `ai:Error`
    isolated remote function embed(ai:Document document) returns ai:Embedding|ai:Error {
        do {
            embeddings:CreateEmbeddingRequest request = {
                model: self.modelType,
                input: document.content
            };
            embeddings:CreateEmbeddingResponse response = check self.embeddingsClient->/embeddings.post(request);
            return check trap response.data[0].embedding;
        } on fail error e {
            return error ai:Error("Unable to obtain embedding for the provided document", e);
        }
    }
}
