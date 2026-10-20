package com.lelqwq.crophelper.site;

import java.lang.reflect.Proxy;
import java.util.Collections;
import java.util.HashMap;
import java.util.Map;

import ic2.api.crops.ICropTile;

/**
 * canGrow/canCross 的只读输入。不给作物卡真实 TileEntity 或 World 引用。
 * 未缓存的环境值返回未知，不通过调用 updateHumidity 等方法改变缓存或消耗随机数。
 */
final class ReadOnlyCropView {

    private ReadOnlyCropView() {}

    static ICropTile of(ICropTile tile) {
        if (!"ic2.core.crop.TileEntityCrop".equals(
            tile.getClass()
                .getName())) {
            throw new UnsupportedOperationException("unreviewed crop tile class");
        }
        Map<String, Object> values = new HashMap<String, Object>();
        values.put("getSize", tile.getSize());
        values.put("getGrowth", tile.getGrowth());
        values.put("getGain", tile.getGain());
        values.put("getResistance", tile.getResistance());
        values.put("getLightLevel", tile.getLightLevel());
        values.put("getHydrationStorage", tile.getHydrationStorage());
        values.put("getNutrientStorage", tile.getNutrientStorage());
        values.put("getWeedExStorage", tile.getWeedExStorage());
        cache(tile, values, "getHumidity", "humidity");
        cache(tile, values, "getNutrients", "nutrients");
        cache(tile, values, "getAirQuality", "airQuality");
        return snapshot(values, tile.getCrop() == null);
    }

    static ICropTile snapshot(Map<String, Object> source, boolean empty) {
        final Map<String, Object> values = Collections.unmodifiableMap(new HashMap<String, Object>(source));
        return (ICropTile) Proxy.newProxyInstance(
            ICropTile.class.getClassLoader(),
            new Class<?>[] { ICropTile.class },
            (proxy, method, args) -> {
                String name = method.getName();
                if (values.containsKey(name)) return values.get(name);
                // 实装 IC2 在空中央位的 isBlockBelow() 首先因 crop == null 返回 false。
                if (empty && "isBlockBelow".equals(name)) return Boolean.FALSE;
                throw new UnsupportedOperationException("crop query requires unsupported access: " + name);
            });
    }

    private static void cache(ICropTile tile, Map<String, Object> values, String getter, String field) {
        try {
            byte value = tile.getClass()
                .getField(field)
                .getByte(tile);
            if (value >= 0) values.put(getter, value);
        } catch (ReflectiveOperationException ignored) {
            // 不确定的缓存不能当作 0，真正使用该值的判断会返回 unknown。
        }
    }
}
