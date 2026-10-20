package com.lelqwq.crophelper;

/**
 * 协议层可预期的失败。code 直接作为响应中的 error 字段返回。
 */
public final class ApiException extends RuntimeException {

    private final String code;

    public ApiException(String code, String message) {
        super(message);
        this.code = code;
    }

    public String code() {
        return code;
    }
}
