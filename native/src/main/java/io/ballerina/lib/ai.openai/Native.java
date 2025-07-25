/*
 * Copyright (c) 2025, WSO2 LLC. (http://wso2.com).
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
package io.ballerina.lib.ai.openai;

import io.ballerina.runtime.api.Module;
import io.ballerina.runtime.api.creators.ErrorCreator;
import io.ballerina.runtime.api.creators.TypeCreator;
import io.ballerina.runtime.api.creators.ValueCreator;
import io.ballerina.runtime.api.types.AnnotatableType;
import io.ballerina.runtime.api.types.ArrayType;
import io.ballerina.runtime.api.types.JsonType;
import io.ballerina.runtime.api.types.PredefinedTypes;
import io.ballerina.runtime.api.types.ReferenceType;
import io.ballerina.runtime.api.types.Type;
import io.ballerina.runtime.api.types.TypeTags;
import io.ballerina.runtime.api.types.UnionType;
import io.ballerina.runtime.api.utils.StringUtils;
import io.ballerina.runtime.api.utils.TypeUtils;
import io.ballerina.runtime.api.values.BArray;
import io.ballerina.runtime.api.values.BError;
import io.ballerina.runtime.api.values.BMap;
import io.ballerina.runtime.api.values.BString;
import io.ballerina.runtime.api.values.BTypedesc;

import java.util.List;

import static io.ballerina.runtime.api.creators.ValueCreator.createMapValue;

/**
 * Native implementation of OpenAI functions.
 *
 * @since 1.0.0
 */
public class Native {
    public static final String ANY_OF = "anyOf";
    public static final String BALLERINA_AI = "ballerina/ai";
    public static final String JSON_SCHEMA = "JsonSchema";

    public static Object generateJsonSchemaForTypedescNative(BTypedesc td) {
        SchemaGenerationContext schemaGenerationContext = new SchemaGenerationContext();
        try {
            Object schema = generateJsonSchemaForType(td.getDescribingType(), schemaGenerationContext);
            return schemaGenerationContext.isSchemaGeneratedAtCompileTime ? schema : null;
        } catch (BError e) {
            return createAIError(e.getErrorMessage());
        }
    }

    private static Object generateJsonSchemaForType(Type t, SchemaGenerationContext schemaGenerationContext)
            throws BError {
        Type impliedType = TypeUtils.getImpliedType(t);
        if (isSimpleType(impliedType)) {
            return createSimpleTypeSchema(impliedType);
        }

        return switch (impliedType) {
            case JsonType ignored -> generateJsonSchemaForJson();
            case ArrayType arrayType -> generateJsonSchemaForArrayType(arrayType, schemaGenerationContext);
            case UnionType unionType -> generateUnionTypeSchema(unionType, schemaGenerationContext);
            case ReferenceType referenceType -> getJsonSchemaFromAnnotatableType(referenceType,
                    schemaGenerationContext);
            default -> throw ErrorCreator.createError(StringUtils.fromString(
                    "Runtime schema generation is not yet supported for type " + impliedType.getName()));
        };
    }

    private static BError createAIError(BString message) {
        return ErrorCreator.createError(new Module("ballerina", "ai", "1"),
                "Error", message, null, null);
    }

    private static BMap<BString, Object> createSimpleTypeSchema(Type type) {
        BMap<BString, Object> schemaMap = createMapValue(TypeCreator.createMapType(PredefinedTypes.TYPE_JSON));
        schemaMap.put(StringUtils.fromString("type"), StringUtils.fromString(getStringRepresentation(type)));
        return schemaMap;
    }

    private static Object generateUnionTypeSchema(UnionType unionType,
                                                  SchemaGenerationContext schemaGenerationContext) {
        BMap<BString, Object> schemaMap = createMapValue(TypeCreator.createMapType(PredefinedTypes.TYPE_JSON));
        List<Type> memberTypes = unionType.getMemberTypes();
        BArray schemas = ValueCreator.createArrayValue(
                TypeCreator.createArrayType(PredefinedTypes.TYPE_JSON));
        for (Type memberType : memberTypes) {
            Object schema = generateJsonSchemaForType(memberType, schemaGenerationContext);
            schemas.append(schema);
        }
        if (schemas.size() == 1) {
            return schemas.get(0);
        }
        schemaMap.put(StringUtils.fromString(ANY_OF), schemas);
        return schemaMap;
    }

    private static Object getJsonSchemaFromAnnotatableType(ReferenceType referenceType,
                                                           SchemaGenerationContext schemaGenerationContext) {
        Type referredType = referenceType.getReferredType();
        if (referredType instanceof  AnnotatableType annotatableType) {
            BMap<BString, Object> annotations = annotatableType.getAnnotations();
            for (BString key : annotations.getKeys()) {
                if (key.getValue().startsWith(BALLERINA_AI) && key.getValue().endsWith(JSON_SCHEMA)) {
                    Object schema = annotations.get(key);
                    if (schema instanceof BMap) {
                        return schema;
                    }
                }
            }
        }
        throw ErrorCreator.createError(StringUtils.fromString(
                "Runtime schema generation is not yet supported for type: " + referenceType.getName()));
    }

    private static BMap<BString, Object> generateJsonSchemaForJson() {
        BString[] bStringValues = new BString[6];
        bStringValues[0] = StringUtils.fromString("object");
        bStringValues[1] = StringUtils.fromString("array");
        bStringValues[2] = StringUtils.fromString("string");
        bStringValues[3] = StringUtils.fromString("number");
        bStringValues[4] = StringUtils.fromString("boolean");
        bStringValues[5] = StringUtils.fromString("null");
        BMap<BString, Object> schemaMap = createMapValue(TypeCreator.createMapType(PredefinedTypes.TYPE_JSON));
        schemaMap.put(StringUtils.fromString("type"), ValueCreator.createArrayValue(bStringValues));
        return schemaMap;
    }

    private static boolean isSimpleType(Type type) {
        return type.getBasicType().all() <= 0b100000;
    }

    private static String getStringRepresentation(Type type) {
        if (type.getTag() == TypeTags.NULL_TAG) {
            return "null";
        }
        return switch (type.getBasicType().all()) {
            case 0b000000 -> "null";
            case 0b000010 -> "boolean";
            case 0b000100 -> "integer";
            case 0b001000, 0b010000 -> "number";
            case 0b100000 -> "string";
            default -> null;
        };
    }

    private static Object generateJsonSchemaForArrayType(ArrayType arrayType,
                                                         SchemaGenerationContext schemaGenerationContext) {
        BMap<BString, Object> schemaMap = createMapValue(TypeCreator.createMapType(PredefinedTypes.TYPE_JSON));
        Type elementType = TypeUtils.getImpliedType(arrayType.getElementType());
        schemaMap.put(StringUtils.fromString("type"), StringUtils.fromString("array"));
        schemaMap.put(StringUtils.fromString("items"), generateJsonSchemaForType(elementType,
                schemaGenerationContext));
        return schemaMap;
    }

    public static BTypedesc getArrayMemberType(BTypedesc expectedResponseTypedesc) {
        return ValueCreator.createTypedescValue(
                ((ArrayType) TypeUtils.getImpliedType(expectedResponseTypedesc.getDescribingType())).getElementType());
    }

    public static boolean containsNil(BTypedesc expectedResponseTypedesc) {
        return expectedResponseTypedesc.getDescribingType().isNilable();
    }

    private static class SchemaGenerationContext {
        boolean isSchemaGeneratedAtCompileTime = true;
    }
}
