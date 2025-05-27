## Overview

This module offers APIs for connecting with OpenAI Large Language Models (LLM).

## Prerequisites

Before using this module in your Ballerina application, first you must obtain the nessary configuration to engage the LLM.

- Create an [OpenAI account](https://beta.openai.com/signup/).
- Obtain an API key by following [these instructions](https://platform.openai.com/docs/api-reference/authentication).


## Quickstart

To use the `ai.model.provider.openai` module in your Ballerina application, update the `.bal` file as follows:

### Step 1: Import the module

Import the `ai.model.provider.openai;` module.

```ballerina
import ballerinax/ai.model.provider.openai;
```

### Step 2: Intialize the Model Provider

Here's how to initialize the Model Provider:

```ballerina
import ballerina/ai;
import ballerinax/ai.model.provider.openai;

final ai:ModelProvider openAiModel = check new openai:Provider("openAiApiKey", modelType = openai:GPT_4O);
```

### Step 4: Invoke chat completion

```
ai:ChatMessage[] chatMessages = [{role: "user", content: "hi"}];
ai:ChatAssistantMessage response = check openAiModel->chat(chatMessages, tools = []);

chatMessages.push(response);
```
