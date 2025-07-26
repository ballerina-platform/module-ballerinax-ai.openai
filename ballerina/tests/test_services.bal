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
    // Change the payload type to JSON due to https://github.com/ballerina-platform/ballerina-library/issues/8048.
    resource function post openai/chat/completions(@http:Payload json payload)
                returns chat:CreateChatCompletionResponse|error {
        test:assertEquals(payload.model, GPT_4O);
        chat:ChatCompletionRequestMessage[] messages = check (check payload.messages).fromJsonWithType();
        chat:ChatCompletionRequestMessage message = messages[0];

        chat:ChatCompletionRequestUserMessageContentPart[]? content = check message["content"].ensureType();
        if content is () {
            test:assertFail("Expected content in the payload");
        }

        chat:ChatCompletionRequestUserMessageContentPart initialContentPart = content[0];
        TextContentPart initialTextContent = check initialContentPart.ensureType();
        string initialText = initialTextContent.text;
        test:assertEquals(content, getExpectedContentParts(initialText),
                string `Test failed for prompt with initial content, ${initialText}`);
        test:assertEquals(message.role, "user");
        chat:ChatCompletionTool[]? tools = check (check payload.tools).fromJsonWithType();
        if tools is () || tools.length() == 0 {
            test:assertFail("No tools in the payload");
        }

        map<json>? parameters = check tools[0].'function?.parameters.toJson().cloneWithType();
        if parameters is () {
            test:assertFail("No parameters in the expected tool");
        }

        test:assertEquals(parameters, getExpectedParameterSchema(initialText),
                string `Test failed for prompt with initial content, ${initialText}`);
        return getTestServiceResponse(initialText);
    }
}
