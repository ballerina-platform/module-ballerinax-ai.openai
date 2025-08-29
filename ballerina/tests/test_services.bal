// Copyright (c) 2025 WSO2 LLC. (http://www.wso2.org).
//
// WSO2 Inc. licenses this file to you under the Apache License,
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
import ballerina/test;
import ballerinax/openai.chat;

service /llm on new http:Listener(8080) {
    private map<int> retryCountMap = {};

    // Change the payload type to JSON due to https://github.com/ballerina-platform/ballerina-library/issues/8048.
    resource function post openai/chat/completions(@http:Payload json payload)
                returns chat:CreateChatCompletionResponse|error {
        [chat:ChatCompletionRequestMessage[], string] [messages, initialText] = 
                check validateChatCompletionPayload(payload);
        
        check assertContentParts(messages, initialText, 0);
        return check getTestServiceResponse(initialText);
    }

    resource function post openai\-retry/chat/completions(@http:Payload json payload)
                returns chat:CreateChatCompletionResponse|error {
        [chat:ChatCompletionRequestMessage[], string] [messages, initialText] = 
                check validateChatCompletionPayload(payload);

        int index;
        lock {
            index = updateRetryCountMap(initialText, self.retryCountMap);
        }

        check assertContentParts(messages, initialText, index);
        return check getTestServiceResponse(initialText, index);
    }
}

isolated function validateChatCompletionPayload(json payload) 
        returns [chat:ChatCompletionRequestMessage[], string]|error {
    test:assertEquals(payload.model, GPT_4O);
    chat:ChatCompletionRequestMessage[] messages = check (check payload.messages).fromJsonWithType();
    chat:ChatCompletionRequestMessage message = messages[0];
    test:assertEquals(message.role, "user");

    chat:ChatCompletionRequestUserMessageContentPart[]? content = check message["content"].ensureType();
    if content is () {
        test:assertFail("Expected content in the payload");
    }

    chat:ChatCompletionRequestUserMessageContentPart initialContentPart = content[0];
    TextContentPart initialTextContent = check initialContentPart.ensureType();
    string initialText = initialTextContent.text;

    chat:ChatCompletionTool[]? tools = check (check payload.tools).fromJsonWithType();
    if tools is () || tools.length() == 0 {
        test:assertFail("No tools in the payload");
    }

    map<json>? parameters = check tools[0].'function?.parameters.toJson().cloneWithType();
    if parameters is () {
        test:assertFail("No parameters in the expected tool");
    }

    test:assertEquals(parameters, getExpectedParameterSchema(initialText),
            string `Parameter assertion failed for prompt starting with '${initialText}'`);

    return [messages, initialText];
}

isolated function assertContentParts(chat:ChatCompletionRequestMessage[] messages, 
        string initialText, int index) returns error? {
    if index >= messages.length() {
        test:assertFail(string `Expected at least ${index + 1} message(s) in the payload`);
    }

    // Test input messages where the role is 'user'.
    chat:ChatCompletionRequestMessage message = messages[index * 2];

    string|chat:ChatCompletionRequestUserMessageContentPart[] content = check message["content"].ensureType();

    if index == 0 && content is string {
        test:assertFail(string `Expected content as an array in the payload, payload: ${content}`);
    }

    if index == 0 {
        test:assertEquals(content, check getExpectedContentParts(initialText),
            string `Prompt assertion failed for prompt starting with '${initialText}'`);
        return;
    }

    if index == 1 {
        test:assertEquals(content, check getExpectedContentPartsForFirstRetryCall(initialText),
            string `Prompt assertion failed for prompt starting with '${initialText}' 
                on first attempt of the retry`);
        return;
    }

    test:assertEquals(content,check getExpectedContentPartsForSecondRetryCall(initialText),
            string `Prompt assertion failed for prompt starting with '${initialText}' on 
                second attempt of the retry`);
}

isolated function updateRetryCountMap(string initialText, map<int> retryCountMap) returns int {
    if retryCountMap.hasKey(initialText) {
        int index = retryCountMap.get(initialText) + 1;
        retryCountMap[initialText] = index;
        return index;
    }

    retryCountMap[initialText] = 0;
    return 0;
}
