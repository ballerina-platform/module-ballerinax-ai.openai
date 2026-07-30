## Overview

OpenAI provides powerful AI models for natural language processing, image generation, and other advanced tasks.

The OpenAI connector offers APIs for connecting with OpenAI Large Language Models (LLMs), enabling the integration of advanced conversational AI, text generation, and language processing capabilities into applications.

### Key Features

- Connect and interact with OpenAI Large Language Models (LLMs)
- Support for GPT-4o, GPT-4, GPT-3.5, and other advanced models
- Efficient handling of conversational prompts and completions
- Secure communication with API key authentication

## Prerequisites

Before using this module in your Ballerina application, first you must obtain the nessary configuration to engage the LLM.

- Create an [OpenAI account](https://beta.openai.com/signup/).
- Obtain an API key by following [these instructions](https://platform.openai.com/docs/api-reference/authentication).


## Quickstart

To use the `ai.openai` module in your Ballerina application, update the `.bal` file as follows:

### Step 1: Import the module

Import the `ai.openai;` module.

```ballerina
import ballerinax/ai.openai;
```

### Step 2: Intialize the Model Provider

Here's how to initialize the Model Provider:

```ballerina
import ballerina/ai;
import ballerinax/ai.openai;

final ai:ModelProvider openAiModel = check new openai:ModelProvider("openAiApiKey", modelType = openai:GPT_4O);
```

### Step 4: Invoke chat completion

```ballerina
ai:ChatMessage[] chatMessages = [{role: "user", content: "hi"}];
ai:ChatAssistantMessage response = check openAiModel->chat(chatMessages, tools = []);

chatMessages.push(response);
```
