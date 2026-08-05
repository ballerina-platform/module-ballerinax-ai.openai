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
import ballerina/test;

final EmbeddingProvider embeddingProvider = check new (API_KEY, TEXT_EMBEDDING_3_SMALL, SERVICE_URL);

@test:Config
function testEmbedWithTextDocument() returns ai:Error? {
    ai:TextDocument doc = {content: "Embed this text"};
    ai:Embedding embedding = check embeddingProvider->embed(doc);
    test:assertEquals(embedding, <ai:Vector>[0.1, 0.2, 0.3]);
}

@test:Config
function testEmbedWithTextChunk() returns ai:Error? {
    ai:TextChunk chunk = {content: "Embed this chunk"};
    ai:Embedding embedding = check embeddingProvider->embed(chunk);
    test:assertEquals(embedding, <ai:Vector>[0.1, 0.2, 0.3]);
}

@test:Config
function testEmbedWithUnsupportedChunk() {
    ai:Chunk chunk = {'type: "binary", content: [1, 2, 3]};
    ai:Embedding|ai:Error embedding = embeddingProvider->embed(chunk);
    test:assertTrue(embedding is ai:Error);
    if embedding is ai:Error {
        test:assertTrue(embedding.message().includes("Unsupported document type"));
    }
}

@test:Config
function testEmbedConnectionError() {
    ai:TextDocument doc = {content: "TRIGGER_EMBEDDING_ERROR now"};
    ai:Embedding|ai:Error embedding = embeddingProvider->embed(doc);
    test:assertTrue(embedding is ai:Error);
    if embedding is ai:Error {
        test:assertTrue(embedding.message().includes("Unable to obtain embedding"));
    }
}

@test:Config
function testEmbedEmptyData() {
    ai:TextDocument doc = {content: "TRIGGER_EMPTY_EMBEDDING_DATA now"};
    ai:Embedding|ai:Error embedding = embeddingProvider->embed(doc);
    test:assertTrue(embedding is ai:Error);
}

@test:Config
function testBatchEmbedWithTextChunks() returns ai:Error? {
    ai:TextChunk[] chunks = [{content: "chunk one"}, {content: "chunk two"}];
    ai:Embedding[] embeddings = check embeddingProvider->batchEmbed(chunks);
    test:assertEquals(embeddings.length(), 2);
    test:assertEquals(embeddings[0], <ai:Vector>[0.1, 0.2, 0.3]);
}

@test:Config
function testBatchEmbedWithTextDocuments() returns ai:Error? {
    ai:TextDocument[] docs = [{content: "doc one"}];
    ai:Embedding[] embeddings = check embeddingProvider->batchEmbed(docs);
    test:assertEquals(embeddings.length(), 1);
}

@test:Config
function testBatchEmbedWithUnsupportedChunks() {
    ai:Chunk[] chunks = [{'type: "binary", content: [1, 2, 3]}];
    ai:Embedding[]|ai:Error embeddings = embeddingProvider->batchEmbed(chunks);
    test:assertTrue(embeddings is ai:Error);
    if embeddings is ai:Error {
        test:assertTrue(embeddings.message().includes("Unsupported chunk type"));
    }
}

@test:Config
function testBatchEmbedConnectionError() {
    ai:TextChunk[] chunks = [{content: "TRIGGER_EMBEDDING_ERROR now"}];
    ai:Embedding[]|ai:Error embeddings = embeddingProvider->batchEmbed(chunks);
    test:assertTrue(embeddings is ai:Error);
}

@test:Config
function testIsAllTextChunks() {
    ai:TextChunk[] textChunks = [{content: "a"}, {content: "b"}];
    test:assertTrue(isAllTextChunks(textChunks));
    ai:Chunk[] mixed = [{content: "a", 'type: "text-chunk"}, {'type: "binary", content: [1]}];
    test:assertFalse(isAllTextChunks(mixed));
}
