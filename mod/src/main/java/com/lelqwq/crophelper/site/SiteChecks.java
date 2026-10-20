package com.lelqwq.crophelper.site;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/** 工位检查的三态汇总；已确认不满足时优先报告 blocked。 */
public final class SiteChecks {

    private SiteChecks() {}

    public static Map<String, Object> check(String name, String status, String detail) {
        Map<String, Object> result = new LinkedHashMap<String, Object>();
        result.put("name", name);
        result.put("status", status);
        result.put("detail", detail);
        return result;
    }

    public static String status(List<Map<String, Object>> checks) {
        boolean unknown = false;
        for (Map<String, Object> check : checks) {
            Object status = check.get("status");
            if ("blocked".equals(status)) return "blocked";
            if (!"pass".equals(status)) unknown = true;
        }
        return unknown || checks.isEmpty() ? "unknown" : "pass";
    }

    public static boolean parentsMatch(String left, String right, String first, String second) {
        return left != null && right != null
            && first != null
            && second != null
            && (left.equals(first) && right.equals(second) || left.equals(second) && right.equals(first));
    }

    /** 根据机器人到扫描点的水平方向推导左、右和额外邻居；拒绝远程/垂直位置。 */
    public static int[][] positions(int hostX, int hostY, int hostZ, int x, int y, int z) {
        long deltaX = (long) x - hostX;
        long deltaZ = (long) z - hostZ;
        if (y != hostY || Math.abs(deltaX) + Math.abs(deltaZ) != 1) {
            throw new IllegalArgumentException("site requires a directly adjacent horizontal crop");
        }
        int dx = (int) deltaX;
        int dz = (int) deltaZ;
        return new int[][] { { x, y, z }, { x + dz, y, z - dx }, { x - dz, y, z + dx }, { x + dx, y, z + dz },
            { hostX, hostY, hostZ } };
    }
}
