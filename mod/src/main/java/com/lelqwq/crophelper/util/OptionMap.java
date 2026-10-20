package com.lelqwq.crophelper.util;

import java.nio.charset.StandardCharsets;
import java.util.LinkedHashMap;
import java.util.Map;

/**
 * OC 的 options 表在默认原生 Lua 下使用 String 键；LuaJ 架构会把 Lua 字符串交付为 byte[]。
 * 这里统一归一化为 String 键，值保持原类型，交给 RequestArgs 处理。
 */
public final class OptionMap {

    private OptionMap() {}

    public static Map<String, Object> normalize(Map<?, ?> input) {
        Map<String, Object> result = new LinkedHashMap<String, Object>();
        for (Map.Entry<?, ?> entry : input.entrySet()) {
            Object rawKey = entry.getKey();
            String key;
            if (rawKey instanceof String) {
                key = (String) rawKey;
            } else if (rawKey instanceof byte[]) {
                key = new String((byte[]) rawKey, StandardCharsets.UTF_8);
            } else {
                continue;
            }
            result.put(key, entry.getValue());
        }
        return result;
    }
}
