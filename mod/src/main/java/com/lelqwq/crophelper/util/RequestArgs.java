package com.lelqwq.crophelper.util;

import java.nio.charset.StandardCharsets;
import java.util.Map;

import com.lelqwq.crophelper.ApiException;

/**
 * OC 会把 Lua 数字转换为 Number（通常是 Long 或 Double），这里统一做整数与范围校验。
 */
public final class RequestArgs {

    private RequestArgs() {}

    public static int requiredInt(Map<?, ?> args, String key, int min, int max) {
        Object value = args == null ? null : args.get(key);
        if (value == null) {
            throw invalid(key + " is required");
        }
        return toInt(key, value, min, max);
    }

    public static int optionalInt(Map<?, ?> args, String key, int defaultValue, int min, int max) {
        Object value = args == null ? null : args.get(key);
        if (value == null) {
            return defaultValue;
        }
        return toInt(key, value, min, max);
    }

    public static String requiredString(Map<?, ?> args, String key) {
        Object value = args == null ? null : args.get(key);
        String text;
        if (value instanceof String) {
            text = (String) value;
        } else if (value instanceof byte[]) {
            // OC 对无法按 UTF-8 往返的 Lua 字符串会交付 byte[]。
            text = new String((byte[]) value, StandardCharsets.UTF_8);
        } else {
            throw invalid(key + " must be a string");
        }
        // 保留原始值：species_id 由 owner/name 原样拼接，trim 会造成目录里的 ID 无法回查。
        if (text.isEmpty() || text.trim()
            .isEmpty()) {
            throw invalid(key + " must not be empty");
        }
        return text;
    }

    private static int toInt(String key, Object value, int min, int max) {
        if (!(value instanceof Number)) {
            throw invalid(key + " must be a number");
        }
        Number number = (Number) value;
        if (number instanceof Double || number instanceof Float) {
            double raw = number.doubleValue();
            if (Double.isNaN(raw) || Double.isInfinite(raw) || raw != Math.rint(raw)) {
                throw invalid(key + " must be an integer");
            }
            if (raw < min || raw > max) {
                throw invalid(key + " must be between " + min + " and " + max);
            }
            return (int) raw;
        }
        long raw = number.longValue();
        if (raw < min || raw > max) {
            throw invalid(key + " must be between " + min + " and " + max);
        }
        return (int) raw;
    }

    private static ApiException invalid(String message) {
        return new ApiException("invalid_argument", message);
    }
}
