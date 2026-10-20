package com.lelqwq.crophelper.catalog;

/**
 * 品种的不可变固有信息。与 IC2 个体三围无关：这里保存的是 CropCard.stat(i)。
 *
 * <p>
 * 身份使用注册时的 owner 与原始 name 组合，显示名只用于展示。
 * </p>
 */
public final class Species {

    public final String id;
    public final String owner;
    public final String name;
    public final String displayName;
    public final int tier;
    public final int maxSize;

    private final int[] stats;
    private final String[] attributes;

    public Species(String owner, String name, String displayName, int tier, int[] stats, String[] attributes,
        int maxSize) {
        if (owner == null || owner.isEmpty()) {
            throw new IllegalArgumentException("owner must not be empty");
        }
        if (name == null || name.isEmpty()) {
            throw new IllegalArgumentException("name must not be empty");
        }
        if (stats == null || stats.length != 5) {
            throw new IllegalArgumentException("stats must contain exactly five values");
        }
        this.id = owner + ":" + name;
        this.owner = owner;
        this.name = name;
        this.displayName = displayName == null || displayName.isEmpty() ? name : displayName;
        this.tier = tier;
        this.maxSize = maxSize;
        this.stats = stats.clone();
        this.attributes = sanitize(attributes);
    }

    /** 过滤 null 标签；正常 CropCard 不会返回 null，异常数据不应破坏目录响应。 */
    private static String[] sanitize(String[] input) {
        if (input == null) {
            return new String[0];
        }
        int count = 0;
        for (String value : input) {
            if (value != null) {
                count++;
            }
        }
        if (count == input.length) {
            return input.clone();
        }
        String[] result = new String[count];
        int index = 0;
        for (String value : input) {
            if (value != null) {
                result[index++] = value;
            }
        }
        return result;
    }

    /** 第 i 项固有属性，i 取值 0..4。 */
    public int stat(int index) {
        return stats[index];
    }

    /** 返回内部数组；调用方只读。 */
    public String[] attributes() {
        return attributes;
    }
}
