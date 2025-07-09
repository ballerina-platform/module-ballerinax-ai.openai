/*
 * Copyright (c) 2025, WSO2 LLC. (http://www.wso2.com).
 *
 * WSO2 LLC. licenses this file to you under the Apache License,
 * Version 2.0 (the "License"); you may not use this file except
 * in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing,
 * software distributed under the License is distributed on an
 * "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 * KIND, either express or implied. See the License for the
 * specific language governing permissions and limitations
 * under the License.
 */

package io.ballerina.lib.ai.openai;

import io.ballerina.compiler.syntax.tree.SyntaxKind;
import io.ballerina.openapi.service.mapper.type.TypeMapper;
import io.ballerina.projects.plugins.CodeModifier;
import io.ballerina.projects.plugins.CodeModifierContext;

/**
 * Analyzes the `generate` API and generates a JSON schema for the expected type.
 *
 * @since 1.0.0
 */
public class AiOpenAICodeModifier extends CodeModifier {
    @Override
    public void init(CodeModifierContext modifierContext) {
        AnalysisData analysisData = new AnalysisData();
        modifierContext.addSyntaxNodeAnalysisTask(new TypeMapperImplInitializer(analysisData), SyntaxKind.MODULE_PART);
        modifierContext.addSourceModifierTask(new GenerateMethodModificationTask(analysisData));
    }

    static final class AnalysisData {
        TypeMapper typeMapper;
    }
}
