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

// ===================================================================
// to_json_schema.bal unit tests (Ballerina runtime schema generation)
// ===================================================================

type NilType ();
type JsonMap map<json>;
type IntArray int[];
type NilableInt int?;

@test:Config
function testIsSimpleType() {
    test:assertTrue(isSimpleType(int));
    test:assertTrue(isSimpleType(string));
    test:assertTrue(isSimpleType(float));
    test:assertTrue(isSimpleType(decimal));
    test:assertTrue(isSimpleType(boolean));
    test:assertTrue(isSimpleType(NilType));
    test:assertFalse(isSimpleType(IntArray));
    test:assertFalse(isSimpleType(JsonMap));
}

@test:Config
function testGetStringRepresentation() {
    test:assertEquals(getStringRepresentation(int), "integer");
    test:assertEquals(getStringRepresentation(string), "string");
    test:assertEquals(getStringRepresentation(float), "number");
    test:assertEquals(getStringRepresentation(decimal), "number");
    test:assertEquals(getStringRepresentation(boolean), "boolean");
    test:assertEquals(getStringRepresentation(NilType), "null");
}

@test:Config
function testGenerateJsonSchemaForTypedescSimple() returns ai:Error? {
    JsonSchema|JsonArraySchema|map<json> schema = check generateJsonSchemaForTypedesc(int, false);
    test:assertTrue(schema is JsonSchema);
    if schema is JsonSchema {
        test:assertEquals(schema.'type, "integer");
    }
}

@test:Config
function testGenerateJsonSchemaForTypedescSimpleString() returns ai:Error? {
    JsonSchema|JsonArraySchema|map<json> schema = check generateJsonSchemaForTypedesc(string, false);
    test:assertTrue(schema is JsonSchema);
    if schema is JsonSchema {
        test:assertEquals(schema.'type, "string");
    }
}

@test:Config
function testGenerateJsonSchemaForTypedescArray() returns ai:Error? {
    JsonSchema|JsonArraySchema|map<json> schema = check generateJsonSchemaForTypedesc(IntArray, false);
    test:assertTrue(schema is JsonArraySchema);
    if schema is JsonArraySchema {
        test:assertEquals(schema.items.'type, "integer");
    }
}

@test:Config
function testGenerateJsonSchemaForTypedescNilableArray() returns ai:Error? {
    JsonSchema|JsonArraySchema|map<json> schema = check generateJsonSchemaForTypedesc(IntArray, true);
    test:assertTrue(schema is JsonArraySchema);
    if schema is JsonArraySchema {
        // Nilable member types produce a oneOf including a "null" option.
        JsonSchema items = schema.items;
        (JsonSchema|JsonArraySchema)[]? oneOf = items.oneOf;
        test:assertTrue(oneOf is (JsonSchema|JsonArraySchema)[]);
    }
}

@test:Config
function testGenerateJsonSchemaForTypedescUnsupported() {
    // A non-simple, non-array json type is not supported by the runtime generator.
    JsonSchema|JsonArraySchema|map<json>|ai:Error schema = generateJsonSchemaForTypedesc(JsonMap, false);
    test:assertTrue(schema is ai:Error);
    if schema is ai:Error {
        test:assertTrue(schema.message().includes("Runtime schema generation is not yet supported"));
    }
}

@test:Config
function testGetArrayMemberType() {
    typedesc<json> memberType = getArrayMemberType(IntArray);
    test:assertTrue(memberType is typedesc<int>);
}

@test:Config
function testContainsNil() {
    test:assertTrue(containsNil(NilableInt));
    test:assertFalse(containsNil(int));
}

@test:Config
function testGenerateJsonSchemaForTypedescAsJsonSimple() returns ai:Error? {
    map<json> schema = check generateJsonSchemaForTypedescAsJson(int);
    test:assertEquals(schema["type"], "integer");
}
