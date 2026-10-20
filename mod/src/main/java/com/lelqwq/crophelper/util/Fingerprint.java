package com.lelqwq.crophelper.util;

import java.io.ByteArrayOutputStream;
import java.io.DataOutputStream;
import java.security.MessageDigest;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.List;

import com.lelqwq.crophelper.catalog.Species;

/**
 * 规则指纹覆盖：协议实现版本、相关模组版本、目录中的品种固有信息。
 *
 * <p>
 * 目录顺序不影响指纹；显示名不参与计算，避免服务端语言设置导致缓存失效。
 * </p>
 */
public final class Fingerprint {

    // 修改权重规则时必须同步提升此版本号，让客户端缓存失效。
    private static final String RULE_VERSION = "crop_helper-rules-v1";

    private Fingerprint() {}

    public static String compute(List<Species> input, String modVersions) {
        List<Species> species = new ArrayList<Species>(input);
        Collections.sort(species, new Comparator<Species>() {

            @Override
            public int compare(Species left, Species right) {
                return left.id.compareTo(right.id);
            }
        });

        try {
            ByteArrayOutputStream bytes = new ByteArrayOutputStream();
            DataOutputStream out = new DataOutputStream(bytes);
            out.writeUTF(RULE_VERSION);
            out.writeUTF(modVersions == null ? "" : modVersions);
            out.writeInt(species.size());
            for (Species value : species) {
                out.writeUTF(value.id);
                out.writeInt(value.tier);
                for (int i = 0; i < 5; i++) {
                    out.writeInt(value.stat(i));
                }
                String[] attributes = value.attributes();
                out.writeInt(attributes.length);
                for (String attribute : attributes) {
                    out.writeUTF(attribute == null ? "" : attribute);
                }
                out.writeInt(value.maxSize);
            }
            out.flush();
            return hex(
                MessageDigest.getInstance("SHA-256")
                    .digest(bytes.toByteArray()));
        } catch (Exception e) {
            throw new IllegalStateException("failed to compute rules fingerprint", e);
        }
    }

    private static String hex(byte[] data) {
        StringBuilder builder = new StringBuilder(data.length * 2);
        for (byte value : data) {
            builder.append(Character.forDigit((value >> 4) & 0xF, 16));
            builder.append(Character.forDigit(value & 0xF, 16));
        }
        return builder.toString();
    }
}
