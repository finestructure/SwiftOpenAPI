import Foundation

// TODO - format, externalDocs, example

/// The Schema Object allows the definition of input and output data types. These types can be objects, but also primitives and arrays. This object is a superset of the JSON Schema Specification Draft 2020-12.
///
/// For more information about the properties, see JSON Schema Core and JSON Schema Validation.
///
/// Unless stated otherwise, the property definitions follow those of JSON Schema and do not add any additional semantics. Where JSON Schema indicates that behavior is defined by the application (e.g. for annotations), OAS also defers the definition of semantics to the application consuming the OpenAPI document.
public indirect enum SchemaObject: Equatable, Codable, SpecificationExtendable {
    
    case any
    
    case primitive(PrimitiveDataType)
    
    case object(
        [String: ReferenceOr<SchemaObject>],
        required: Set<String>?,
        additionalProperties: ReferenceOr<SchemaObject>? = nil,
        xml: XMLObject? = nil
    )
    
    case array(
        ReferenceOr<SchemaObject>
    )
    
    case composite(
        CompositeType,
        [ReferenceOr<SchemaObject>],
        discriminator: DiscriminatorObject?
    )
    
    public enum CodingKeys: String, CodingKey {
        
        case type
        case items
        case required
        case properties
        case discriminator
        case xml
        case additionalProperties
        
        case oneOf
        case allOf
        case anyOf
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decodeIfPresent(DataType.self, forKey: .type)
        
        switch type {
        case .array:
            let items = try container.decode(ReferenceOr<SchemaObject>.self, forKey: .items)
            self = .array(items)
            
        case .object:
            let properties = try container.decode([String: ReferenceOr<SchemaObject>].self, forKey: .properties)
            let xml = try container.decodeIfPresent(XMLObject.self, forKey: .xml)
        		let required = try container.decodeIfPresent(Set<String>.self, forKey: .required)
        		let additionalProperties = try container.decodeIfPresent(ReferenceOr<SchemaObject>.self, forKey: .additionalProperties)
            self = .object(
                properties,
                required: required,
                additionalProperties: additionalProperties,
                xml: xml
            )
            
        case .none:
            let compositionKey = Set(container.allKeys).intersection([.oneOf, .allOf, .anyOf]).first
            
            if let compositionKey, let composition = CompositeType(rawValue: compositionKey.rawValue) {
                let discriminator = try container.decodeIfPresent(DiscriminatorObject.self, forKey: .discriminator)
                let objects = try container.decode([ReferenceOr<SchemaObject>].self, forKey: compositionKey)
                self = .composite(
                    composition,
                    objects,
                    discriminator: discriminator
                )
            } else {
                self = .any
            }
            
        case let .some(type):
            self = .primitive(PrimitiveDataType(rawValue: type.rawValue) ?? .string)
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .any:
            break
            
        case let .primitive(type):
            try container.encodeIfPresent(type, forKey: .type)
            
        case let .object(
            properties,
            required,
            additionalProperties,
            xml
        ):
            try container.encodeIfPresent(DataType.object, forKey: .type)
            try container.encodeIfPresent(xml, forKey: .xml)
            try container.encode(properties, forKey: .properties)
            try container.encodeIfPresent(required, forKey: .required)
            try container.encodeIfPresent(additionalProperties, forKey: .additionalProperties)
            
        case let .array(schemaObject):
            try container.encodeIfPresent(DataType.array, forKey: .type)
            try container.encode(schemaObject, forKey: .items)
            
        case let .composite(composite, items, discriminator):
            try container.encodeIfPresent(discriminator, forKey: .type)
            try container.encode(items, forKey: CodingKeys(rawValue: composite.rawValue) ?? .oneOf)
        }
    }
}

public protocol ExpressibleBySchemaObject {
    
    init(schemaObject: SchemaObject)
}

extension SchemaObject: ExpressibleBySchemaObject {
    
    public init(schemaObject: SchemaObject) {
        self = schemaObject
    }
}

extension ReferenceOr: ExpressibleBySchemaObject where Object: ExpressibleBySchemaObject {
    
    public init(schemaObject: SchemaObject) {
        self = .value(Object(schemaObject: schemaObject))
    }
}

public extension ExpressibleBySchemaObject {
    
    static func oneOf(
        _ types: ReferenceOr<SchemaObject>...,
        discriminator: DiscriminatorObject? = nil
    ) -> Self {
        Self(
            schemaObject: .composite(.oneOf, types, discriminator: discriminator)
        )
    }
    
    static func allOf(
        _ types: ReferenceOr<SchemaObject>...,
        discriminator: DiscriminatorObject? = nil
    ) -> Self {
        Self(
            schemaObject: .composite(.allOf, types, discriminator: discriminator)
        )
    }
    
    static func anyOf(
        _ types: ReferenceOr<SchemaObject>...,
        discriminator: DiscriminatorObject? = nil
    ) -> Self {
        Self(
            schemaObject: .composite(.anyOf, types, discriminator: discriminator)
        )
    }
    
    static var string: Self { Self(schemaObject: .primitive(.string)) }
    static var number: Self { Self(schemaObject: .primitive(.number)) }
    static var integer: Self { Self(schemaObject: .primitive(.integer)) }
    static var boolean: Self { Self(schemaObject: .primitive(.boolean)) }
}

extension SchemaObject: ExpressibleByDictionary {
    
    public typealias Key = String
    public typealias Value = ReferenceOr<SchemaObject>
    
    public init(dictionaryElements elements: [(String, ReferenceOr<SchemaObject>)]) {
        self = .object(
            Dictionary(elements) { _, s in s },
            required: nil,
            additionalProperties: nil,
            xml: nil
        )
    }
}

extension SchemaObject {
    
    var isReferenceable: Bool {
        switch self {
        case .any:
            return false
        case .object, .array, .composite, .primitive:
            return true
        }
    }
}

public extension ExpressibleBySchemaObject {
    
    @discardableResult
    static func encode(_ value: Encodable, into schemes: inout [String: ReferenceOr<SchemaObject>]) throws -> Self {
        let encoder = SchemeEncoder()
        try value.encode(to: encoder)
        schemes.merge(encoder.references) { _, s in s }
        schemes[.typeName(type(of: value))] = .value(encoder.result)
        return Self(schemaObject: encoder.result)
    }
    
    static func encodeWithoutReferences(_ value: Encodable) throws -> Self {
        let encoder = SchemeEncoder(extractReferences: false)
        try value.encode(to: encoder)
        return Self(schemaObject: encoder.result)
    }
}
