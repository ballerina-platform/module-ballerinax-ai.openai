## Overview

The `ai.openai` module provides OpenAI-backed `ModelProvider` and `EmbeddingProvider` implementations for the [`ballerina/ai`](https://central.ballerina.io/ballerina/ai/latest) agent framework. Use it to drive OpenAI chat models (GPT-4o, GPT-4, GPT-3.5) and text-embedding models from Ballerina AI agents, RAG pipelines, and other `ai`-module abstractions — rather than calling the OpenAI REST API directly.

### Key Features

- Connect and interact with OpenAI Large Language Models (LLMs)
- Support for GPT-6, GPT-5, GPT-4.1, GPT-4o, and other advanced models
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

The first argument, `apiKey`, sets how the connector authenticates with the OpenAI API. It keeps its name so that existing code still compiles, but it accepts any of the following. The same options apply to `openai:EmbeddingProvider`.

- **API key** (`string`): sent in the `Authorization: Bearer` header, as in the example above.

- **API key with an organization or project** (`openai:ApiKeyConfig`): sends `organization` in the `OpenAI-Organization` header and `project` in the `OpenAI-Project` header, so usage is counted for that organization and project. Set them when your user belongs to more than one organization or accesses projects through a legacy user API key.

    ```ballerina
    final ai:ModelProvider openAiModel = check new openai:ModelProvider(
        {apiKey: "openAiApiKey", organization: "org-...", project: "proj_..."}, openai:GPT_4O);
    ```

- **Workload Identity Federation** (`openai:WorkloadIdentityConfig`): exchanges an identity token from your identity provider (for example, AWS, Google Cloud, Microsoft Entra ID, Kubernetes, or GitHub Actions) for a short-lived OpenAI access token, so no API key is needed. The connector reuses the access token until it is about to expire, then exchanges the identity token again. An access token never outlives the identity token, and a rejected identity token is not exchanged again, so once the identity token expires or is rejected, create a new model provider with a new identity token. See [Workload identity federation](https://developers.openai.com/api/docs/guides/workload-identity-federation) for how to set up the workload identity provider and service account mapping.

    ```ballerina
    final ai:ModelProvider openAiModel = check new openai:ModelProvider({
        identityProviderId: "<workload identity provider ID>",
        serviceAccountId: "<service account ID>",
        identityToken: "<identity token (JWT) from your identity provider>"
    }, openai:GPT_4O);
    ```

    A module-level `final` provider, as above, cannot be replaced. Use one only when the identity token outlives the application. Many identity tokens expire within an hour, for example Kubernetes projected service account tokens and GitHub Actions OIDC tokens. For those, create the provider where you can replace it, and create a new one with a new identity token before the old identity token expires.

- **Access token** (`http:BearerTokenConfig`): an access token obtained elsewhere, sent in the `Authorization: Bearer` header. The connector does not refresh it, so requests fail once it expires.

> **Note:** Some models are restricted on the default Chat Completions API:
> - `O3_PRO`, `GPT_5_PRO`, `GPT_5_2_PRO`, `GPT_5_3_CODEX`, `GPT_5_4_PRO` and `GPT_5_5_PRO` are available only with `apiType = openai:RESPONSES`.
> - Tool calling and `generate()` with `GPT_6_ASTRA`, `GPT_6_1_SOL` and `GPT_6_1_TERRA` require `apiType = openai:RESPONSES`.
> - Tool calling and `generate()` with the `GPT_5_6` family, `GPT_6_SOL` and `GPT_6_LUNA` require `reasoningEffort = openai:NONE`, or `apiType = openai:RESPONSES`.

### Step 4: Invoke chat completion

```ballerina
ai:ChatMessage[] chatMessages = [{role: "user", content: "hi"}];
ai:ChatAssistantMessage response = check openAiModel->chat(chatMessages, tools = []);

chatMessages.push(response);
```
