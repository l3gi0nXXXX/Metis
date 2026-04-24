package metis.telemetry.otel

import std.collection.*
import stdx.encoding.base64.toBase64String

/**
 * Lightweight helpers to translate AttributeValue into OTLP JSON-friendly structures.
 */
public class OtlpJsonUtils {
    private init() {}

    /**
     * Converts a map of attribute key/value pairs into OTLP key/value list form.
     */
    public static func mapAttributes(attributes: HashMap<String, AttributeValue>): ArrayList<OtlpKeyValue> {
        let list = ArrayList<OtlpKeyValue>()
        for ((key, value) in attributes) {
            list.add(OtlpKeyValue(key: key, value: toAnyValue(value)))
        }
        return list
    }

    /**
     * Converts a single AttributeValue into an OTLP AnyValue payload.
     */
    public static func toAnyValue(value: AttributeValue): OtlpAnyValue {
        match (value) {
            case AttributeValue.StringValue(v) => return OtlpAnyValue(stringValue: Some(v))
            case AttributeValue.IntValue(v) => return OtlpAnyValue(intValue: Some(v.toString()))
            case AttributeValue.DoubleValue(v) => return OtlpAnyValue(doubleValue: Some(v))
            case AttributeValue.BoolValue(v) => return OtlpAnyValue(boolValue: Some(v))
            case AttributeValue.BytesValue(bytes) =>
                let encoded = toBase64String(bytes)
                return OtlpAnyValue(bytesValue: Some(encoded))
            case AttributeValue.ArrayValue(values) =>
                var arrayValue = OtlpArrayValue()
                for (item in values) {
                    arrayValue.values.add(toAnyValue(item))
                }
                return OtlpAnyValue(arrayValue: Some(arrayValue))
            case AttributeValue.KvList(map) =>
                var kvList = OtlpKeyValueList()
                for ((k, v) in map) {
                    kvList.values.add(OtlpKeyValue(key: k, value: toAnyValue(v)))
                }
                return OtlpAnyValue(kvlistValue: Some(kvList))
        }
    }

    /**
     * Converts a (String -> String) attribute map into OTLP key/value pairs.
     */
    public static func mapStringAttributes(attributes: HashMap<String, String>): ArrayList<OtlpKeyValue> {
        let list = ArrayList<OtlpKeyValue>()
        for ((key, value) in attributes) {
            list.add(OtlpKeyValue(key: key, value: OtlpAnyValue(stringValue: Some(value))))
        }
        return list
    }

    /**
     * Expands an attribute compound key (key=value pairs joined by comma) into a map.
     */
    public static func decodeAttributeKey(encoded: String): HashMap<String, String> {
        let attributes = HashMap<String, String>()
        if (encoded.size == 0) {
            return attributes
        }

        for (pair in encoded.split(",")) {
            match (pair.indexOf("=")) {
                case Some(separatorIndex) =>
                    let runes = pair.toRuneArray()
                    let keyRunes = Array<Rune>(Int64(separatorIndex), { idx => runes[idx] })
                    let valueRunes = Array<Rune>(runes.size - Int64(separatorIndex) - 1, { idx => runes[idx + Int64(separatorIndex) + 1] })
                    let key = String(keyRunes)
                    let value = String(valueRunes)
                    attributes[key] = value
                case None => ()
            }
        }
        return attributes
    }

    /**
     * Normalizes a trace identifier to 32 lowercase hexadecimal characters when possible.
     */
    public static func normalizeTraceId(traceId: String): String {
        return normalizeHex(traceId, 32)
    }

    /**
     * Normalizes a span identifier to 16 lowercase hexadecimal characters when possible.
     */
    public static func normalizeSpanId(spanId: String): String {
        return normalizeHex(spanId, 16)
    }

    private static func normalizeHex(value: String, expectedLength: Int64): String {
        if (value.size == 0) {
            return ""
        }
        if (value.size == expectedLength) {
            return value
        }
        if (value.size > expectedLength) {
            let runes = value.toRuneArray()
            let startIndex = runes.size - expectedLength
            let slice = Array<Rune>(Int64(expectedLength), { idx => runes[idx + startIndex] })
            return String(slice)
        }
        return value.padStart(expectedLength, padding: "0")
    }
}
