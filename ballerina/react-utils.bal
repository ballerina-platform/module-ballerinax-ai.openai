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
import ballerina/lang.regexp;
import ballerina/log;

const THOUGHT_KEY = "Thought:";
const BACKTICKS = "```";
const OBSERVATION_KEY = "Observation";
const ACTION_KEY = "action";
const ACTION_INPUT_KEY = "action_input";
const ACTION_NAME_KEY = "name";
const ACTION_ARGUEMENTS_KEY = "arguments";
const FINAL_ANSWER_KEY = "Final Answer";

final string:RegExp ACTION_INPUT_REGEX = re `^action.?input`;
final string:RegExp FINAL_ANSWER_REGEX = re `^final.?answer`;

isolated function isToolCallSupported(OPEN_AI_MODEL_NAMES model) returns boolean => model != CHATGPT_4O_LATEST;

isolated function constructReActPrompt(ToolInfo toolInfo, string instructions) returns string =>
string `Respond to the human as helpfully and accurately as possible.
You have access to the following tools:
${toolInfo.toolIntro}

Use a json blob to specify a tool by providing an action key (tool name) and an action_input key (tool input).
Valid "${ACTION_KEY}" values: "${FINAL_ANSWER_KEY}" or ${toolInfo.toolList}

Provide only ONE action per $JSON_BLOB, as shown:
${BACKTICKS}
{
  "${ACTION_KEY}": $TOOL_NAME,
  "${ACTION_INPUT_KEY}": $INPUT_JSON
}
${BACKTICKS}

Follow this format:
Question: input question to answer
Thought: consider previous and subsequent steps
Action:
${BACKTICKS}
$JSON_BLOB
${BACKTICKS}
${OBSERVATION_KEY}: action result
... (repeat Thought/Action/${OBSERVATION_KEY} N times)
Thought: I know what to respond
Action:
${BACKTICKS}
{
  "${ACTION_KEY}": "Final Answer",
  "${ACTION_INPUT_KEY}": "Final response to human"
}
${BACKTICKS}

Begin! Reminder to ALWAYS respond with a valid json blob of a single action.
Format is Action:${BACKTICKS}$JSON_BLOB${BACKTICKS}then Observation:.

Beyond the strict instructions listed above, the following rules must be adhered to as well:
${instructions}`;

isolated function extractToolInfo(ai:ChatCompletionFunctions[] tools) returns ToolInfo {
    string[] toolNameList = [];
    string[] toolIntroList = [];
    foreach ai:ChatCompletionFunctions tool in tools {
        toolNameList.push(string `${tool.name}`);
        record {|string description; json inputSchema?;|} toolDescription = {
            description: tool.description,
            inputSchema: tool.parameters
        };
        toolIntroList.push(string `${tool.name}: ${toolDescription.toString()}`);
    }
    return {
        toolList: string:'join(", ", ...toolNameList).trim(),
        toolIntro: string:'join("\n", ...toolIntroList).trim()
    };
}

isolated function parseReActLlmResponse(string? llmResponse) returns ai:LlmToolResponse|ai:LlmChatResponse|ai:LlmInvalidGenerationError {
    if llmResponse is () {
        return error ai:LlmInvalidGenerationError("Unable to extract the tool due to invalid generation", llmResponse = llmResponse);
    }
    string normalizedLlmResponse = normalizeLlmResponse(llmResponse);
    string[] content = regexp:split(re `${BACKTICKS}`, normalizedLlmResponse + "<endtoken>");
    if content.length() < 3 {
        log:printWarn("Unexpected LLM response is given", llmResponse = llmResponse);
        return error ai:LlmInvalidGenerationError("Unable to extract the tool due to invalid generation", llmResponse = llmResponse);
    }

    map<json>|error jsonResponse = content[1].fromJsonStringWithType();
    if jsonResponse is error {
        log:printWarn("Invalid JSON is given as the action.", jsonResponse);
        return error ai:LlmInvalidGenerationError("Invalid JSON is given as the action.", jsonResponse, llmResponse = llmResponse);
    }

    map<json> jsonAction = {};
    foreach [string, json] [key, value] in jsonResponse.entries() {
        if key.toLowerAscii() == ACTION_KEY {
            jsonAction[ACTION_NAME_KEY] = value;
        } else if key.toLowerAscii().matches(ACTION_INPUT_REGEX) {
            jsonAction[ACTION_ARGUEMENTS_KEY] = value;
        }
    }
    json input = jsonAction[ACTION_ARGUEMENTS_KEY];
    if jsonAction[ACTION_NAME_KEY].toString().toLowerAscii().matches(FINAL_ANSWER_REGEX) && input is string {
        return {content: input};
    }
    ai:LlmToolResponse|error tool = jsonAction.fromJsonWithType();
    if tool is error {
        log:printError("Error while extracting action name and inputs from LLM response.", tool, llmResponse = llmResponse);
        return error ai:LlmInvalidGenerationError("Generated 'Action' JSON_BLOB contains invalid action name or inputs.",
        tool, llmResponse = llmResponse);
    }

    return {
        name: tool.name,
        arguments: tool.arguments
    };
}

isolated function normalizeLlmResponse(string llmResponse) returns string {
    string normalizedResponse = llmResponse.trim();
    if !normalizedResponse.includes(BACKTICKS) {
        if normalizedResponse.startsWith("{") && normalizedResponse.endsWith("}") {
            normalizedResponse = string `${BACKTICKS}${normalizedResponse}${BACKTICKS}`;
        } else {
            int? jsonStart = normalizedResponse.indexOf("{");
            int? jsonEnd = normalizedResponse.lastIndexOf("}");
            if jsonStart is int && jsonEnd is int {
                normalizedResponse = string `${BACKTICKS}${normalizedResponse.substring(jsonStart, jsonEnd + 1)}${BACKTICKS}`;
            }
        }
    }
    normalizedResponse = regexp:replace(re `${BACKTICKS}json`, normalizedResponse, BACKTICKS);
    normalizedResponse = regexp:replaceAll(re `"\{\}"`, normalizedResponse, "{}");
    return normalizedResponse;
}

isolated function formatFunctionCallToJsonWithFences(ai:FunctionCall toolCall) returns string =>
string `${BACKTICKS}json
{
    "${ACTION_KEY}": "${toolCall.name}",
    "${ACTION_INPUT_KEY}": ${toolCall.arguments.toJsonString()}
}
${BACKTICKS}`;

isolated function formatFinalAnswerToJsonWithFences(string answer) returns string =>
string `${BACKTICKS}json
{
    "${ACTION_KEY}": "${FINAL_ANSWER_KEY}",
    "${ACTION_INPUT_KEY}": "${answer}"
}
${BACKTICKS}`;
